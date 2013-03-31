package POEx::IRC::Backend::Connector;
{
  $POEx::IRC::Backend::Connector::VERSION = '0.024005';
}
use strictures 1;
use Moo;
use namespace::clean;

with 'POEx::IRC::Backend::Role::Connector';

has args => (
  lazy    => 1,
  is      => 'ro',
  default => sub { {} },
);

has bindaddr => (
  lazy      => 1,
  is        => 'ro',
  predicate => 'has_bindaddr',
  default   => sub { '' },
);

1;

=pod

=head1 NAME

POEx::IRC::Backend::Connector - An outgoing connector

=head1 SYNOPSIS

Created by L<POEx::IRC::Backend> for outgoing connector sockets.

=head1 DESCRIPTION

These objects contain details regarding 
L<POEx::IRC::Backend> outgoing connector sockets.

This class consumes L<POEx::IRC::Backend::Role::Connector> and adds the
following attributes:

=head2 bindaddr

The local address this Connector should bind to.

B<has_bindaddr> can be used to find out if we have a local bind address
specified.

=head2 args

Arbitrary metadata attached to this Connector. (By default, this is a HASH.)

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
