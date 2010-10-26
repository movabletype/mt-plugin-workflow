use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT::Test;
use Test::More tests => 1;

use MT;
ok (MT->component ('Workflow'), "Workflow loaded successfully");
