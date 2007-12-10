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

###
### Callbacks
###

sub edit_entry_source {
    my ($cb, $app, $tmpl) = @_;
    
    my $new = q{
        <mt:unless name="status_publish">
        <mtapp:setting
            id="workflow_status"
            label="Workflow Status">
            <script type="text/javascript">
                function updateNote() {
                    var sel = getByID('workflow_status');
                    var val = sel.options[sel.selectedIndex].value;
                    if (val > 1) {
                        TC.removeClassName (getByID('workflow_change_note-field'), 'hidden');                        
                    }
                    else {
                        TC.addClassName (getByID('workflow_change_note-field'), 'hidden');
                    }
                }
            </script>
            <select name="workflow_status" id="workflow_status" class="full-width" onchange="updateNote();">
                <option value="1">Unfinished</option>
                <option value="2">Ready for next step</option>
                <mt:if name="workflow_has_previous"><option value="3">Return to previous step</option></mt:if>
            </select>
        </mtapp:setting>
        <mtapp:setting
            id="workflow_change_note"
            label="Workflow Change Note"
            shown="0">
            <textarea type="text" class="full-width short" rows="" cols="" id="workflow_change_note" name="workflow_change_note"></textarea>
        </mtapp:setting>
        </mt:unless>
    };
    my $old = '<h3><__trans phrase="Publishing"></h3>';
    
    $$tmpl =~ s{\Q$old\E}{$old$new}ms;
}

sub edit_entry_param {
    my ($cb, $app, $param, $tmpl) = @_;
    
    return if (!$param->{id});
    my $prev_owner = $plugin->_get_previous_owner ($param->{id});
    
    $param->{workflow_has_previous} = ($prev_owner && $param->{author_id} != $prev_owner->id);
}

sub list_entry_source {
    my ($cb, $app, $tmpl) = @_;
    my $old = q{    </div>
</mt:setvarblock>
<mt:unless name="is_power_edit">};
    my $new = q{
        <mt:if name="workflow_transferred">
            <mtapp:statusmsg
                id="workflow_transferred"
                class="success">
                <__trans phrase="The [_1] has been transferred." params="<mt:var name="object_label">">
            </mtapp:statusmsg>
        </mt:if>
    };
    
    $$tmpl =~ s{\Q$old\E}{$new$old}ms;
}

sub list_entry_param {
    my ($cb, $app, $param, $tmpl) = @_;
    $param->{workflow_transferred} = $app->param ('workflow_transferred');
}

1;