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
