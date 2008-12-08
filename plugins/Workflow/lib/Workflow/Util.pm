
package Workflow::Util;
use strict;
use warnings;

use Data::Dumper;

use Exporter;
@Workflow::Util::ISA = qw( Exporter );
use vars qw( @EXPORT_OK );
@EXPORT_OK = qw( use_blog_id );

sub use_blog_id {
# default to 0 (system-wide steps) if no steps exist for this particular blog
	my ($blog_id) = @_;
	if (MT->model('workflow_step')->count({ blog_id => $blog_id })) {
		return $blog_id;
	}
	my $plugin = MT->component('workflow');
	# if setting to use system steps is off, return -1 so nothing will be found
	return $plugin->get_config_value('use_system', "blog:$blog_id") ? 0 : -1;
}

1;
