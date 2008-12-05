package Workflow::StepAssociation;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'blog_id'   => 'integer',
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
    my $sa = shift;
    my ($obj) = @_;
    
    require MT::Author;
    if (AUTHOR eq $sa->type) {
        return (MT::Author->load ($sa->assoc_id));
    }
    elsif (GROUP eq $sa->type) {
        # ???
    }
    elsif (ROLE eq $sa->type) {
        require MT::Association;
        my @authors = MT::Author->load ({}, {
            join    => MT::Association->join_on ('author_id', {
                role_id => $sa->assoc_id,
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
