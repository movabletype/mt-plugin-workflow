package Workflow::Status;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'                => 'integer not null primary key auto_increment',
        'object_id'         => 'integer not null',
        'object_datasource' => 'string(50) not null',
        'owner_id'          => 'integer not null',
        'previous_owner_id' => 'integer not null',
        'step_id'           => 'integer not null',
    },

    indexes => {
        'id'    => 1,
        'object_id' => 1,
        'step_id'   => 1,
    },
    
    defaults => {
        'step_id'   => 0,
    },

    audit       => 1,
    datasource  => 'workflow_status',
    primary_key => 'id',
});

sub class_label {
    MT->translate ('Workflow Step');
}

sub step {
    my $obj = shift;
    return undef if (!$obj->step_id);
    require Workflow::Step;
    return Workflow::Step->load ($obj->step_id);
}


1;
