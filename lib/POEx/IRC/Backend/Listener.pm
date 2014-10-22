package POEx::IRC::Backend::Listener;
$POEx::IRC::Backend::Listener::VERSION = '0.024006';
use Types::Standard -types;

use Moo; use MooX::late;
with 'POEx::IRC::Backend::Role::Connector';

has idle  => (
  lazy    => 1,
  isa     => StrictNum,
  is      => 'ro',
  writer  => 'set_idle',
  default => sub { 180 },
);

1;

=pod

=head1 NAME

POEx::IRC::Backend::Listener - An incoming connection Listener

=head1 SYNOPSIS

Typically created by L<POEx::IRC::Backend> to represent a listening socket.

=head1 DESCRIPTION

These objects contain details regarding L<POEx::IRC::Backend> 
Listener sockets.

This class consumes L<POEx::IRC::Backend::Role::Connector> and adds the
following attributes:

=head2 idle

Interval, in seconds, at which an idle alarm event should be issued for
connections to this listener (default: 180)

Can be altered via B<set_idle>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
