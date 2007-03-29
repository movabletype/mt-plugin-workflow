

package MT::Plugin::Workflow;

use base qw( MT::Plugin );
use vars qw($VERSION $plugin);
use MT;
return 1 unless MT->version_number () >= 3.2;

use MT::Entry;

use MT::Template::Context;
use MT::Util qw( spam_protect );
use Data::Dumper;

use strict;

use lib './lib';

$VERSION = '1.5';
$plugin = MT::Plugin::Workflow->new ({
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
            [ 'can_publish', { Default => undef, Scope => 'blog' } ],
            
            # Whether or not email notifications should be sent out for transfer and publish attempts
            [ 'email_notification', { Default => 1, Scope => 'blog'} ],
            
            # Automatically transfer an entry that was publish attempted to the first available editor
            # Where "first available" is defined as the editor with the most recent published entry
            [ 'automatic_transfer', { Default => 0, Scope => 'blog'} ],
        ]),
            
        callbacks   => {
            'CMSPostSave.entry'  => {
                priority    => 1,
                code        => \&entry_save,
            },
            
            'Workflow::CanPublish'          => \&can_publish,
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
});
MT->add_plugin ($plugin);

sub init_app {
    my $plugin = shift;
    my ($app) = (@_);

    if ($app->isa ('MT::App::CMS')) {
        $app->add_itemset_action ({
                type	=> 'entry',
                key	    => 'workflow_transfer',
                label	=> 'Workflow transfer',
                code	=> sub { transfer_entries ($plugin, @_) },
                });
    }
    
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
        if (!defined $data->{ can_publish }) {
            $data->{ can_publish } = $plugin->_default_perms ($blog_id);
        }
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

# Check for the existance of old Workflow permissions
# If found, import the data and destroy the old record
        require MT::PluginData;
        if (my $old_publish_perms = MT::PluginData->load ({plugin => 'Workflow', key => $blog_id})) {
            $old_workflow_perms = $old_publish_perms->data;
            $params->{ can_publish } = {
                map {
                    $_ => 1
                }
                grep {
                    $old_workflow_perms->{ $_ }->{ can_publish }
                }
                keys %$old_workflow_perms
            };
            $plugin->set_config_value('can_publish', $params->{ can_publish },
                    $scope);

            $old_publish_perms->remove;
        }

        require MT::Permission;
        my %publishers = %{ $params->{ can_publish } };
        $params->{authors_loop} = [ map {
            { author_id => $_->author_id,
                author_name => $_->author->name,
                author_can_publish => $publishers{$_->author_id},
            }
        } 
        sort {lc($a->author->name) cmp lc($b->author->name) } 
        grep { $_->can_post } 
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
        $param->{can_publish} = { map { $_ => 1 } @p };
    }

    $plugin->SUPER::save_config (@_);
}

sub reset_config {
    my $plugin = shift;
    my ($scope) = @_;

    if ($scope =~ /blog:(\d+)/) {
        my $blog_id = $1;
        $plugin->set_config_value ('can_publish', 
                $plugin->_default_perms ($blog_id), 
                $scope
                );
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

sub workflow_blog_setup {
    my $plugin = shift;
    require MT::App::CMS;
    my $app = MT::App::CMS->instance;
    my ($params, $scope) = @_;
    if (!defined $params->{'can_publish'}) {
        return "Initial setup";
    } else {
        return "Normal config";
    }
}

sub transfer_entries {
    my $plugin = shift;
    my ($app)= @_;
    return "transferring entries";
}

if (MT->version_number >= 3.2) {
    require MT::App::CMS;
    {
        local $SIG{__WARN__} = sub {};
        my $mt_update_entry_status = \&MT::App::CMS::update_entry_status;
        *MT::App::CMS::update_entry_status = \&workflow_update_entry_status;
    }
} else {
    require MT::ConfigMgr;
    if (!MT::ConfigMgr->instance->AltTemplatePath) {
        MT::ConfigMgr->instance->AltTemplatePath ('./plugins/Workflow/alt-tmpl');
    }
}


sub workflow_update_entry_status {
    my $app = shift;
    my ($new_status, @ids) = @_;
    return $app->errtrans("Need a status to update entries") unless $new_status;
    return $app->errtrans("Need entries to update status") unless @ids;
    my @bad_ids;
    my @rebuild_list;
    require MT::Entry;
    foreach my $id (@ids) {
        my $entry = MT::Entry->load($id, {cached_ok=>1}) or return $app->errtrans("One of the entries ([_1]) did not actually exist", $id);
        push @rebuild_list, $entry if $entry->status != $new_status;
        $entry->status($new_status);
        $entry->save() or (push @bad_ids, $id);

# Call workflow's publish checker callbacks and reload the entry
        &entry_save($app, $app, $entry);
        $entry = MT::Entry->load($entry->id, {cached_ok=>1});

# Remove it from the rebuild_list if it didn't change
        pop @rebuild_list if $entry->status != $new_status
    }
    return $app->errtrans("Some entries failed to save") if (@bad_ids); # FIXME: we don't really want this
        $app->rebuild_entry(Entry => $_, BuildDependencies => 1)
        foreach @rebuild_list; # FIXME: optimize, phase out to another page.
        my $blog_id = $app->param('blog_id');
    $app->call_return;
}

# The default publish checker: if the user is in the plugin config's can_publish hash, they can publish
sub can_publish {
    my ($eh, $app, $author, $entry) = @_;

    my $publish_perms = $plugin->get_config_value ('can_publish', 'blog:' . $entry->blog_id);

    # Unless we know otherwise, let them publish!
    return 1 unless ($publish_perms);
    
    return $publish_perms->{$author->id};
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
            map { MT::Entry->load ({ author_id => $_->id, status => MT::Entry::RELEASE, { sort => 'modified_on', direction => 'descend', limit => 1 } }) } @editors;

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

1;
