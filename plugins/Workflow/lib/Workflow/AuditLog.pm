package Workflow::AuditLog;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'                => 'integer not null primary key auto_increment',
        'object_id'         => 'integer not null',
        'object_datasource' => 'string(50) not null',
        'note'              => 'text',
        'transferred_from'  => 'integer',
        'transferred_to'    => 'integer',
        'old_status'        => 'smallint',
        'new_status'        => 'smallint',
        'old_step_id'       => 'integer not null',
        'new_step_id'       => 'integer not null',
        'edited'            => 'boolean',
    },

    indexes => {
        'id'    => 1,
        'object_id'  => 1,
        'object_datasource'  => 1,
        'old_step_id'  => 1,
        'new_step_id'  => 1,
    },

    defaults => {
	    'new_step_id'   => 0,
	    'old_step_id'   => 0,
    },

    audit       => 1,
    datasource  => 'workflow_audit_log',
    primary_key => 'id',
});

sub class_label {
    MT->translate ('Audit Log');
}

sub class_label_plural {
    MT->translate ('Audit Logs');
}


1;