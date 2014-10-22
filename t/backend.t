use Test::More;
use strict; use warnings FATAL => 'all';

use POE;

use_ok( 'POEx::IRC::Backend' );
use_ok( 'IRC::Message::Object', 'ircmsg' );

my $expected = {
  'got registered'       => 1,
  'got listener_created' => 1,
  'got connector_open'   => 1,
  'got listener_open'    => 1,
  'got ircsock_input'    => 2,
#  'got disconnect'       => 1,
};
my $got = {};


POE::Session->create(
  package_states => [
    main => [ qw/
      _start
      shutdown
      ircsock_registered

      ircsock_connector_open
      ircsock_listener_created
      ircsock_listener_removed
      ircsock_listener_failure
      ircsock_listener_open
      ircsock_disconnect
      ircsock_input
    / ],
  ],
);

sub _start {
  $_[HEAP] = new_ok( 'POEx::IRC::Backend' );
  my ($k, $backend) = @_[KERNEL, HEAP];
  $k->delay( shutdown => 30 => 'timeout' );
  $backend->spawn;
  $k->post( $backend->session_id, 'register' );
  $backend->create_listener(
    protocol => 4,
    bindaddr => '127.0.0.1',
    port     => 0,
  );
}

sub shutdown {
  my ($k, $backend) = @_[KERNEL, HEAP];
  $k->alarm_remove_all;
  $k->post( $backend->session_id, 'shutdown' );
  if ($_[ARG0] && $_[ARG0] eq 'timeout') {
    fail("Timed out")
  }
}

sub ircsock_registered {
  $got->{'got registered'}++;
  isa_ok( $_[ARG0], 'POEx::IRC::Backend' );
}

sub ircsock_listener_created {
  my ($k, $backend) = @_[KERNEL, HEAP];
  my $listener = $_[ARG0];

  $got->{'got listener_created'}++;

  isa_ok( $listener, 'POEx::IRC::Backend::Listener' );

  $backend->create_connector(
    remoteaddr => $listener->addr,
    remoteport => $listener->port,
  );
}

sub ircsock_connector_open {
  my ($k, $backend) = @_[KERNEL, HEAP];
  my $conn = $_[ARG0];

  $got->{'got connector_open'}++;

  isa_ok( $conn, 'POEx::IRC::Backend::Connect' );

  $backend->send(
    {
      command => 'CONNECTOR',
      params  => [ 'testing', 'things' ],
    },
    $conn->wheel_id
  );
}

sub ircsock_listener_removed {
  ## FIXME test listener_removed
}

sub ircsock_listener_failure {
  my ($op, $errno, $errstr) = @_[ARG1 .. ARG3];
  BAIL_OUT("Failed listener creation: $op ($errno) $errstr");
}

sub ircsock_listener_open {
  my ($k, $backend) = @_[KERNEL, HEAP];
  my ($conn, $listener) = @_[ARG0 .. $#_];

  $got->{'got listener_open'}++;

  isa_ok( $conn, 'POEx::IRC::Backend::Connect' );

  $backend->send(
    ircmsg(
      prefix  => 'listener',
      command => 'test',
      params  => [ 'testing', 'stuff' ],
    ),
    $conn->wheel_id
  );
}

sub ircsock_disconnect {
  ## FIXME test listener removal first
  my ($k, $backend) = @_[KERNEL, HEAP];
  $got->{'got disconnect'}++;
  $k->yield( shutdown => 1 )
}

sub ircsock_input {
  my ($k, $backend) = @_[KERNEL, HEAP];
  my ($conn, $ev)   = @_[ARG0 .. $#_];

  $got->{'got ircsock_input'}++;

  isa_ok( $conn, 'POEx::IRC::Backend::Connect' );
  isa_ok( $ev, 'IRC::Message::Object' );

  ## FIXME test ->disconnect() behavior
  ##  - add disconnect_now?
  if ($got->{'got ircsock_input'} == $expected->{'got ircsock_input'}) {
    #$backend->disconnect( $conn->wheel_id );
    $k->yield( shutdown => 1 )
  }
}


$poe_kernel->run;

TEST: for my $name (keys %$expected) {
  ok( defined $got->{$name}, "have result for '$name'")
    or next TEST;
  cmp_ok( $expected->{$name}, '==', $got->{$name}, 
    "correct result for '$name'"
  );
}

done_testing;
