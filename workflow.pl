
package MT::Plugin::Workflow;

use strict;
use warnings;

use base qw( MT::Plugin );
use MT 4;

use MT::Entry;

use MT::Util qw( spam_protect format_ts epoch2ts ts2epoch relative_date );
use Data::Dumper;

use Workflow::AuditLog;

use vars qw($VERSION $plugin);
$VERSION = '1.5';
$plugin = MT::Plugin::Workflow->new ({
        id          => 'Workflow',
        name		=> 'Workflow',
        version		=> $VERSION,
        description	=> 'Workflow can limit publishing rights to editors, can limit specified authors to posting only drafts, and lets an author pass ownership of an entry to any other author or editor with appropriate permissions.  Authors are notified when ownership of an entry is transferred.',
        plugin_link	=> 'http://www.apperceptive.com/plugins/workflow/',
        author_name	=> 'Apperceptive, LLC',
        author_link	=> 'http://www.apperceptive.com/',
        blog_config_template	=> 'blog_config.tmpl',
        settings		=> new MT::PluginSettings ([
            # Hash where the keys are author ids that have been checked in the plugin config
            # (though not necessarily that can publish, as the plugin may be extended via callbacks)
            # (this is just the default list)
            # [ 'can_publish', { Default => undef, Scope => 'blog' } ],
            
            # Whether or not email notifications should be sent out for transfer and publish attempts
            [ 'email_notification', { Default => 1, Scope => 'blog'} ],
            
            # Automatically transfer an entry that was publish attempted to the first available editor
            # Where "first available" is defined as the editor with the most recent published entry
            [ 'automatic_transfer', { Default => 0, Scope => 'blog'} ],
        ]),
            
        callbacks   => {
            # 'CMSPostSave.entry'  => {
            #     priority    => 1,
            #     code        => \&entry_save,
            # },
            
            'Workflow::CanTransfer'         => \&can_transfer,
            'Workflow::PostTransfer'        => \&post_transfer,
            'Workflow::PostPublishAttempt'  => \&post_publish_attempt,
        },
        
        
        template_tags   => {
            map { 
                my $old_tag = 'EntryAuthor' . $_;
                my $new_tag = 'EntryCreator' . $_;
                $new_tag => sub { workflow_tag_runner ( $old_tag , @_ ) }
            } ( '', 'DisplayName', 'Email', 'Link', 'Nickname', 'URL', 'Username'),
        },
        
        schema_version  => '0.3',
});
MT->add_plugin ($plugin);

sub init_registry {
    my $plugin = shift;
    my $reg = {
        object_types    => {
            'workflow_audit_log'    => 'Workflow::AuditLog',
        },
        callbacks   => {
            'MT::App::CMS::template_source.edit_entry'  => \&edit_entry_source,
            'MT::App::CMS::template_param.edit_entry'   => \&edit_entry_param,
            'cms_post_save.entry'                       => \&post_save_entry,
            
            'MT::App::CMS::template_source.list_entry'  => \&list_entry_source,
            'MT::App::CMS::template_param.list_entry'   => \&list_entry_param,
            
            'Workflow::CanPublish'          => \&can_publish,
            'Workflow::PostTransfer'        => sub {
                  transfer_audit_log (@_);
            },
        },
        
        init_app    => {
            'MT::App::CMS'  => \&init_cms_app,
        },
        
        applications    => {
            cms         => {
                methods => {
                    edit_workflow   => '$workflow::Workflow::CMS::edit_workflow',
                },
                list_actions    => {
                    entry       => {
                        view_audit_log  => {
                            label   => 'View audit log',
                            order   => 100,
                            code    => \&view_audit_log,
                            dialog  => 1,
                            condition   => sub {
                                return 1 unless MT::App->instance->mode eq 'view';
                            }
                        }
                    }
                },
                menus   => {
                    'manage:workflow'   => {
                        label   => 'Workflow',
                        mode    => 'edit_workflow',
                        order   => 10000,
                        permission  => 'edit_all_posts',
                        view    => 'blog',
                    }
                }
            }
        }
    };
    $plugin->registry ($reg);
}

