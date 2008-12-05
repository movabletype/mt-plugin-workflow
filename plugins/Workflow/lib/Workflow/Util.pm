
package Workflow::Util;
use strict;
use warnings;

use Data::Dumper;

use Exporter;
@Workflow::Util::ISA = qw( Exporter );
use vars qw( @EXPORT_OK );
@EXPORT_OK = qw( use_blog_id );

sub use_blog_id {
# default to -1 (system-wide steps) if no steps exist for this particular blog
	my ($blog_id) = @_;
	if (MT->model('workflow_step')->count({ blog_id => $blog_id })) {
		return $blog_id;
	}
	return 0;
}

1;
