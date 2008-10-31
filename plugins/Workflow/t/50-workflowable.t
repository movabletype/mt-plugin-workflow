
use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT::Test qw( :cms :db :data );
use Data::Dumper;

use Test::More tests => 8;

my $mt = MT->instance;
require_ok ( 'Workflow::Workflowable' );
can_ok ('MT::Entry', 'workflow_update');

require MT::Entry;
my $e = MT::Entry->load ( 1 );

require_ok ('Workflow::AuditLog');
is (Workflow::AuditLog->count, 0, "Should be no audit logs");

is ($e->workflow_update ($e, 0, 'Note', undef), 0, "workflow_update with no direction");
ok ($e->workflow_update ($e, 1, 'Forward note', undef), "workflow_updatewith positive direction");
is (Workflow::AuditLog->count, 1, "One audit log record generated");
is (Workflow::AuditLog->load->note, 'Forward note', 'Note is in audit log');
