############################################################################
# Copyright © 2006-2010 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

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
