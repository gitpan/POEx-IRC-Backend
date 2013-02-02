package POEx::IRC::Backend;
{
  $POEx::IRC::Backend::VERSION = '0.021';
}

use 5.10.1;
use strictures 1;

use Carp;

use Moo;
use MooX::Types::MooseLike::Base ':all';

use IRC::Message::Object 'ircmsg';

use Net::IP::Minimal 'ip_is_ipv6';

use POE qw/
  Session

  Wheel::ReadWrite
  Wheel::SocketFactory
  Component::SSLify

  Filter::Stackable
  Filter::IRCv3
  Filter::Line
/;

use Socket qw/
  AF_INET
  AF_INET6
  inet_ntop
/;

use Try::Tiny;

use POEx::IRC::Backend::Connect;
use POEx::IRC::Backend::Connector;
use POEx::IRC::Backend::Listener;
use POEx::IRC::Backend::_Util;


use namespace::clean;


=pod

=for Pod::Coverage has_optional

=cut

our %_Has;
try {
  require POE::Filter::Zlib::Stream;
  $_Has{zlib} = 1
};

sub has_optional {
  my ($val) = @_;
  $_Has{$val}
}


has 'session_id' => (
  ## Session ID for own session.
  init_arg  => undef,
  lazy      => 1,
  is        => 'ro',
  writer    => '_set_session_id',
  default   => sub { undef },
);

has 'controller' => (
  ## Session ID for controller session
  ## Typically set by 'register' event
  lazy      => 1,
  is        => 'ro',
  writer    => '_set_controller',
  predicate => 'has_controller',
);

has 'filter_irc' => (
  lazy    => 1,
  isa     => InstanceOf['POE::Filter'],
  is      => 'ro',
  default => sub {
    POE::Filter::IRCv3->new(colonify => 1)
  },
);

has 'filter_line' => (
  lazy    => 1,
  isa     => InstanceOf['POE::Filter'],
  is      => 'ro',
  default => sub {
    POE::Filter::Line->new(
      InputRegexp   => '\015?\012',
      OutputLiteral => "\015\012",
    )
  },
);

has 'filter' => (
  lazy    => 1,
  isa     => InstanceOf['POE::Filter'],
  is      => 'ro',
  default => sub {
    my ($self) = @_;
    POE::Filter::Stackable->new(
      Filters => [ $self->filter_line, $self->filter_irc ],
    );
  },
);

## POEx::IRC::Backend::Listener objs
## These are listeners for a particular port.
has 'listeners' => (
  init_arg => undef,
  is      => 'ro',
  default => sub { {} },
  clearer => '_clear_listeners',
);

## POEx::IRC::Backend::Connector objs
## These are outgoing (peer) connectors.
has 'connectors' => (
  is      => 'ro',
  default => sub { {} },
  clearer => '_clear_connectors',
);

## POEx::IRC::Backend::Connect objs
## These are our connected wheels.
has 'wheels' => (
  is      => 'ro',
  default => sub { {} },
  clearer => '_clear_wheels',
);


sub spawn {
  ## Create our object and session.
  ## Returns $self
  ## Sets session_id()
  my ($class, %args) = @_;

  $args{lc $_} = delete $args{$_} for keys %args;

  my $self = ref $class ? $class : $class->new;

  my $sess_id = POE::Session->create(
    object_states => [
      $self => {
        '_start' => '_start',
        '_stop'  => '_stop',

        'register' => '_register_controller',
        'shutdown' => '_shutdown',

        'send' => '_send',

        'create_listener' => '_create_listener',
        'remove_listener' => '_remove_listener',

        '_accept_conn_v4' => '_accept_conn',
        '_accept_conn_v6' => '_accept_conn',
        '_accept_fail' => '_accept_fail',
        '_idle_alarm'  => '_idle_alarm',

        'create_connector'  => '_create_connector',
        '_connector_up_v4'  => '_connector_up',
        '_connector_up_v6'  => '_connector_up',
        '_connector_failed' => '_connector_failed',

        '_ircsock_input'    => '_ircsock_input',
        '_ircsock_error'    => '_ircsock_error',
        '_ircsock_flushed'  => '_ircsock_flushed',
      },
    ],
  )->ID;

  confess "Unable to spawn POE::Session and retrieve ID()"
    unless $sess_id;

  ## ssl_opts => [ ]
  ##  FIXME document that we need a pubkey + cert for server-side ssl
  if ($args{ssl_opts}) {
    confess "ssl_opts should be an ARRAY"
      unless ref $args{ssl_opts} eq 'ARRAY';

    my $ssl_err;
    try {
      POE::Component::SSLify::SSLify_Options(
        @{ $args{ssl_opts} }
      );

      1
    } catch {
      $ssl_err = $_;

      undef
    } or confess "SSLify failure: $ssl_err";
  }

  ## FIXME add listeners / connectors here if they're configured?

  $self
}


