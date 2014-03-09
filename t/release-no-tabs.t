
BEGIN {
  unless ($ENV{RELEASE_TESTING}) {
    require Test::More;
    Test::More::plan(skip_all => 'these tests are for release candidate testing');
  }
}

use strict;
use warnings;

# this test was generated with Dist::Zilla::Plugin::NoTabsTests 0.06

use Test::More 0.88;
use Test::NoTabs;

my @files = (
    'lib/POEx/IRC/Backend.pm',
    'lib/POEx/IRC/Backend/Connect.pm',
    'lib/POEx/IRC/Backend/Connector.pm',
    'lib/POEx/IRC/Backend/Listener.pm',
    'lib/POEx/IRC/Backend/Role/Connector.pm',
    'lib/POEx/IRC/Backend/Role/HasWheel.pm',
    'lib/POEx/IRC/Backend/_Util.pm'
);

notabs_ok($_) foreach @files;
done_testing;
