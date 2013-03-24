package POEx::IRC::Backend::_Util;
{
  $POEx::IRC::Backend::_Util::VERSION = '0.024003';
}
use strictures 1;
use Carp;

use Exporter 'import';
our @EXPORT = qw/
  get_unpacked_addr
/;

use Socket qw/
  AF_INET
  AF_INET6
  inet_ntop
  sockaddr_family
  unpack_sockaddr_in
  unpack_sockaddr_in6
/;

sub get_unpacked_addr {
  ## v4/v6-compat address unpack.
  ## FIXME should probably be using getnameinfo
  my ($sock_packed) = @_;
  confess "No address passed to get_unpacked_addr"
    unless defined $sock_packed;
  my $sock_family = sockaddr_family($sock_packed);
  my ($inet_proto, $sockaddr, $sockport);
  FAMILY: {
    if ($sock_family == AF_INET6) {
      ($sockport, $sockaddr) = unpack_sockaddr_in6($sock_packed);
      $sockaddr   = inet_ntop(AF_INET6, $sockaddr);
      $inet_proto = 6;
      last FAMILY
    }
    if ($sock_family == AF_INET) {
      ($sockport, $sockaddr) = unpack_sockaddr_in($sock_packed);
      $sockaddr   = inet_ntop(AF_INET, $sockaddr);
      $inet_proto = 4;
      last FAMILY
    }
    confess "Unknown socket family type"
  }
  ($inet_proto, $sockaddr, $sockport)
}

1;

=pod

=for Pod::Coverage get_unpacked_addr

=cut
