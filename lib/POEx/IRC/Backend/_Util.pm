package POEx::IRC::Backend::_Util;
{
  $POEx::IRC::Backend::_Util::VERSION = '0.024005';
}
use strictures 1;
use Carp;

use Exporter 'import';
our @EXPORT = qw/
  get_unpacked_addr
/;

use Socket qw/
  getnameinfo
  NI_NUMERICHOST
  NI_NUMERICSERV
  NIx_NOSERV
/;

sub get_unpacked_addr {
  my ($sock_packed, %params) = @_;

  my ($err, $addr, $port) = getnameinfo $sock_packed,
     NI_NUMERICHOST | NI_NUMERICSERV,
      ( $params{noserv} ? NIx_NOSERV : () );

  croak $err if $err;

  $params{noserv} ? $addr : ($addr, $port)
}

1;

=pod

=for Pod::Coverage get_unpacked_addr

=cut
