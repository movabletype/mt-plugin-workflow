
package MT::Plugin::Workflow;

use strict;
use warnings;

use base qw( MT::Plugin );
use MT 4;

use MT::Entry;

use MT::Util qw( spam_protect format_ts epoch2ts ts2epoch relative_date );
use Data::Dumper;

use Workflow::Workflowable;
use Workflow::AuditLog;
use Workflow::Step;
use Workflow::StepAssociation;

use vars qw($VERSION $plugin);
$VERSION = '1.9.1';
$plugin = MT::Plugin::Workflow->new ({
        id          => 'Workflow',
        name		=> 'Workflow',
        version		=> $VERSION,
        description	=> 'Workflow can limit publishing rights to editors, can limit specified authors to posting only drafts, and lets an author pass ownership of an entry to any other author or editor with appropriate permissions.  Authors are notified when ownership of an entry is transferred.',
        plugin_link	=> 'http://www.apperceptive.com/plugins/workflow/',
        author_name	=> 'Apperceptive, LLC',
        author_link	=> 'http://www.apperceptive.com/',
        doc_link    => 'README.html',
        blog_config_template	=> 'blog_config.tmpl',
        settings		=> new MT::PluginSettings ([
            # Whether or not email notifications should be sent out for transfer and publish attempts
            [ 'email_notification', { Default => 1, Scope => 'blog'} ],
            
            # Automatically transfer an entry that was publish attempted to the first available editor
            # Where "first available" is defined as the editor with the most recent published entry
            [ 'automatic_transfer', { Default => 0, Scope => 'blog'} ],
        ]),
            
        callbacks   => {
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
        
        schema_version  => '0.6',
});
MT->add_plugin ($plugin);

sub instance {
    $plugin;
}

sub init_registry {
    my $plugin = shift;
    my $reg = {
        object_types    => {
            'workflow_audit_log'    => 'Workflow::AuditLog',
            'workflow_step'         => 'Workflow::Step',
            'workflow_step_association' => 'Workflow::StepAssociation',
            'workflow_status'       => 'Workflow::Status',
        },
        callbacks   => {
            'MT::App::CMS::template_param.edit_entry'   => '$Workflow::Workflow::CMS::edit_entry_param',
            'cms_post_save.entry'                       => \&post_save_entry,
            
            'MT::App::CMS::template_source.list_entry'  => '$Workflow::Workflow::CMS::list_entry_source',
            'MT::App::CMS::template_param.list_entry'   => '$Workflow::Workflow::CMS::list_entry_param',
            
            'cms_post_save.workflow_step'               => '$Workflow::Workflow::CMS::post_workflow_step_save',
            
            'Workflow::CanPublish'          => \&can_publish,
            'Workflow::PostTransfer'        => \&post_transfer,
            'Workflow::PostTransfer.entry'  => \&post_transfer_entry,
        },
        
        init_app    => \&app_init,
        
        applications    => {
            cms         => {
                methods => {
                    edit_workflow   => '$Workflow::Workflow::CMS::edit_workflow',
                    list_workflow_step  => '$Workflow::Workflow::CMS::list_workflow_step',
                    view_workflow_step  => '$Workflow::Workflow::CMS::view_workflow_step',
                    view_audit_log  => '$Workflow::Workflow::CMS::view_audit_log',
                },
                page_actions    => {
                    entry  => {
                        view_audit_log  => {
                            label   => 'View audit log',
                            dialog  => 'view_audit_log',
                            permission  => 'edit_all_posts',
                        }
                    }
                },
                menus   => {
                    'manage:workflow'   => {
                        label   => 'Workflow',
                        # mode    => 'edit_workflow',
                        mode    => 'list',
                        args    => { _type => 'workflow_step' },
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

sub app_init {
    my $plugin = shift;
    my ($app) = @_;
    
    $plugin->init_workflowable_objects;
    $plugin->init_cms_app ($app) if ($app->isa ('MT::App::CMS'));
}

sub init_workflowable_objects {
    my $plugin = shift;
    require MT::Entry;
    push @MT::Entry::ISA, 'Workflow::Workflowable';
    
    MT::Entry->workflow_init (
        TextFields  => [ qw( text text_more title excerpt ) ],
        OwnerField  => 'author_id',
        StatusField => 'status',
    );
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

sub post_save_entry {
    my ($cb, $app, $obj, $orig) = @_;
    
    if (defined (my $res = $obj->workflow_update ($orig, $app->param ('workflow_status'), $app->param ('workflow_change_note')))) {
        if ($res) {
            require MT::Request;
            my $r = MT::Request->instance;
            $r->stash ('workflow_transferred', 1);
        }
        return 1;
    }
    else {
        return $cb->error ($obj->errstr);
    }
    
    # my $step = $obj->workflow_step;
    # 
    # # First check for status changes
    # # and log them if there is a change
    # require Workflow::AuditLog;
    # my $al = Workflow::AuditLog->new;
    # $al->object_id ($obj->id);
    # $al->object_datasource ($obj->datasource);
    # $al->new_status ($obj->status);
    # if (!$orig) {
    #     # New entry!
    #     $al->old_status (0);
    #     $al->edited (0);
    # }
    # else {
    #     # It's not new, and somebody saved it
    #     $al->old_status ($orig->status);        
    # 
    #     # Check the various text fields for changes
    #     my $is_edited = 0;
    #     foreach my $field (qw( text text_more title excerpt )) {
    #         $is_edited ||= ($obj->$field ne $orig->$field);
    #     }
    #     $al->edited ($is_edited);
    # }
    # $al->save;
    # 
    # # No need to keep going unless it's something *other* than 1
    # my $workflow_status = $app->param ('workflow_status');
    # return unless ($workflow_status && $workflow_status > 1);
    # 
    # if ($workflow_status == 2) {
    #     # move it along to the next user in the workflow
    #     $plugin->_automatic_transfer ($cb, $app, $app->user, $obj) or return $cb->error ($cb->errstr);
    # }
    # elsif ($workflow_status == 3) {
    #     # bounce it back to the previous owner
    #     my $prev_owner = $plugin->_get_previous_owner ($obj);
    #     if ($prev_owner && $prev_owner->id != $obj->author_id) {
    #         $plugin->transfer_entry ($cb, $app, Entry => $obj, To => $prev_owner) or return $cb->error ($cb->errstr);
    #     }
    # }
    # else {
    #     return;
    # }
    # 
    # # There was a transfer, so add that to the log
    # $al->transferred_to ($obj->author_id);
    # $al->note ($app->param ('workflow_change_note'));
    # $al->save;
    
    # if we got this far, an entry was transferred, so we should make a note of that
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

# sub post_transfer {
#     my ($eh, $app, $e, $old_a, $auth) = @_;
# 
#     return 1 if (!$plugin->get_config_value ('email_notification', 'blog:' . $e->blog_id));
# 
#     require MT::Entry;
#     my $a = $e->author;
#     if ($a->email) {
#         require MT::Blog;
#         require MT::Mail;
#         my $from_addr = $app->{cfg}->EmailAddressMain || $auth->email;
#         my %head = ( To => $a->email,
#                 From => $from_addr,
#                 Subject => 
#                 '[' . $e->blog->name . '] ' .
#                 $app->translate ('Entry Transferred: [_1]', $e->title)
#                 );
# 
#         my $charset = $app->{cfg}->PublishCharset || 'iso-8859-1';
#         $head{'Content-Type'} = qq(text/plain; charset="$charset");
#         my $base = $app->base . $app->path . $app->{cfg}->AdminScript;
# 
#         my $edit_url = $base . '?__mode=view&blog_id=' . $e->blog_id
#             . '&_type=entry&id=' . $e->id;
# 
#         my $can_publish = MT->run_callbacks ('Workflow::CanPublish', $app, $a, $e);
# 
#         my %params = (
#                 blog_name => $e->blog->name,
#                 entry_id => $e->id,
#                 entry_title => $e->title,
#                 edit_url => $edit_url,
#                 can_publish => $can_publish,
#                 );
# 
#         my $body = $app->build_page ('transfer_notification.tmpl', \%params);
#         require Text::Wrap;
#         $Text::Wrap::columns = 72;
#         $body = Text::Wrap::wrap ('', '', $body, "\n\n");
#         $body .= "\n\nEdit this entry:\n<$edit_url>\n\n";
#         MT::Mail->send (\%head, $body) or 
#             $app->log ("Error sending transfer notification email to ".$a->name);
#     }
# }

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

sub post_transfer {
    my ($cb, $obj, $from, $to) = @_;
    
    require MT::App;
    my $app = MT::App->instance;
    
    my $log_message = $obj->class_label . " #" . $obj->id . " transferred to " . $to->name;
    
    $app->log ($log_message);
}

sub post_transfer_entry {
    my ($cb, $obj, $from, $to) = @_;
    
    # Nix any cached author, since we've just changed it
    delete $obj->{__cache}{author};
}

1;
