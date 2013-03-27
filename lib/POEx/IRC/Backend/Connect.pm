package POEx::IRC::Backend::Connect;
{
  $POEx::IRC::Backend::Connect::VERSION = '0.024004';
}

use 5.10.1;
use strictures 1;
use Carp;

use Moo;
use MooX::Types::MooseLike::Base ':all';

use namespace::clean;

with 'POEx::IRC::Backend::Role::HasWheel';

has alarm_id => (
  ## Idle alarm ID.
  lazy      => 1,
  is        => 'rw',
  predicate => 'has_alarm_id',
  default   => sub { 0 },
);


has compressed => (
  ## zlib filter added.
  lazy    => 1,
  is      => 'rwp',
  writer  => 'set_compressed',
  default => sub { 0 },
);


has idle => (
  ## Idle delay.
  lazy    => 1,
  is      => 'rwp',
  default => sub { 180 },
);


has is_client => (
  lazy    => 1,
  is      => 'rw',
  default => sub { 0 },
);


has is_peer => (
  lazy    => 1,
  is      => 'rw',
  default => sub { 0 },
);


has is_disconnecting => (
  ## Bool or string (disconnect message)
  is      => 'rw',
  default => sub { 0 },
);


has is_pending_compress => (
  ## Wheel needs zlib filter after a socket flush.
  is      => 'rw',
  default => sub { 0 },
);


has peeraddr => (
  required => 1,
  isa      => Str,
  is       => 'ro',
  writer   => 'set_peeraddr',
);


has peerport => (
  required => 1,
  is       => 'ro',
  writer   => 'set_peerport',
);

has ping_pending => (
  lazy    => 1,
  is      => 'rw',
  default => sub { 0 },
);

has protocol => (
  ## 4 or 6.
  required => 1,
  is       => 'ro',
);


has seen => (
  ## TS of last activity on this Connect.
  lazy    => 1,
  is      => 'rw',
  default => sub { 0 },
);


has sockaddr => (
  required => 1,
  isa      => Str,
  is       => 'ro',
  writer   => 'set_sockaddr',
);


has sockport => (
  required => 1,
  is       => 'ro',
  writer   => 'set_sockport',
);


1;

=pod

=head1 NAME

POEx::IRC::Backend::Connect - A connectoed socket wheel

=head1 SYNOPSIS

Typically created by L<POEx::IRC::Backend> to represent an established
connection.

=head1 DESCRIPTION

These objects contain details regarding connected socket 
L<POE::Wheel::ReadWrite> wheels managed by 
L<POEx::IRC::Backend>.

Consumes L<POEx::IRC::Backend::Role::HasWheel> and adds the following
attributes:

=head2 alarm_id

Connected socket wheels normally have a POE alarm ID attached for an idle 
timer. Writable attribute.

=head2 compressed

Set to true if the Zlib filter has been added.

=head2 set_compressed

Change the boolean value of the L</compressed> attrib.

=head2 idle

Idle time used for connection check alarms.

=head2 is_disconnecting

Boolean false if the Connect is not in a disconnecting state; if it is 
true, it is the disconnect message:

  $obj->is_disconnecting("Client quit")

=head2 is_client

Boolean true if the connection wheel has been marked as a client.

=head2 is_peer

Boolean true if the connection wheel has been marked as a peer.

=head2 is_pending_compress

Boolean true if the Wheel needs a Zlib filter.

  $obj->is_pending_compress(1)

=head2 peeraddr

The remote peer address.

=head2 peerport

The remote peer port.

=head2 protocol

The protocol in use (4 or 6).

=head2 seen

Timestamp; should be updated when traffic is seen from this Connect:

  ## In an input handler
  $obj->seen( time )

=head2 sockaddr

Our socket address.

=head2 sockport

Our socket port.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=for Pod::Coverage set_(?:peer|sock)(?:addr|port)

=cut
