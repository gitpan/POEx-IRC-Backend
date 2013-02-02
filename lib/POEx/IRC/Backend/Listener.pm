package POEx::IRC::Backend::Listener;
{
  $POEx::IRC::Backend::Listener::VERSION = '0.021';
}

use 5.10.1;
use strictures 1;
use Carp;

use Moo;
use MooX::Types::MooseLike::Base ':all';

use namespace::clean;

has 'addr'  => (
  required => 1,
  isa      => Str,
  is       => 'ro',
  writer   => 'set_addr',
);

has 'idle'  => (
  lazy => 1,
  isa => Num,
  is  => 'ro',

  predicate => 'has_idle',
  writer    => 'set_idle',

  default => sub { 0 },
);

has 'port'  => (
  required => 1,
  is       => 'ro',
  writer   => 'set_port',
);

has 'protocol' => (
  required => 1,
  is       => 'ro',
  writer   => 'set_protocol',
);

has 'ssl'   => (
  is        => 'ro',
  predicate => 'has_ssl',
  writer    => 'set_ssl',
  default   => sub { 0 },
);

has 'wheel_id' => (
  lazy   => 1,
  isa    => Defined,
  is     => 'ro',
  writer => 'set_wheel_id',
);

has 'wheel' => (
  required => 1,

  isa => InstanceOf['POE::Wheel'],
  is  => 'ro',

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

POEx::IRC::Backend::Listener - Listener socket details

=head1 SYNOPSIS

Typically created by L<POEx::IRC::Backend> to represent a listening socket.

=head1 DESCRIPTION

These objects contain details regarding L<POEx::IRC::Backend> 
Listener sockets.

=head2 addr

The local address to bind to.

=head2 port

The local port to listen on.

=head2 protocol

The internet protocol version to use for this listener (4 or 6).

=head2 ssl

Boolean value indicating whether or not connections to this listener 
should be SSLified.

=head2 wheel

The L<POE::Wheel::SocketFactory> instance for this listener.

=head2 wheel_id

The (last known) wheel ID.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
