
package Workflow;

use MT::Plugin;
@ISA = qw( MT::Plugin );

use vars qw( %Setup_options );
use strict;

use File::Spec;

sub name { 'Workflow' }
sub description { 'Workflow can limit publishing rights to editors, can limit specified authors to posting only drafts, and lets an author pass ownership of an entry to any other author or editor with appropriate permissions. Authors are notified when ownership of an entry is transferred. Version @VERSION@' }

sub add_setup_option {
  my $wkflw = shift;
  my ($key, $cfg) = @_;

  $cfg->{label} ||= $key;
  return $wkflw->error ("No executable code") 
    unless $cfg->{can_publish} && $cfg->{can_grant};
  return $wkflw->error ("Setup option already exists in the system")
    if exists $Setup_options{$key};
  $Setup_options{$key} = $cfg;

# Add the callbacks for the setup option chosen
  MT->add_callback ("Workflow::${key}::SetupPublish", 0, $wkflw, $cfg->{can_publish});
  MT->add_callback ("Workflow::${key}::SetupGrant", 0, $wkflw, $cfg->{can_grant});
}

sub all_setup_options { \%Setup_options }

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

1;