sub _start {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->_set_session_id( $_[SESSION]->ID );
  $kernel->refcount_increment( $self->session_id, "IRCD Running" );
}

sub _stop {

}

sub shutdown {
  my $self = shift;

  $poe_kernel->post( $self->session_id => 
    shutdown => @_ 
  );

  1
}

sub _shutdown {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->refcount_decrement( $self->session_id, "IRCD Running" );
  $kernel->refcount_decrement( $self->controller, "IRCD Running" );

  ## _disconnected should also clear our alarms.
  $self->_disconnected($_, "Server shutdown")
    for keys %{ $self->wheels // {} };

  $self->_clear_listeners;
  $self->_clear_connectors;
  $self->_clear_wheels;
}

sub _register_controller {
  ## 'register' event sets a controller session.
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $self->_set_controller( $_[SENDER]->ID );

  $kernel->refcount_increment( $self->controller, "IRCD Running" );

  $kernel->post( $self->controller => 
    ircsock_registered => $self 
  );
}

sub _accept_conn {
  ## Accepted connection to a listener.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $p_addr, $p_port, $listener_id) = @_[ARG0 .. ARG3];

  ## Our peer's addr.
  my $type = $_[STATE] eq '_accept_conn_v6' ? AF_INET6 : AF_INET;
  $p_addr = inet_ntop( $type, $p_addr );

  my $sock_packed = getsockname($sock);
  my ($protocol, $sockaddr, $sockport) = get_unpacked_addr($sock_packed);
  my $listener = $self->listeners->{$listener_id};

  if ( $listener->ssl ) {
    try {
      $sock = POE::Component::SSLify::Client_SSLify($sock)
    } catch {
      warn "Could not SSLify (server) socket: $_";
      undef
    } or return;
  }

  my $wheel = POE::Wheel::ReadWrite->new(
    Handle => $sock,
    Filter => $self->filter,
    InputEvent   => '_ircsock_input',
    ErrorEvent   => '_ircsock_error',
    FlushedEvent => '_ircsock_flushed',
  );

  unless ($wheel) {
    carp "Wheel creation failure in _accept_conn";
    return
  }

  my $w_id = $wheel->ID;

  my $this_conn = POEx::IRC::Backend::Connect->new(
    protocol => $protocol,
    wheel    => $wheel,

    peeraddr => $p_addr,
    peerport => $p_port,

    sockaddr => $sockaddr,
    sockport => $sockport,

    seen => time,
    idle => $listener->idle,
  );

  $self->wheels->{$w_id} = $this_conn;

  $this_conn->alarm_id(
    $poe_kernel->delay_set(
      '_idle_alarm',
      $this_conn->idle,
      $w_id
    )
  );

  $poe_kernel->post( $self->controller => 
    ircsock_listener_open => $this_conn, $listener
  );
}

sub _idle_alarm {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $w_id = $_[ARG0];

  my $this_conn = $self->wheels->{$w_id} || return;

  $kernel->post( $self->controller => 
    ircsock_connection_idle => $this_conn
  );

  $this_conn->alarm_id(
    $kernel->delay_set( _idle_alarm => 
      $this_conn->idle, $w_id
    )
  );
}

sub _accept_fail {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errnum, $errstr, $listener_id) = @_[ARG0 .. ARG3];

  my $listener = delete $self->listeners->{$listener_id};

  if ($listener) {
    $listener->clear_wheel;

    $kernel->post( $self->controller => 
      ircsock_listener_failure => $listener, $op, $errnum, $errstr
    );
  }
}


sub create_listener {
  my $self = shift;

  $poe_kernel->post( $self->session_id,
    'create_listener',
    @_
  );

  $self
}

