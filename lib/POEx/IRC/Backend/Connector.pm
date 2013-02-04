package POEx::IRC::Backend::Connector;
{
  $POEx::IRC::Backend::Connector::VERSION = '0.023';
}

use 5.10.1;
use strictures 1;

use Carp;
use Moo;
use MooX::Types::MooseLike::Base ':all';

use namespace::clean;


has 'addr' => (
  required => 1,
  is       => 'ro',
  writer   => 'set_addr',
);

has 'args' => (
  lazy    => 1,
  is      => 'ro',
  writer  => 'set_args',
  default => sub { {} },
);

has 'bindaddr' => (
  lazy      => 1,
  is        => 'ro',
  predicate => 'has_bindaddr',
  writer    => 'set_bindaddr',
  default => sub { '' },
);

has 'port' => (
  required => 1,
  is       => 'ro',
  writer   => 'set_port',
);

has 'protocol' => (
  required => 1,
  is       => 'ro',
  writer   => 'set_protocol',
);

has 'ssl' => (
  is        => 'ro',
  predicate => 'has_ssl',
  writer    => 'set_ssl',
  default   => sub { 0 },
);

has 'wheel_id' => (
  lazy => 1,
  is   => 'ro',
  writer    => 'set_wheel_id',
  predicate => 'has_wheel_id',
);

has 'wheel' => (
  required  => 1,
  isa       => InstanceOf['POE::Wheel'],
  is        => 'ro',
  clearer   => 'clear_wheel',
  writer    => 'set_wheel',
  predicate => 'has_wheel',
  trigger   => sub {
    my ($self, $wheel) = @_;
    $self->set_wheel_id( $wheel->ID )
  },
);


1;

=pod

=head1 NAME

POEx::IRC::Backend::Connector - Connector socket details

=head1 SYNOPSIS

Created by L<POEx::IRC::Backend> for outgoing connector sockets.

=head1 DESCRIPTION

These objects contain details regarding 
L<POEx::IRC::Backend> outgoing connector sockets.

All of these attributes can be set via C<set_$attrib> :

=head2 addr

The remote address this Connector is intended for; also see L</port>

=head2 bindaddr

The local address this Connector should bind to.

=head2 args

Arbitrary metadata attached to this Connector. (By default, this is a HASH.)

=head2 port

The remote port this Connector is intended for; also see L</addr>

=head2 protocol

The Internet protocol version this Connector was spawned for; either 4 or 
6.

=head2 ssl

Boolean value indicating whether or not this Connector should be 
SSLified at connect time.

=head2 wheel

The L<POE::Wheel::SocketFactory> for this Connector.

=head2 wheel_id

The (last known) wheel ID.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