sub view_audit_log {
    my $app = shift;
    my $id = $app->param ('id');
    require MT::Entry;
    my $entry = MT::Entry->load ($id);
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


sub init_cms_app {
    my $plugin = shift;
    my ($app) = @_;
    
    local $SIG{__WARN__} = sub {};
    my $orig_handler = \&MT::App::CMS::_finish_rebuild_ping;
    *MT::App::CMS::_finish_rebuild_ping = sub {
        my $a = shift;
        my ($entry) = @_;
        require MT::Request;
        my $r = MT::Request->instance;
        if ($r->stash ('workflow_transferred')) {
            $app->redirect (
                $app->uri (
                    mode => 'list_entry',
                    args    => {
                        blog_id => $entry->blog_id,
                        workflow_transferred => 1,
                    }
                )
            );
        }
        else {
            $orig_handler->($app, @_);
        }
    }
}

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

sub post_save_entry {
    my ($cb, $app, $obj, $orig) = @_;
    
    # First check for status changes
    # and log them if there is a change
    require Workflow::AuditLog;
    my $al = Workflow::AuditLog->new;
    $al->entry_id ($obj->id);
    $al->new_status ($obj->status);
    if (!$orig) {
        # New entry!
        $al->old_status (0);
        $al->edited (0);
    }
    else {
        # It's not new, and somebody saved it
        $al->old_status ($orig->status);        

        # Check the various text fields for changes
        my $is_edited = 0;
        foreach my $field (qw( text text_more title excerpt )) {
            $is_edited ||= ($obj->$field ne $orig->$field);
        }
        $al->edited ($is_edited);
    }
    $al->save;
    
    
    # No need to keep going unless it's something *other* than 1
    my $workflow_status = $app->param ('workflow_status');
    return unless ($workflow_status && $workflow_status > 1);
    
    if ($workflow_status == 2) {
        # move it along to the next user in the workflow
        $plugin->_automatic_transfer ($cb, $app, $app->user, $obj) or return $cb->error ($cb->errstr);
    }
    elsif ($workflow_status == 3) {
        # bounce it back to the previous owner
        my $prev_owner = $plugin->_get_previous_owner ($obj);
        if ($prev_owner && $prev_owner->id != $obj->author_id) {
            $plugin->transfer_entry ($cb, $app, Entry => $obj, To => $prev_owner) or return $cb->error ($cb->errstr);
        }
    }
    else {
        return;
    }

    # There was a transfer, so add that to the log
    $al->transferred_to ($obj->author_id);
    $al->note ($app->param ('workflow_change_note'));
    $al->save;
    
    # if we got this far, an entry was transferred, so we should make a note of that
    require MT::Request;
    my $r = MT::Request->instance;
    $r->stash ('workflow_transferred', 1);
}

sub _get_previous_owner {
    my $plugin = shift;
    my ($entry) = @_;
    
    if (!ref $entry) {
        require MT::Entry;
        $entry = MT::Entry->load ($entry);
    }
    require MT::Author;
    MT::Author->load ($entry->created_by);
}

sub _default_perms {
    my $plugin = shift;
    my ($blog_id) = @_;

    require MT::Permission;
    return { 
        map {
            $_->author_id => 1
        }
        grep { 
            $_->can_post 
                && $_->can_edit_all_posts 
        } 
        MT::Permission->load ({ blog_id => $blog_id }) 
    };
}

sub apply_default_settings {
    my $plugin = shift;
    my ($data, $scope_id) = @_;

    $plugin->SUPER::apply_default_settings (@_);

    if ($scope_id =~ /blog:(\d+)/) {
        my $blog_id = $1;
        # if (!defined $data->{ can_publish }) {
        #     $data->{ can_publish } = $plugin->_default_perms ($blog_id);
        # }
    }
}

sub load_config {
    my $plugin = shift;
    my ($params, $scope) = @_;
    my $old_workflow_perms;
    my $blog_id;

# First load up any configuration items
    $plugin->SUPER::load_config (@_);

# Check the scope to see if we're working on an individual blog
    if ($scope =~ /blog:(\d+)/) {
        $blog_id = $1;

# # Check for the existance of old Workflow permissions
# # If found, import the data and destroy the old record
#         require MT::PluginData;
#         if (my $old_publish_perms = MT::PluginData->load ({plugin => 'Workflow', key => $blog_id})) {
#             $old_workflow_perms = $old_publish_perms->data;
#             $params->{ can_publish } = {
#                 map {
#                     $_ => 1
#                 }
#                 grep {
#                     $old_workflow_perms->{ $_ }->{ can_publish }
#                 }
#                 keys %$old_workflow_perms
#             };
#             $plugin->set_config_value('can_publish', $params->{ can_publish },
#                     $scope);
# 
#             $old_publish_perms->remove;
#         }

        require MT::Permission;
        my %publishers = map { $_->author_id => 1 } grep { $_->can_publish_post } MT::Permission->load ({ blog_id => $blog_id });
        $params->{authors_loop} = [ map {
            { author_id => $_->author_id,
                author_name => $_->author->name,
                author_can_publish => $publishers{$_->author_id},
            }
        } 
        sort {lc($a->author->name) cmp lc($b->author->name) } 
        grep { $_->can_create_post } 
        MT::Permission->load ({ blog_id => $blog_id }) ];

    }

} 

sub save_config {
    my $plugin = shift;
    my ($param, $scope) = @_;

    if ($scope =~ /blog:(\d+)/) {
        my $blog_id = $1;
        require MT::App::CMS;
        my $app = MT::App::CMS->instance;
        my $q = $app->{query};
        my @p = $q->param('workflow_can_publish');
        my %publishers = map { $_ => 1 } @p;
        
        require MT::Permission;
        foreach my $perm (MT::Permission->load ({ blog_id => $blog_id })) {
            if ($perm->can_publish_post && !exists $publishers{$perm->author_id}) {
                # Remove publish perm if they currently have it and it's not checked
                $perm->can_publish_post (0);
                $perm->save;
            }
            elsif (!$perm->can_publish_post && exists $publishers{$perm->author_id}) {
                # Add publish perm if they don't already have it and it's checked
                $perm->can_publish_post (1);
                $perm->save;
            }
        }
    }

    $plugin->SUPER::save_config (@_);
}

sub reset_config {
    my $plugin = shift;
    my ($scope) = @_;

    if ($scope =~ /blog:(\d+)/) {
        my $blog_id = $1;
        # $plugin->set_config_value ('can_publish', 
        #         $plugin->_default_perms ($blog_id), 
        #         $scope
        #         );
    }
}

sub load_plugins {
    my $plugin_dir = File::Spec->catdir ('plugins', 'Workflow', 'plugins');
    local *DH;
    if (opendir DH, $plugin_dir) {
        my @p = readdir DH;
        for my $plugin (@p) {
            next if ($plugin !~ /\.pl$/);
            $plugin = File::Spec->catfile ($plugin_dir, $plugin);
            eval { require $plugin; }
        }
    }
}

# sub workflow_update_entry_status {
#     my $app = shift;
#     my ($new_status, @ids) = @_;
#     return $app->errtrans("Need a status to update entries") unless $new_status;
#     return $app->errtrans("Need entries to update status") unless @ids;
#     my @bad_ids;
#     my @rebuild_list;
#     require MT::Entry;
#     foreach my $id (@ids) {
#         my $entry = MT::Entry->load($id, {cached_ok=>1}) or return $app->errtrans("One of the entries ([_1]) did not actually exist", $id);
#         push @rebuild_list, $entry if $entry->status != $new_status;
#         $entry->status($new_status);
#         $entry->save() or (push @bad_ids, $id);
# 
# # Call workflow's publish checker callbacks and reload the entry
#         &entry_save($app, $app, $entry);
#         $entry = MT::Entry->load($entry->id, {cached_ok=>1});
# 
# # Remove it from the rebuild_list if it didn't change
#         pop @rebuild_list if $entry->status != $new_status
#     }
#     return $app->errtrans("Some entries failed to save") if (@bad_ids); # FIXME: we don't really want this
#         $app->rebuild_entry(Entry => $_, BuildDependencies => 1)
#         foreach @rebuild_list; # FIXME: optimize, phase out to another page.
#         my $blog_id = $app->param('blog_id');
#     $app->call_return;
# }

# The default publish checker: if the user is in the plugin config's can_publish hash, they can publish
sub can_publish {
    my ($eh, $app, $author, $entry) = @_;

    require MT::Permission;
    my $perm = MT::Permission->get_by_key ({ blog_id => $entry->blog_id, author_id => $author->id });
    return $perm->can_publish_post;
}

# The default transfer checker: make sure the new author can post to the entry's blog
sub can_transfer {
    my ($eh, $app, $entry, $new_author, $user) = @_;
    
    require MT::Permission;
    my $perm = MT::Permission->load ({ author_id => $new_author->id, blog_id => $entry->blog_id });
    
    return $perm && $perm->can_post;
}


sub entry_save {
    my ($eh, $app, $e) = @_;
    my $author = $app->{author};

    # If the entry is *not* set to draft, and the current user cannot publish
    # keep the entry from being published
    if ($e->status != MT::Entry::HOLD &&
            !MT->run_callbacks ('Workflow::CanPublish', $app, $author, $e)) {

        # Can't publish, so set the entry status to unpublished, save the entry
        # And call the publish attempt callback
        $e->status (MT::Entry::HOLD);
        $e->save;
        MT->run_callbacks('Workflow::PostPublishAttempt', $app, $author, $e);
    }
}

sub post_transfer {
    my ($eh, $app, $e, $old_a, $auth) = @_;

    return 1 if (!$plugin->get_config_value ('email_notification', 'blog:' . $e->blog_id));

    require MT::Entry;
    my $a = $e->author;
    if ($a->email) {
        require MT::Blog;
        require MT::Mail;
        my $from_addr = $app->{cfg}->EmailAddressMain || $auth->email;
        my %head = ( To => $a->email,
                From => $from_addr,
                Subject => 
                '[' . $e->blog->name . '] ' .
                $app->translate ('Entry Transferred: [_1]', $e->title)
                );

        my $charset = $app->{cfg}->PublishCharset || 'iso-8859-1';
        $head{'Content-Type'} = qq(text/plain; charset="$charset");
        my $base = $app->base . $app->path . $app->{cfg}->AdminScript;

        my $edit_url = $base . '?__mode=view&blog_id=' . $e->blog_id
            . '&_type=entry&id=' . $e->id;

        my $can_publish = MT->run_callbacks ('Workflow::CanPublish', $app, $a, $e);

        my %params = (
                blog_name => $e->blog->name,
                entry_id => $e->id,
                entry_title => $e->title,
                edit_url => $edit_url,
                can_publish => $can_publish,
                );

        my $body = $app->build_page ('transfer_notification.tmpl', \%params);
        require Text::Wrap;
        $Text::Wrap::columns = 72;
        $body = Text::Wrap::wrap ('', '', $body, "\n\n");
        $body .= "\n\nEdit this entry:\n<$edit_url>\n\n";
        MT::Mail->send (\%head, $body) or 
            $app->log ("Error sending transfer notification email to ".$a->name);
    }
}

# Get a list of eligible editors based on a given entry
sub _get_editors {
    my $plugin = shift;
    my ($app, $entry) = @_;
    
    my $blog = $entry->blog;
    
    require MT::Permission;
    my @perms = MT::Permission->load ({ blog_id => $blog->id });
    
    require MT::Author;
    return ( grep { MT->run_callbacks ('Workflow::CanPublish', $app, $_, $entry) } map { MT::Author->load ($_->author_id) } @perms );
}

# Perform the actual entry transfer
sub _transfer_entry {
    my $plugin = shift;
    my ($eh, $app, %params) = @_;
    my $entry = $params{Entry};
    my $new_author = $params{To};
    
    # Grab the old author
    # and delete the cached version(s)
    my $old_author = $entry->author;
    delete $entry->{__author};          # For MT
    delete $entry->{__cache}{author};   # For MTE
    
    # Set the updated author_id
    # and record the original entry creator if there wasn't one already
    $entry->author_id ($new_author->id);
    $entry->created_by ($old_author->id) if (!$entry->created_by);
    
    # And save the entry
    $entry->save or return $eh->error ("Error saving transferred entry: " . $entry->errstr);
}

sub transfer_entry {
    my $plugin = shift;
    my ($eh, $app, %params) = @_;
    
    my $entry = $params{Entry};
    my $new_author = $params{To};
    
    # If the current user can transfer this particular entry to this particular author
    if (MT->run_callbacks ('Workflow::CanTransfer', $app, $entry, $new_author, $app->user)) {
        
        # Grab the current author
        my $old_author = $entry->author;
        
        # Why separate CanTransfer from PreTransfer?  I'm honestly not sure
        # Probably because it will allow callback writers to assume that the transfer has been approved
        # by the time the PreTransfer callback is made.
        # That is not an assumption that can be made in CanTransfer as a later callback might kick back a disapproval
        MT->run_callbacks ('Workflow::PreTransfer', $app, $entry, $new_author, $app->user);
        
        # Perform the actual entry transfer
        $plugin->_transfer_entry ($eh, $app, %params) or return $eh->error ($eh->errstr);
                
        $app->log ("Entry #".$entry->id." transferred from '".$old_author->name.
                "' to '".$new_author->name."' by '".$app->{author}->name."'");
        
        # Run the PostTransfer callbacks
        MT->run_callbacks ('Workflow::PostTransfer', $app, $entry, $new_author, $app->user);
        
        # Entry was successfully transfereed, so return a true value
        return 1;
    }
    else {
        return $eh->error ("Entry cannot be transfered");
    }
}


sub _automatic_transfer {
    my $plugin = shift;
    my ($eh, $app, $author, $entry) = @_;
    
    my @editors = $plugin->_get_editors ($app, $entry);
    
    # Only do the fancy bits if there are more than one available editor
    if (scalar @editors > 1) {
        require MT::Entry;

        # Build up a hash of author_id => timestamp of latest entry
        # so that we can sort on it in regular order (i.e. lower numbers, like 0, go first)
        my %latest_editor_entries = 
            map { $_->author_id => $_->modified_on }
            map { MT::Entry->load ({ author_id => $_->id, status => MT::Entry::RELEASE }, { sort => 'modified_on', direction => 'descend', limit => 1 }) } @editors;

        # Sort the editor list based on the latest entry modified_on timestamps
        # Editors with no published entries will rise to the front of the list as their latest entry dates will be 0/undef
        @editors = sort { $latest_editor_entries{$a->id} <=> $latest_editor_entries{$b->id} } @editors;
    }
    
    $plugin->transfer_entry ($eh, $app, Entry => $entry, To => $editors[0]) or return $eh->error ($eh->errstr);
}

sub post_publish_attempt {
    my ($eh, $app, $author, $entry) = @_;
    
    # First check for automatic transfer
    return $plugin->_automatic_transfer ($eh, $app, $author, $entry) if ($plugin->get_config_value ('automatic_transfer', 'blog:' . $entry->blog_id));
    
    # Skip this if email notification is turned off
    return 1 if (!$plugin->get_config_value ('email_notification', 'blog:' . $entry->blog_id));
    
    # First, get a list of all the Editors (i.e. can publish folks) and whatever email addresses they have handy
    # We cannot just do this with the plugin settings as other plugins may be hooking into the callback
    # so we'll have to load up every author associated with the blog and loop through to see who gets the email
    my @editors = $plugin->_get_editors ($app, $entry);
    
    my %email_addresses = map { $_->email ? ($_->email => 1) : () } @editors; # Use a hash to eliminate any duplicates
    my @email_addrs = sort { $a cmp $b } keys %email_addresses;
    
    require MT::Mail;
    my $from_addr = $app->{cfg}->EmailAddressMain || $author->email;
    my %head = ( To => \@email_addrs,
            From => $from_addr,
            Subject => 
            '[' . $entry->blog->name . '] ' .
            $app->translate ('Entry Publish Attempted: [_1]', $entry->title)
            );

    my $charset = $app->{cfg}->PublishCharset || 'iso-8859-1';
    $head{'Content-Type'} = qq(text/plain; charset="$charset");
    
    my $body = $app->build_page ('post_attempt_notification.tmpl', {});
    
    require Text::Wrap;
    $Text::Wrap::columns = 72;
    $body = Text::Wrap::wrap ('', '', $body, "\n\n");
    # MT::Mail->send
}

sub _get_entry_creator {
    my $e = $_[0]->stash ('entry') or return;

    my $a = MT::Author->load ($e->created_by ? $e->created_by : $e->author_id);
    $a;
}

sub workflow_tag_runner {
    my ($tag, $ctx, $args) = @_;

    my $a = _get_entry_creator ($ctx, $args)
        or return $ctx->_no_entry_error ($ctx->stash ('tag'));
        
    local $ctx->{__stash}{entry}{__author} = $a;
    my ($hdlr) = $ctx->handler_for ($tag);
    $hdlr->($ctx, $args);
}

sub transfer_audit_log {
    my ($cb, $app, $entry, $user) = @_;
    
    # my $al = Workflow::AuditLog->new;
    # $al->entry_id ($entry->id);
    # $al->transferred_to ($entry->author_id);
    # $al->note ($app->param ('workflow_change_note'));
    # $al->save;
}


1;
