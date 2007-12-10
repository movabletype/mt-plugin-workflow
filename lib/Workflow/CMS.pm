package Workflow::CMS;

use MT::Util qw( ts2epoch format_ts epoch2ts relative_date );

sub edit_workflow {
    my $app = shift;
    
    $app->load_tmpl ('workflow_edit.tmpl', {});
}

sub view_audit_log {
    my $app = shift;
    my $id = $app->param ('id');
    require MT::Entry;
    my $entry = MT::Entry->load ($id);
    
    my $plugin = MT::Plugin::Workflow->instance;
    
    my $tmpl = $plugin->load_tmpl ('audit_log.tmpl') or die $plugin->errstr;
    my $blog = $entry->blog;
    $app->listing ({
        type    => 'workflow_audit_log',
        template    => $tmpl,
        terms   => {
            entry_id    => $id,
        },
        code    => sub {
            my ($obj, $row) = @_;
            require MT::Author;
            my $a = MT::Author->load ($obj->created_by);
            $row->{username} = $a->name;
            if ($obj->transferred_to) {
                my $ta = MT::Author->load ($obj->transferred_to);
                $row->{transferred_to_username} = $ta->name;                
            }
            else {
                $row->{transferred_to_username} = '';
            }
            my @actions = ();
            
            if (!$obj->old_status) {
                push @actions, 'Created';
            }
            elsif ($obj->edited) {
                push @actions, 'Edited';
            }
                        
            if ($obj->old_status != $obj->new_status) {
                if ($obj->new_status == MT::Entry::HOLD()) {
                    push @actions, 'Unpublished';
                }
                elsif ($obj->new_status == MT::Entry::RELEASE()) {
                    push @actions, 'Published';
                }
                elsif ($obj->new_status == MT::Entry::FUTURE()) {
                    push @actions, 'Scheduled';
                }
            }
            
            if ($obj->transferred_to) {
                push @actions, 'Transferred';
            }
            
            $row->{action_taken} = join (' and ', @actions);
            
            if ( my $ts = $obj->created_on ) {
                    $row->{created_on_formatted} =
                      format_ts( '%b %e, %Y',
                        epoch2ts( $blog, ts2epoch( undef, $ts ) ), $blog, $app->user ? $app->user->preferred_language : undef );
                $row->{created_on_relative} = relative_date( $ts, time );
                # $row->{log_detail} = $log->description;
            }
            
        },
         
    });
}

1;