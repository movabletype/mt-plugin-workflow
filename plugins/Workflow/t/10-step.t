
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT::Test qw( :db );

require MT::Object;
require_ok ('Workflow::Step');
ok (MT::Object->driver->table_exists ('Workflow::Step'), "Table exists for step data");
