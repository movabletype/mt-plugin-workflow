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

package Workflow::Step;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'blog_id'   => 'integer not null',
        'name'      => 'string(80)',
        'description'   => 'text',
        'order'     => 'smallint not null',
    },

    indexes => {
        'id'    => 1,
        'blog_id'   => 1,
    },

    audit       => 1,
    datasource  => 'workflow_step',
    primary_key => 'id',
});

sub class_label {
    MT->translate ('Step');
}

sub class_label_plural {
    MT->translate ('Steps');
}

sub next {
    my $obj = shift;
    my $class = ref ($obj);
    return $class->load ({ blog_id => $obj->blog_id }, { limit => 1, direction => 'ascend', sort => 'order', start_val => $obj->order });
}

sub previous {
    my $obj = shift;
    my $class = ref ($obj);
    return $class->load ({ blog_id => $obj->blog_id }, { limit => 1, direction => 'descend', sort => 'order', start_val => $obj->order });
}

sub members {
    my $obj = shift;
    require Workflow::StepAssociation;

    my @assocs = Workflow::StepAssociation->load ({ blog_id => $obj->blog_id, step_id => $obj->id });
    my @authors;
    foreach my $assoc (@assocs) {
        push @authors, $assoc->authors;
    }

    # Just in case, filter out dupes
    my %seen = ();
    @authors = grep { !$seen{$_->id}++ } @authors;
    @authors;
}

sub first_step {
    my $class = shift;
    my ($blog_id) = @_;
    return $class->load ({ blog_id => $blog_id }, { limit => 1, direction => 'ascend', sort => 'order' });
}

sub last_step {
    my $class = shift;
    my ($blog_id) = @_;
    return $class->load ({ blog_id => $blog_id }, { limit => 1, direction => 'descend', sort => 'order' });
}

1;
