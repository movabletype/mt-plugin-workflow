use strict;
use warnings;

use File::Spec;

my $mt_home; 
BEGIN {
    $mt_home = $ENV{MT_HOME} || '';
    unshift @INC, File::Spec->catdir ($mt_home, 'lib'), File::Spec->catdir ($mt_home, 'extlib');
}

use Test::More tests => 1;

use MT;

my $mt = MT->instance or die MT->errstr;

ok (MT->component ('workflow'), "Workflow loading");