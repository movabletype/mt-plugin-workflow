package Workflow::AuditLog;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'entry_id'  => 'integer not null',
        'note'      => 'text',
        'transferred_to'    => 'integer',
        'old_status'    => 'smallint not null',
        'new_status'    => 'smallint not null',
        'edited'    => 'boolean',
    },

    indexes => {
        'id'    => 1,
        'entry_id'  => 1,
    },

    audit       => 1,
    datasource  => 'workflow_audit_log',
    primary_key => 'id',
});

1;