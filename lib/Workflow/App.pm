
package Workflow::App;

use lib 'plugins/Workflow/lib';

use MT::App;
@ISA = qw( MT::App );

use File::Spec;
use Data::Dumper;
use Workflow;

use MT::Util qw( mark_odd_rows );

use strict;

sub init {
  my $app = shift;
  $app->SUPER::init (@_) or return;

  $app->add_methods (
      transfer_entry_select => \&transfer_entry_select,
      transfer_entry =>	\&transfer_entry,
      admin_publish_perms => \&admin_publish_perms,
      build_initial_perms => \&build_initial_perms,
      update_publish_perms => \&update_publish_perms,
      );

  $app->{default_mode} = 'transfer_entry_select';
  
  $app->{template_dir} = 'cms';
  $app->{plugin_template_path} = File::Spec->catdir ('plugins', 'Workflow', 'tmpl');

  $app->{requires_login} = 1;
  $app->{user_class} = 'MT::Author';
  
  $app;
  
}

sub uri {
  $_[0]->mt_uri
}

sub pre_run {
  my $app = shift;
  $app->add_breadcrumb ($app->translate('Main Menu'), $app->mt_uri );
  if (my $blog_id = $app->{query}->param ('blog_id')) {
    require MT::Permission;
    $app->{perms} = MT::Permission->load ({ blog_id => $blog_id, author_id => $app->{author}->id });
    my $blog = MT::Blog->load ($blog_id);
    $app->add_breadcrumb ($blog->name, $app->mt_uri . "?__mode=menu&blog_id=$blog_id");
  }
  $app->add_breadcrumb ("Workflow", 
      $app->path . "plugins/Workflow/" . $app->script);
  $app->SUPER::pre_run ();
}

sub transfer_entry {
  my ($app) = @_;
  my $q = $app->{query};

  my $entry_id = $q->param ('entry_id');
  my $new_author_id = $q->param ('new_author_id');

  require MT::Entry;
  require MT::Author;
  require MT::Blog;

  my $e = MT::Entry->load ($entry_id);
  my $a = MT::Author->load ($new_author_id);
  my $blog = MT::Blog->load ($e->blog_id);
  my $auth = $app->{author};

  
  require MT::Permission;
  my $perms = MT::Permission->load ({ blog_id => $e->blog_id, 
      author_id => $auth->id });
  if (!$perms || !$perms->can_edit_entry ($e, $auth)) {
    return "You are not authorized to edit this entry.";
  }

  my $new_perms = MT::Permission->load ({ blog_id => $e->blog_id,
      author_id => $new_author_id });
  if (!$new_perms || !$new_perms->can_post) {
    return "New author does not have sufficient access to the blog";
  }

  require Workflow;
  Workflow->load_plugins;

# Params for CanTransfer callback: app, entry, to_author, by_author
# if it passes, the entry can be transferred to the intended user
  if (MT->run_callbacks ('Workflow::CanTransfer', $app, $e, $a, $auth)) {

# Params for callback: app, entry, to_author, by_author
# the entry is being transferred, so do whatever pre-transfer stuff you want
    MT->run_callbacks ('Workflow::PreTransfer', $app, $e, $a, $auth);
    my $old_a = $e->author;
    $e->author_id ($a->id);
    $e->created_by ($old_a->id) if (!$e->created_by);
    $e->save;
    delete $e->{__author};
  
    $app->log ("Entry #".$e->id." transferred from '".$old_a->name."' to '".
    	$a->name."' by '".$auth->name."'");


# Params for callback: app, entry, from_author, by_author
    MT->run_callbacks ('Workflow::PostTransfer', $app, $e, $old_a, $auth);

# Run the callbacks 'cuz we just saved an entry

    MT->run_callbacks ('AppPostEntrySave', $app, $e);
  
# Cribbed from MT::App::CMS::save_entry
  
    if ($e->status == MT::Entry::RELEASE()) {
      if ($blog->count_static_templates('Individual') == 0 ||
  	  MT::Util->launch_background_tasks()) {
    	$app->rebuild_entry ( Entry => $e, BuildDependencies => 1 );
      	return $app->redirect ($app->mt_uri."?__mode=view&_type=entry&id=".$e->id."&blog_id=".$e->blog_id."&saved_changes=1") if ($perms->can_edit_entry ($e, $auth));
	return $app->redirect ($app->mt_uri."?__mode=list_entries&saved=1&blog_id=".$e->blog_id);
      } else {
    	return $app->redirect ($app->mt_uri."?__mode=start_rebuild&blog_id=".
  	    $e->blog_id."&next=0&type=entry-".$e->id);
      }
    } else {
      return $app->redirect ($app->mt_uri."?__mode=view&_type=entry&id=".$e->id."&blog_id=".$e->blog_id."&saved_changes=1") if ($perms->can_edit_entry ($e, $auth));
      return $app->redirect ($app->mt_uri."?__mode=list_entries&saved=1&blog_id=".$e->blog_id);
    }
  } else {
# Handle possibility that transfer was not authorized or cancelled in some way
    return $app->build_page ('error.tmpl', {
	error => "There was an error while transferring the entry."
	});
  }

}

