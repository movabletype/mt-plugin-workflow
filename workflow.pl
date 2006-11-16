

package MTPlugins::Workflow;

use MT;
return 1 unless MT->version_number () >= 3.1;

use MT::Entry;

use MT::Template::Context;
use MT::Util qw( spam_protect );

use strict;

use lib 'plugins/Workflow/lib';

MT->add_plugin_action ('entry', 'workflow.cgi?__mode=transfer_entry_select', "Transfer ownership of this entry");

MT->add_plugin_action ('blog', 'workflow.cgi?__mode=admin_publish_perms', 'Edit Publish Permissions');

require Workflow;
my $plugin = Workflow->new ();
MT->add_plugin ($plugin);
# Remember with these callbacks, total parameters are: eh, app, perm

Workflow->add_setup_option ('Open Publishing', 
	  { desc => '<strong>Any user can publish.</strong> Editors will be given permission to grant publish access to other users. Any Author who has permission to post will be given permission to publish entries.',
	    can_grant => sub { $_[2]->can_edit_all_posts }, 
	    can_publish => sub { $_[2]->can_post } });

Workflow->add_setup_option ('Default Publishing', 
	  { desc => '<strong>Editors can publish, Authors can post in draft.</strong> Only Editors will be given permission to publish entries. Editors can also give publishing rights to other Authors.',
	    can_grant => sub { $_[2]->can_edit_all_posts }, 
	    can_publish => sub { $_[2]->can_edit_all_posts } });

if (MT->version_number < 3.3) {
    MT->add_callback ('AppPostEntrySave', 1, $plugin, \&entry_save);
}
else {
    MT->add_callback('CMSPostSave.entry', 1, $plugin, \&entry_save);
}
MT->add_callback ('Workflow::CanPublish', 1, $plugin, \&can_publish);
MT->add_callback ('Workflow::PostTransfer', 1, $plugin, \&post_transfer);

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
  my $name = $a->name || '';
  my $show_email = 1 unless exists $args->{show_email};
  my $show_url = 1 unless exists $args->{show_url};
  if ($show_url && $a->url) {
    return sprintf qq(<a target="_blank" href="%s">%s</a>), $a->url, $name;
  } elsif ($show_email && $a->email) {
    my $str = "mailto:" . $a->email;
    $str = spam_protect($str) if $args->{'spam_protect'};
    return sprintf qq(<a href="%s">%s</a>), $str, $name;
  } else {
    return $name;
  }
}

sub entry_creator_nick {
  my $a = &_get_entry_creator (@_)
    or return $_[0]->_no_entry_error('MTEntryCreatorNickname');
  $a ? $a->nickname || '' : '';  
}