sub _create_listener {
  ## Create a listener on a particular port.
  ##  bindaddr =>
  ##  port =>
  ## [optional]
  ##  ipv6 =>
  ##  ssl  =>
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  my $idle_time = delete $args{idle}     || 180;

  my $bindaddr  = delete $args{bindaddr} || '0.0.0.0';
  my $bindport  = delete $args{port}     || 0;

  my $protocol = 4;
  $protocol = 6
    if delete $args{ipv6} or ip_is_ipv6($bindaddr);

  my $ssl = delete $args{ssl} || 0;

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain => ($protocol == 6 ? AF_INET6 : AF_INET),
    BindAddress  => $bindaddr,
    BindPort     => $bindport,
    SuccessEvent => 
      ($protocol == 6 ? '_accept_conn_v6' : '_accept_conn_v4' ),
    FailureEvent => '_accept_fail',
    Reuse        => 1,
  );

  my $id = $wheel->ID;

  my $listener = POEx::IRC::Backend::Listener->new(
    protocol => $protocol,
    wheel => $wheel,
    addr  => $bindaddr,
    port  => $bindport,
    idle  => $idle_time,
    ssl   => $ssl,
  );

  $self->listeners->{$id} = $listener;

  ## Real bound port/addr
  my ($proto, $addr, $port) = get_unpacked_addr( $wheel->getsockname );
  $listener->set_port($port) if $port;

  ## Tell our controller session
  $kernel->post( $self->controller => 
    ircsock_listener_created => $listener
  );
}

sub remove_listener {
  my $self = shift;

  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  confess "remove_listener requires either port => or listener => params"
    unless defined $args{port} or defined $args{listener};

  $poe_kernel->post( $self->session_id =>
    remove_listener => @_
  );

  $self
}

sub _remove_listener {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  if (defined $args{listener} && $self->listeners->{ $args{listener} }) {
    my $listener = delete $self->listeners->{ $args{listener} };

    $listener->clear_wheel;

    $kernel->post( $self->controller =>
      ircsock_listener_removed => $listener
    );

    return
  }

  my @removed;

  LISTENER: for my $id (keys %{ $self->listeners }) {
    my $listener = $self->listeners->{$id};
    if (defined $args{port} && defined $args{addr}) {
      if ($args{addr} eq $listener->addr && $args{port} eq $listener->port) {
        delete $self->listeners->{$id};
        push @removed, $listener;
        next LISTENER
      }
    } elsif (defined $args{addr} && $args{addr} eq $listener->addr) {
      delete $self->listeners->{$id};
      push @removed, $listener;
    } elsif (defined $args{port} && $args{port} eq $listener->port) {
      delete $self->listeners->{$id};
      push @removed, $listener;
    }
  }

  for my $listener (@removed) {
    $listener->clear_wheel;
    $kernel->post( $self->controller => 
      ircsock_listener_removed => $listener 
    );
  }
}

sub create_connector {
  my $self = shift;

  $poe_kernel->post( $self->session_id =>
    create_connector => @_
  );

  $self
}