sub transfer_entry_select {
  my ($app) = @_;
  my $q = $app->{query};

  my $id = $q->param ('id');
  if ($id) {


    require MT::Entry;
    require MT::Blog;
    require MT::Author;
    my $e = MT::Entry->load ($id);

    my $auth = $app->{author};
    require MT::Permission;

    my $perm = MT::Permission->load ({ blog_id => $e->blog_id,
	author_id => $auth->id });

    my %params;
    if (!$perm || !$perm->can_edit_entry ($e, $auth)) {
      return $app->build_page ('error.tmpl', { error => 'You do not have permission to make changes to this entry' });
    } else {
      $params{'can_edit_entry'} = 1;

      $params{'entry_title'} = $e->title;
      $params{'entry_id'}    = $e->id;
    
      require MT::Permission;
      my @perms = MT::Permission->load ({ blog_id => $e->blog_id });
  
      @perms = grep { $_->can_post && 
      	$_->author_id != $e->author_id } @perms;
  
      my @authors = map { MT::Author->load ($_->author_id) || () } @perms;

      require Workflow;
      Workflow->load_plugins;
# Params for Workflow::CanTransfer callback: app, entry, to_author, by_author
# if it passes, the entry can be transferred to that author by that author
      @authors = grep { 
	MT->run_callbacks ('Workflow::CanTransfer', $app, $e, $_, $auth)} @authors;
    
      $params{'author_loop'} = [ map { { author_name => $_->name,
   				       author_id   => $_->id } } @authors ];
    }
    return $app->build_page ('transfer_entry.tmpl', \%params);
  } else {
    return 'Id required';
  }
  
}

sub admin_publish_perms {
  my ($app) = @_;
  my $q = $app->{query};
  my $author = $app->{author};

  my $blog_id = $q->param ('blog_id');
  if ($blog_id) {

# Load up the blog
    require MT::Blog;
    my $blog = MT::Blog->load ($blog_id);

    return $app->show_error ("Blog does not exist") if (!$blog);

    require MT::PluginData;
    my $publish_perms = MT::PluginData->load ({ plugin => 'Workflow',
						key    => $blog_id });

    unless ($publish_perms) {
      require MT::Permission;
      my $perm = MT::Permission->load ({ blog_id => $blog_id,
	  				 author_id => $author->id });
      unless ($perm && $perm->can_edit_all_posts) {
	return $app->show_error ("You do not have sufficient permission to access this.");
      }

      my %params;
      $params{'blog_name'} = $blog->name;
      $params{'blog_id'} = $blog->id;
      $params{'blog_url'} = $blog->site_url;

      require Workflow;
      Workflow->load_plugins;
      my $setup_options = Workflow->all_setup_options;
      $params{'setup_options'} = [ map { { name => $_, desc => $setup_options->{$_}->{desc} || "" } } sort keys %{$setup_options} ];

      return $app->build_page ('initial_permissions.tmpl', \%params);
    }

    $publish_perms = $publish_perms->data;

#    unless ($publish_perms->{$author->id}->{'can_grant'}) {
#      return $app->show_error ('You do not have sufficient permission to access this.');
#    }

# Load the perms for the blog
    require MT::Permission;
    my @perms = MT::Permission->load ({ blog_id => $blog_id });

# Extract who can actually post
    @perms = grep { $_->can_post } @perms;

# Build the author list
    my @authors = map { MT::Author->load ($_->author_id) || () } @perms;

    my @author_loop = map { { author_name => $_->name,
      			      author_id   => $_->id,
			      author_can_publish => 
				$publish_perms->{$_->id}->{'can_publish'},
			      author_can_grant => 
				$publish_perms->{$_->id}->{'can_grant'},
                            } } @authors;


    mark_odd_rows(\@author_loop);
    my %params;
    $params{'blog_name'} = $blog->name;
    $params{'blog_id'} = $blog->id;
    $params{'blog_url'} = $blog->site_url;
    $params{'author_loop'} = \@author_loop;

    unless ($publish_perms->{$author->id}->{'can_grant'}) {
      return $app->build_page ('list_publish_perms.tmpl', \%params);
    }

    return $app->build_page ('admin_publish_perms.tmpl', \%params);
    
  }
}

