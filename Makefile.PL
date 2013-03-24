
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "IRC client or server backend",
  "AUTHOR" => "Jon Portnoy <avenj\@cobaltirc.org>",
  "BUILD_REQUIRES" => {
    "Test::More" => "0.88"
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "POEx-IRC-Backend",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "POEx::IRC::Backend",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Exporter" => 0,
    "IRC::Toolkit" => 0,
    "Moo" => 1,
    "MooX::Types::MooseLike" => "0.15",
    "Net::IP::Minimal" => "0.04",
    "POE" => "1.3",
    "POE::Filter::IRCv3" => 0,
    "POE::Filter::Line" => 0,
    "POE::Filter::Stackable" => 0,
    "POE::Wheel::ReadWrite" => 0,
    "POE::Wheel::SocketFactory" => 0,
    "Scalar::Util" => 0,
    "Socket" => 2,
    "Try::Tiny" => 0,
    "namespace::clean" => 0,
    "strictures" => 1
  },
  "VERSION" => "0.024003",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



