

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

use lib 'plugins/Workflow/lib';

sub BEGIN {
    $VERSION = '@VERSION@';
    $plugin = MT::Plugin::Workflow->new ({
            name		=> 'Workflow',
            version		=> $VERSION,
            description	=> 'Workflow can limit publishing rights to editors, can limit specified authors to posting only drafts, and lets an author pass ownership of an entry to any other author or editor with appropriate permissions.  Authors are notified when ownership of an entry is transferred.',
            plugin_link	=> 'http://www.rayners.org/plugins/workflow/',
            author_name	=> 'David Raynes',
            author_link	=> 'http://www.rayners.org/',
            blog_config_template	=> 'blog_config.tmpl',
            settings		=> new MT::PluginSettings ([
                ['can_publish', { Default => undef, Scope => 'blog' }],
                ]),
            });
    MT->add_plugin ($plugin);

    if (MT->version_number < 3.3) {
        MT->add_callback ('AppPostEntrySave', 1, $plugin, \&entry_save);
    }
    else {
        MT->add_callback('CMSPostSave.entry', 1, $plugin, \&entry_save);
    }
    MT->add_callback ('Workflow::CanPublish', 1, $plugin, \&can_publish);
    MT->add_callback ('Workflow::PostTransfer', 1, $plugin, \&post_transfer);

}

sub init_app {
    my $plugin = shift;
    my ($app) = (@_);

    if ($app->isa ('MT::App::CMS')) {
        $app->add_itemset_action ({
                type	=> 'entry',
                key	=> 'workflow_transfer',
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

sub can_publish {
    my ($eh, $app, $author, $entry) = @_;

    require MT::PluginData;
    my $publish_perms = MT::PluginData->load ({ plugin => 'Workflow',
            key => $entry->blog_id });

# Unless we know otherwise, let them publish!
    return 1 unless ($publish_perms);

    my $perms = $publish_perms->data;
    return (exists $perms->{$author->id} && exists $perms->{$author->id}->{'can_publish'});
}


sub entry_save {
    my ($eh, $app, $e) = @_;
    my $author = $app->{author};

    require Workflow;
    Workflow->load_plugins;
    if ($e->status != MT::Entry::HOLD &&
            !MT->run_callbacks ('Workflow::CanPublish', $app, $author, $e)) {
        $e->status (MT::Entry::HOLD());
        $e->save;
        MT->run_callbacks('Workflow::PostPublishAttempt', $app, $author, $e);
    }
}

sub post_transfer {
    my ($eh, $app, $e, $old_a, $auth) = @_;

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

        require Workflow;
        Workflow->load_plugins;
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

### Template Tags

MT::Template::Context->add_tag ( EntryCreator => \&entry_creator );
MT::Template::Context->add_tag ( EntryCreatorEmail => \&entry_creator_email );
MT::Template::Context->add_tag ( EntryCreatorURL => \&entry_creator_url );
MT::Template::Context->add_tag ( EntryCreatorLink => \&entry_creator_link );
MT::Template::Context->add_tag ( EntryCreatorNickname => \&entry_creator_nick );
MT::Template::Context->add_tag ( EntryCreatorDisplayName =>
        \&entry_creator_display_name );
MT::Template::Context->add_tag ( EntryCreatorUsername =>
        \&entry_creator_username );

sub _get_entry_creator {
    my $e = $_[0]->stash ('entry') or return;

    my $a = MT::Author->load ($e->created_by ? $e->created_by : $e->author_id);
    $a;
}

sub entry_creator {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreator');

    $a ? $a->name || '' : '';

}

sub entry_creator_display_name {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorDisplayName');
    $a ? $a->nickname || '' : '';
}

sub entry_creator_nick {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorNickname');
    $a ? $a->nickname || '' : '';  
}

sub entry_creator_username {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorUsername');
    $a ? $a->name || '' : '';
}

sub entry_creator_email {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorEmail');

    return '' unless $a && defined $a->email;
    $_[1] && $_[1]->{'spam_protect'} ? spam_protect($a->email) : $a->email;
}

sub entry_creator_url {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorURL');

    $a ? $a->url || "" : "";
}

sub entry_creator_link {
    my $a = &_get_entry_creator (@_)
        or return $_[0]->_no_entry_error('MTEntryCreatorLink');

    my ($ctx, $args) = @_;
    return '' unless $a;
    my $name = $a->nickname || '';
    my $show_email = $args->{ show_email } ? 1 : 0;
    my $show_url = 1 unless exists $args->{show_url} && !$args->{show_url};
    my $target = $args->{new_window} ? ' target="_blank"' : '';
    if ($show_url && $a->url && ($name ne '')) {
        return sprintf qq(<a href="%s"%s>%s</a>), $a->url, $target, $name;
    } elsif ($show_email && $a->email && ($name ne '')) {
        my $str = "mailto:" . $a->email;
        $str = spam_protect($str) if $args->{'spam_protect'};
        return sprintf qq(<a href="%s">%s</a>), $str, $name;
    } else {
        return $name;
    }
}

