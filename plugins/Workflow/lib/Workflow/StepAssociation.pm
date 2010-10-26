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

package Workflow::StepAssociation;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'blog_id'   => 'integer not null',
        'step_id'   => 'integer not null',
        'type'      => 'string(10)', # author, group, role, etc
        'assoc_id'  => 'integer not null',
    },

    indexes => {
        'id'    => 1,
        'blog_id'   => 1,
        'step_id'   => 1,
    },

    audit       => 1,
    datasource  => 'workflow_step_association',
    primary_key => 'id',
});

use constant AUTHOR => 'author';
use constant GROUP  => 'group';
use constant ROLE   => 'role';

use Exporter;
*import = \&Exporter::import;
use vars qw( @EXPORT_OK %EXPORT_TAGS);
@EXPORT_OK = qw( AUTHOR GROUP ROLE );
%EXPORT_TAGS = (constants => [ qw(AUTHOR GROUP ROLE) ]);

sub class_label {
    MT->translate ('Step Association');
}

sub class_label_plural {
    MT->translate ('Step Associations');
}

sub authors {
    my $obj = shift;

    require MT::Author;
    if (AUTHOR eq $obj->type) {
        return (MT::Author->load ($obj->assoc_id));
    }
    elsif (GROUP eq $obj->type) {
        # ???
    }
    elsif (ROLE eq $obj->type) {
        require MT::Association;
        my @authors = MT::Author->load ({}, {
            join    => MT::Association->join_on ('author_id', {
                role_id => $obj->assoc_id,
                blog_id => $obj->blog_id,
            }),
        });
        # my @assocs = MT::Association->load ({ blog_id => $obj->blog_id, role_id => $obj->assoc_id });
        # my @authors;
        # foreach my $assoc (@assocs) {
        #     next if (!$assoc->author_id);
        #     my $author = MT::Author->load ($assoc->author_id);
        #     push @authors, $author if ($author);
        # }
        return @authors;
    }
}

1;
