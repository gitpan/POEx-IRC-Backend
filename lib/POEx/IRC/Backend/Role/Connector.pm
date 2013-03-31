package POEx::IRC::Backend::Role::Connector;
{
  $POEx::IRC::Backend::Role::Connector::VERSION = '0.024005';
}
use 5.10.1;
use strictures 1;

use Moo::Role;
use MooX::Types::MooseLike::Base ':all';

use namespace::clean;

with 'POEx::IRC::Backend::Role::HasWheel';

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

This role consumes L<POEx::IRC::Backend::Role::HasWheel> and adds the
following attributes:

=head2 addr

The local address we are bound to.

=head2 port

The local port we are listening on.

=head2 set_port

Change the current port attribute.

This won't trigger any automatic Wheel changes (at this time), 
but it is useful when creating a listener on port 0.

=head2 protocol

The Internet protocol version for this listener (4 or 6).

=head2 ssl

Boolean value indicating whether connections should be SSLified.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