sub build_initial_perms {
  my ($app) = @_;
  my $q = $app->{query};
  my $author = $app->{author};

  my $blog_id = $q->param ('blog_id');
  require MT::Blog;
  unless ($blog_id && MT::Blog->load ($blog_id)) {
    return $app->show_error ('This blog does not exist.');
  }

  require MT::Permission;
  my $perm = MT::Permission->load ({ blog_id => $blog_id, 
                                     author_id => $author->id });
  unless ($perm && $perm->can_edit_all_posts) {
    return $app->show_error ('You do not have sufficient permission to access this.');
  }

  require MT::PluginData;
  my $publish_perms = MT::PluginData->load ({ plugin => 'Workflow',
                                              key => $blog_id });
  if ($publish_perms) {
    return $app->show_error ('Workflow permissions already exist for this blog.');
  }

  $publish_perms = MT::PluginData->new ();
  $publish_perms->plugin ('Workflow');
  $publish_perms->key ($blog_id);
  
  my $perm_option = $q->param ('perm_option');
  require Workflow;
  Workflow->load_plugins;
  my $setup_options = Workflow->all_setup_options;
  return $app->show_error ('Unknown setup option') 
    if (!exists $setup_options->{$perm_option});

  my $perms_hash = {};
  foreach my $perm (MT::Permission->load ({ blog_id => $blog_id })) {
    next if (!$perm->can_post);
    $perms_hash->{$perm->author_id}->{'can_grant'}++ if 
      (MT->run_callbacks ("Workflow::${perm_option}::SetupGrant", $app, $perm) 
       && MT->run_callbacks ("Workflow::SetupGrant", $app, $perm));
    $perms_hash->{$perm->author_id}->{'can_publish'}++ if
      (MT->run_callbacks ("Workflow::${perm_option}::SetupPublish", $app, $perm)
       && MT->run_callbacks ("Workflow::SetupPublish", $app, $perm));
  }

  $publish_perms->data ($perms_hash);
  $publish_perms->save;
  
  return $app->redirect ($app->path."/plugins/Workflow/workflow.cgi?__mode=admin_publish_perms&blog_id=$blog_id");
}

sub update_publish_perms {
  my ($app) = @_;
  my $q = $app->{query};
  my $author = $app->{author};

  my $blog_id = $q->param ('blog_id');
  require MT::Blog;
  unless ($blog_id && MT::Blog->load ($blog_id)) {
    return $app->show_error ('This blog does not exist.');
  }

  require MT::PluginData;
  my $publish_perms = MT::PluginData->load ({ plugin => 'Workflow',
                                              key => $blog_id });

  unless ($publish_perms) {
    return $app->redirect ($app->path."/plugins/Workflow/workflow.cgi?__mode=admin_publish_perms&blog_id=$blog_id");
  }

  my $perms_hash = {};
  my @publish_ids = $q->param ('can_publish');
  my @grant_ids = $q->param ('can_grant');
  foreach my $id (@publish_ids) {
    $perms_hash->{$id}->{'can_publish'}++;
  }
  foreach my $id (@grant_ids) {
    $perms_hash->{$id}->{'can_grant'}++;
  }

  $publish_perms->data ($perms_hash);
  $publish_perms->save;

  return $app->redirect ($app->path."/plugins/Workflow/workflow.cgi?__mode=admin_publish_perms&blog_id=$blog_id");
}

sub build_page {
  {
    local $SIG{__WARN__} = sub { };
    $_[2]->{workflow_url} = $_[0]->path . "plugins/Workflow/" . $_[0]->script;
    require MT::App::CMS;
    MT::App::CMS::build_page (@_);
  }
}

1;
