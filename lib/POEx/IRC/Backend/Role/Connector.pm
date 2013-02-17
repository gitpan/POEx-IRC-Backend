package POEx::IRC::Backend::Role::Connector;
{
  $POEx::IRC::Backend::Role::Connector::VERSION = '0.024000';
}
use 5.10.1;
use strictures 1;

use Moo::Role;
use MooX::Types::MooseLike::Base ':all';

use namespace::clean;


has addr => (
  required => 1,
  is       => 'ro',
);

has port => (
  required => 1,
  is       => 'ro',
  writer   => 'set_port',
);

has protocol => (
  required => 1,
  is       => 'ro',
);

has ssl => (
  is      => 'ro',
  default => sub { 0 },
);

has wheel_id => (
  lazy    => 1,
  isa     => Defined,
  is      => 'ro',
  writer  => '_set_wheel_id',
);

has wheel => (
  required  => 1,
  isa       => InstanceOf['POE::Wheel'],
  is        => 'ro',
  clearer   => 'clear_wheel',
  writer    => 'set_wheel',
  predicate => 'has_wheel',
  trigger   => sub {
    my ($self, $wheel) = @_;
    $self->_set_wheel_id( $wheel->ID )
  },
);

1;

=pod

=head1 NAME

POEx::IRC::Backend::Role::Connector

=head1 SYNOPSIS

A Moo::Role defining some basic common attributes for listening/connecting
sockets.

=head1 DESCRIPTION

This role is consumed by L<POEx::IRC::Backend::Connector> and 
L<POEx::IRC::Backend::Listener> objects; it defines some basic attributes
shared by listening/connecting sockets.

=head2 addr

The local address we are bound to.

=head2 port

The local port we are listening on.

=for Pod::Coverage set_port

B<set_port> can be used to alter the current port attribute.
This won't trigger any automatic L</wheel> changes (at this time), 
but it is useful when creating a listener on port 0.

=head2 protocol

The Internet protocol version for this listener (4 or 6).

=head2 ssl

Boolean value indicating whether connections should be SSLified.

=head2 wheel

The L<POE::Wheel::SocketFactory> instance for this listener.

Can be cleared via B<clear_wheel>; use B<has_wheel> to determine if this
listener's wheel has been cleared.

Can be replaced via B<set_wheel> (although whether this is a good idea or not
is debatable; better to spawn a new instance of your class)

=head2 wheel_id

The POE ID of the last known L</wheel>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