sub _create_connector {
  ## Connector; try to spawn socket <-> remote peer
  ##  remoteaddr =>
  ##  remoteport =>
  ## [optional]
  ##  bindaddr =>
  ##  ipv6 =>
  ##  ssl  =>
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args = @_[ARG0 .. $#_];

  $args{lc $_} = delete $args{$_} for keys %args;

  my $remote_addr = delete $args{remoteaddr};
  my $remote_port = delete $args{remoteport};

  confess "_create_connector expects a RemoteAddr and RemotePort"
    unless defined $remote_addr and defined $remote_port;

  my $protocol = 4;
  $protocol = 6
    if delete $args{ipv6} or ip_is_ipv6($remote_addr);

  my $wheel = POE::Wheel::SocketFactory->new(
    SocketDomain   => ($protocol == 6 ? AF_INET6 : AF_INET),
    SocketProtocol => 'tcp',

    RemoteAddress  => $remote_addr,
    RemotePort     => $remote_port,

    FailureEvent   => '_connector_failed',
    SuccessEvent   => 
      ( $protocol == 6 ? '_connector_up_v6' : '_connector_up_v4' ),

    (
      defined $args{bindaddr} ?
        ( BindAddress => delete $args{bindaddr} ) : () 
    ),
  );

  my $id = $wheel->ID;

  $self->connectors->{$id} = POEx::IRC::Backend::Connector->new(
    wheel     => $wheel,
    addr      => $remote_addr,
    port      => $remote_port,
    protocol  => $protocol,

    (defined $args{ssl}      ?
      (ssl      => delete $args{ssl}) : () ),

    (defined $args{bindaddr} ?
      (bindaddr => delete $args{bindaddr}) : () ),

    ## Attach any extra args to Connector->args()
    (keys %args ?
      (args => \%args) : () ),
  );
}


sub _connector_up {
  ## Created connector socket.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($sock, $peeraddr, $peerport, $c_id) = @_[ARG0 .. ARG3];
  
  my $type = $_[STATE] eq '_connector_up_v6' ? AF_INET6 : AF_INET;
  $peeraddr = inet_ntop( $type, $peeraddr );

  ## No need to try to connect out any more; remove from connectors pool
  my $ct = delete $self->connectors->{$c_id};

  if ( $ct->ssl ) {
    try {
      $sock = POE::Component::SSLify::Client_SSLify($sock)
    } catch {
      warn "Could not SSLify (client) socket: $_";
      undef
    } or return;
  }

  my $wheel = POE::Wheel::ReadWrite->new(
    Handle       => $sock,
    InputEvent   => '_ircsock_input',
    ErrorEvent   => '_ircsock_error',
    FlushedEvent => '_ircsock_flushed',
    Filter       => POE::Filter::Stackable->new(
      Filters => [ $self->filter ],
    )
  );

  unless ($wheel) {
    carp "Wheel creation failure in _connector_up";
    return
  }

  my $w_id = $wheel->ID;

  my $sock_packed = getsockname($sock);
  my ($protocol, $sockaddr, $sockport)
    = get_unpacked_addr($sock_packed);

  my $this_conn = POEx::IRC::Backend::Connect->new(
    protocol => $protocol,
    wheel    => $wheel,
    peeraddr => $peeraddr,
    peerport => $peerport,
    sockaddr => $sockaddr,
    sockport => $sockport,
    seen => time,
  );

  $self->wheels->{$w_id} = $this_conn;

  $kernel->post( $self->controller => 
    ircsock_connector_open => $this_conn
  );

  ## FIXME hum. should we be setting an idle_alarm?
}

sub _connector_failed {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($op, $errno, $errstr, $c_id) = @_[ARG0 .. ARG3];

  my $ct = delete $self->connectors->{$c_id};
  $ct->clear_wheel;

  $kernel->post( $self->controller =>
    ircsock_connector_failure => $ct, $op, $errno, $errstr
  );
}

## _ircsock_* handlers talk to endpoints via listeners/connectors
sub _ircsock_input {
  ## Input handler.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($input, $w_id)  = @_[ARG0, ARG1];

  ## Retrieve Backend::Connect
  my $this_conn = $self->wheels->{$w_id};

  ## Disconnecting? Don't care.
  return if $this_conn->is_disconnecting;

  ## Adjust last seen and idle alarm
  $this_conn->seen( time );
  $kernel->delay_adjust( $this_conn->alarm_id, $this_conn->idle )
    if $this_conn->has_alarm_id;

  ## FIXME configurable raw events?

  ## Send ircsock_input to controller/dispatcher
  $kernel->post( $self->controller => 
    ircsock_input => $this_conn, ircmsg(%$input)
  );
}

sub _ircsock_error {
  ## Lost someone.
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my ($errstr, $w_id) = @_[ARG2, ARG3];

  my $this_conn = $self->wheels->{$w_id} || return;

  $self->_disconnected(
    $w_id,
    $errstr || $this_conn->is_disconnecting
  );
}

sub _ircsock_flushed {
  ## Socket's been flushed; we may have something to do.
  my ($kernel, $self, $w_id) = @_[KERNEL, OBJECT, ARG0];

  my $this_conn = $self->wheels->{$w_id} || return;

  if ($this_conn->is_disconnecting) {
    $self->_disconnected(
      $w_id,
      $this_conn->is_disconnecting
    );
    return
  }

  if ($this_conn->is_pending_compress) {
    $self->set_compressed_link_now($w_id);
    return
  }

}

sub _send {
  ## POE bridge to send()
  $_[OBJECT]->send(@_[ARG0 .. $#_ ]);
}

## Methods.

sub send {
  ## ->send(HASH, ID [, ID .. ])
  my ($self, $out, @ids) = @_;

  if ( is_Object($out) ) {

    if      ( $out->isa('IRC::Message::Object') ) {
      $out = {
        prefix  => $out->prefix,
        params  => $out->params,
        command => $out->command,
        (
          $out->has_tags ? (tags => $out->tags) : ()
        )
      };
    } else {
      confess "No idea what to do with $out",
    }

  }

  unless (@ids && ref $out eq 'HASH') {
    carp "send() takes a HASH and a list of connection IDs";
    return
  }

  for my $id (grep { $self->wheels->{$_} } @ids) {
    $self->wheels->{$id}->wheel->put( $out );
  }

  $self
}

sub disconnect {
  ## Mark a wheel for disconnection.
  my ($self, $w_id, $str) = @_;

  confess "disconnect() needs a wheel ID"
    unless defined $w_id;

  confess "disconnect() called for nonexistant wheel ID $w_id"
    unless defined $self->wheels->{$w_id};

  $self->wheels->{$w_id}->is_disconnecting(
    $str || "Client disconnect"
  );

  $self
}

sub _disconnected {
  ## Wheel needs cleanup.
  my ($self, $w_id, $str) = @_;
  return unless $w_id and $self->wheels->{$w_id};

  my $this_conn = delete $self->wheels->{$w_id};

  ## Idle timer cleanup
  $poe_kernel->alarm_remove( $this_conn->alarm_id )
    if $this_conn->has_alarm_id;

  if ($^O =~ /(cygwin|MSWin32)/) {
    $this_conn->wheel->shutdown_input;
    $this_conn->wheel->shutdown_output;
  }

  ## Higher layers may still have a $conn object bouncing about.
  ## They should check ->has_wheel to determine if the Connect obj
  ## has been disconnected (no longer has a wheel).
  $this_conn->clear_wheel;

  $poe_kernel->post( $self->controller => 
    ircsock_disconnect => $this_conn, $str
  );

  1
}

sub set_compressed_link {
  my ($self, $w_id) = @_;

  confess "set_compressed_link requires POE::Filter::Zlib::Stream"
    unless has_optional('zlib');

  confess "set_compressed_link() needs a wheel ID"
    unless defined $w_id;

  return unless $self->wheels->{$w_id};

  $self->wheels->{$w_id}->is_pending_compress(1);

  $self
}

sub set_compressed_link_now {
  my ($self, $w_id) = @_;

  confess "set_compressed_link requires POE::Filter::Zlib::Stream"
    unless has_optional('zlib');

  confess "set_compressed_link() needs a wheel ID"
    unless defined $w_id;
 
  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  $this_conn->wheel->get_input_filter->unshift(
    POE::Filter::Zlib::Stream->new,
  );

  $this_conn->is_pending_compress(0);
  $this_conn->set_compressed(1);

  $poe_kernel->post( $self->controller =>
    ircsock_compressed => $this_conn
  );

  $self
}

sub unset_compressed_link {
  my ($self, $w_id) = @_;

  confess "unset_compressed_link() needs a wheel ID"
    unless defined $w_id;

  my $this_conn;
  return unless $this_conn = $self->wheels->{$w_id};

  return unless $this_conn->compressed;

  $this_conn->wheel->get_input_filter->shift;

  $this_conn->set_compressed(0);

  $self
}

## FIXME listener connect ip blacklist?

no warnings 'void';
q{
 <CaptObviousman> pretend for a moment that I'm stuck with mysql
 <rnowak> ok, fetching my laughing hat and monocle
};


=pod

=head1 NAME

POEx::IRC::Backend - IRC client or server sockets

=head1 SYNOPSIS

  ## Spawn a Backend and register as the controlling session.
  my $backend = POEx::IRC::Backend->spawn(
    ## See POE::Component::SSLify (SSLify_Options):
    ssl_opts => [ ARRAY ],
  );

  $poe_kernel->post( $backend->session_id, 'register' );

  $backend->create_listener(
    bindaddr => $addr,
    port     => $port,
    ## Optional:
    ipv6     => 1,
    ssl      => 1,
  );

  $backend->create_connector(
    remoteaddr => $remote,
    remoteport => $remoteport,
    ## Optional:
    bindaddr => $bindaddr,
    ipv6     => 1,
    ssl      => 1,
  );

  ## Handle and dispatch incoming IRC events.
  sub ircsock_input {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    ## POEx::IRC::Backend::Connect obj:
    my $this_conn = $_[ARG0];

    ## IRC::Message::Object obj:
    my $input_obj = $_[ARG1];

    my $cmd = $input_obj->command;

    ## ... dispatch, etc ...
  }

=head1 DESCRIPTION

A L<POE> IRC backend socket handler using L<POE::Filter::IRCv3> and
L<IRC::Toolkit>.

This can be used by client/server libraries to speak IRC protocol via
L<IRC::Message::Object> objects.

This module is part of a set of IRC building blocks that have been 
split out of a much larger project; it is also early 'alpha-quality' software.
Take a gander at L<POE::Component::IRC> for a fully-featured IRC library.


=head2 Attributes

=head3 controller

Retrieve the L<POE::Session> ID for the backend's registered controller.

Predicate: B<has_controller>

=head3 connectors

A HASH of active Connector objects, keyed on their wheel ID.

=head3 filter

A L<POE::Filter::Stackable> instance consisting of the current L</filter_irc>
stacked with L</filter_line> (at the time the attribute is built).

=head3 filter_irc

A L<POE::Filter::IRCv3> instance with B<colonify> enabled, by default.

A client-side Backend will probably want a non-colonifying filter:

  my $backend = POEx::IRC::Backend->new(
    filter_irc => POE::Filter::IRCv3->new(colonify => 0),
    ...
  );

=head3 filter_line

A L<POE::Filter::Line> instance.

=head3 listeners

HASH of active Listener objects, keyed on their wheel ID.

=head3 session_id

Returns the backend's session ID.

=head3 wheels

HASH of actively connected wheels, keyed on their wheel ID.


=head2 Methods

=head3 spawn

  my $backend = POEx::IRC::Backend->spawn(
    ## Optional, needed for SSL-ified server-side sockets
    ssl_opts => [
      'server.key',
      'server.cert',
    ],
  );

=head3 create_connector

  $backend->create_connector(
    remoteaddr => $addr,
    remoteport => $addr,
    ## Optional:
    bindaddr => $local_addr,
    ipv6 => 1,
    ssl  => 1,
  );

Attempts to create a L<POEx::IRC::Backend::Connector> that 
holds a L<POE::Wheel::SocketFactory> connector wheel; connectors will 
attempt to establish an outgoing connection immediately.

=head3 create_listener

  $backend->create_listener(
    bindaddr => $addr,
    port     => $port,
    ## Optional:
    ipv6     => 1,
    ssl      => 1,
    idle     => $seconds,
  );

Attempts to create a L<POEx::IRC::Backend::Listener> 
that holds a L<POE::Wheel::SocketFactory> listener wheel.

=head3 remove_listener

    $backend->remove_listener(
      listener => $listener_id,
    );

    ## or via addr, port, or combination thereof:
    $backend->remove_listener(
      addr => '127.0.0.1',
      port => 6667,
    );

Removes a listener and clears its B<wheel> attribute; the socket shuts down
when the L<POE::Wheel::SocketFactory> wheel goes out of scope.

=head3 disconnect

  $backend->disconnect($wheel_id, $disconnect_string);

Given a connection's wheel ID, mark the specified wheel for 
disconnection.

=head3 send

  $backend->send(
    {
      prefix  => $prefix,
      params  => [ @params ],
      command => $cmd,
    },
    @connect_ids
  );

  use IRC::Message::Object 'ircmsg';
  my $msg = ircmsg(
    command => 'PRIVMSG',
    params  => [ $chan, $string ],
  );
  $backend->send( $msg, $connect_id );

Feeds L<POE::Filter::IRCv3> and sends the resultant raw IRC 
line to the specified connection wheel ID(s).

Accepts either an L<IRC::Message::Object> or a HASH compatible with
L<POE::Filter::IRCv3> -- look there for details.

=head3 set_compressed_link

  $backend->set_compressed_link( $conn_id );

Mark a specified connection wheel ID as pending compression; 
L<POE::Filter::Zlib::Stream> will be added to the filter stack when the 
next flush event arrives.

=head3 set_compressed_link_now

  $backend->set_compressed_link_now( $conn_id );

Add a L<POE::Filter::Zlib::Stream> to the connection's filter stack 
immediately, rather than upon next flush event.

=head3 unset_compressed_link

  $backend->unset_compressed_link( $conn_id );

Remove L<POE::Filter::Zlib::Stream> from the connection's filter stack.


=head2 Received events

=head3 register

  $poe_kernel->post( $backend->session_id,
    'register'
  );

Register the sender session as the backend's controller session. The last 
session to send 'register' is the session that receives notification 
events from the backend component.

=head3 create_connector

Event interface to I<create_connector> -- see L</Methods>

=head3 create_listener

Event interface to I<create_listener> -- see L</Methods>

=head3 remove_listener

Event interface to I<remove_listener> -- see L</Methods>

=head3 send

Event interface to I</send> -- see L</Methods>

=head3 shutdown

Disconnect all wheels and clean up.


=head2 Dispatched events

These events are dispatched to the controller session; see L</register>.

=head3 ircsock_compressed

Dispatched when a connection wheel has had a compression filter added.

C<$_[ARG0]> is the connection's 
L<POEx::IRC::Backend::Connect>

=head3 ircsock_connection_idle

Dispatched when a connection wheel has had no input for longer than 
specified idle time (see L</create_listener> regarding idle times).

C<$_[ARG0]> is the connection's 
L<POEx::IRC::Backend::Connect>

=head3 ircsock_connector_failure

Dispatched when a Connector has failed due to some sort of socket error.

C<$_[ARG0]> is the connection's 
L<POEx::IRC::Backend::Connector> with wheel() cleared.

C<@_[ARG1 .. ARG3]> contain the socket error details reported by 
L<POE::Wheel::SocketFactory>; operation, errno, and errstr, respectively.

=head3 ircsock_connector_open

Dispatched when a Connector has established a connection to a peer.

C<$_[ARG0]> is the L<POEx::IRC::Backend::Connect> for the 
connection.

=head3 ircsock_disconnect

Dispatched when a connection wheel has been cleared.

C<$_[ARG0]> is the connection's L<POEx::IRC::Backend::Connect> 
with wheel() cleared.

=head3 ircsock_input

Dispatched when there is some IRC input from a connection wheel.

C<$_[ARG0]> is the connection's 
L<POEx::IRC::Backend::Connect>.

C<$_[ARG1]> is an L<IRC::Message::Object>.

=head3 ircsock_listener_created

Dispatched when a L<POEx::IRC::Backend::Listener> has been 
created.

C<$_[ARG0]> is the L<POEx::IRC::Backend::Listener> instance; 
the instance's port() is altered based on getsockname() details after 
socket creation and before dispatching this event.

=head3 ircsock_listener_failure

Dispatched when a Listener has failed due to some sort of socket error.

C<$_[ARG0]> is the L<POEx::IRC::Backend::Listener> object.

C<@_[ARG1 .. ARG3]> contain the socket error details reported by 
L<POE::Wheel::SocketFactory>; operation, errno, and errstr, respectively.

=head3 ircsock_listener_open

Dispatched when a listener accepts a connection.

C<$_[ARG0]> is the connection's L<POEx::IRC::Backend::Connect>

C<$_[ARG1]> is the connection's L<POEx::IRC::Backend::Listener>

=head3 ircsock_listener_removed

Dispatched when a Listener has been removed.

C<$_[ARG0]> is the L<POEx::IRC::Backend::Listener> object.

=head3 ircsock_registered

Dispatched when a L</register> event has been successfully received, as a 
means of acknowledging the controlling session.

C<$_[ARG0]> is the Backend's C<$self> object.


=head1 BUGS

Probably lots. Please report them via RT, e-mail, or GitHub
(L<http://github.com/avenj/poex-irc-backend>).

Tests are a bit incomplete, as of this writing. 
Zlib and SSL are mostly untested.

=head1 SEE ALSO

L<IRC::Toolkit>

L<POE::Filter::IRCv3>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Inspiration derived from L<POE::Component::Server::IRC::Backend> and
L<POE::Component::IRC> by BINGOS, HINRIK et al

=cut

