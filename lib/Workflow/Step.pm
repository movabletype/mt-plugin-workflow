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
    require Workflow::StepAssocation;
    
    my @assocs = Workflow::StepAssocation->load ({ blog_id => $obj->blog_id, step_id => $obj->id });
    my @authors;
    foreach my $assoc (@assocs) {
        push @authors, $assoc->authors;
    }
    
    # Just in case, filter out dupes
    my %seen = ();
    @authors = grep { $seen{$_->id}++ } @authors;
    @authors;
}


1;
