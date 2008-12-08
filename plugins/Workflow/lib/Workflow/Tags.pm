package Workflow::Tags;

use Data::Dumper;
use Workflow::Step;
use Workflow::AuditLog;
use Workflow::Util qw( use_blog_id );

sub hdlr_blog_workflow_steps {
	my ($ctx, $args, $cond) = @_;
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	my $result = '';
	my @steps = blog_steps($ctx, $args);
	local $ctx->{__stash}{workflow_steps} = \@steps;
	for my $step (@steps) {
		local $ctx->{__stash}{workflow_step} = $step;
        defined(my $out = $builder->build($ctx, $tokens, $cond))
            or return $ctx->error( $builder->errstr );
		$result .= $out;
	}
	return $result;
}

sub blog_steps {
	my ($ctx, $args) = @_;
	my $blog = $ctx->stash('blog')
		|| return $ctx->error('Not called from blog context');
	my %terms = (
		blog_id => use_blog_id($blog->id),
	);
	my %load_args = (
		sort => $args->{sort_by} || 'order',
		direction => $args->{sort_order} || 'ascend',
	);
	my @steps = MT->model('workflow_step')->load(\%terms, \%load_args);
	return @steps;
}

sub hdlr_entry_workflow_steps {
	my ($ctx, $args, $cond) = @_;
	my $entry = $ctx->stash('entry')
		|| return $ctx->error('Not called from entry context');
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	my %terms = (
		object_id => $entry->id,
		object_datasource => 'entry',
	);
	my %load_args = (
		sort => $args->{sort_by} || 'created_on',
		direction => $args->{sort_order} || 'ascend',
	);
	my $result = '';
	for my $al (MT->model('workflow_audit_log')->load(\%terms, \%load_args)) {
		my $step = MT->model('workflow_step')->load($al->new_step_id);
		local $ctx->{__stash}{workflow_audit_log} = $al;
		local $ctx->{__stash}{workflow_step} = $step;
        defined(my $out = $builder->build($ctx, $tokens, $cond))
            or return $ctx->error( $builder->errstr );
		$result .= $out;
	}
	return $result;
}

sub hdlr_entry_if_step {
	my ($ctx, $args, $cond) = @_;
	my $entry = $ctx->stash('entry')
		|| return $ctx->error('Not called from entry context');
	my $step;
	if ($args->{'id'}) {
		$step = MT->model('workflow_step')->load($args->{'id'});
	} elsif ($args->{'name'}) {
		$step = MT->model('workflow_step')->load({ name => $args->{name} });
	} else {
		$step = $ctx->stash('workflow_step');
	}
	if (!$step) {
		return $ctx->error('No step specified');
	}
	my %terms = (
		object_id => $entry->id,
		object_datasource => 'entry',
	);
	my $status = MT->model('workflow_status')->load(\%terms);
	return 0 unless $status;
	my $cur_step = MT->model('workflow_step')->load($status->step_id);
	return 0 unless $cur_step;
	return ($cur_step->order > $step->order) ? 1 : 0;
}

sub hdlr_old_step {
	my ($ctx, $args, $cond) = @_;
	my $old_step_id = audit_log_column('old_step_id', $ctx, $args);
	return '' unless $old_step_id;
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	my $old_step = MT->model('workflow_step')->load($old_step_id);
	local $ctx->{__stash}{workflow_step} = $old_step;
	defined(my $out = $builder->build($ctx, $tokens, $cond))
		or return $ctx->error( $builder->errstr );
	return $out;
}

sub hdlr_step_author {
	my ($ctx, $args, $cond) = @_;
	my $author_id = audit_log_column('transferred_to', $ctx, $args);
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	local $ctx->{__stash}{author} = MT->model('author')->load($author_id);
	defined(my $out = $builder->build($ctx, $tokens, $cond))
		or return $ctx->error( $builder->errstr );
	return $out;
}

sub hdlr_step_old_author {
	my ($ctx, $args, $cond) = @_;
	my $author_id = audit_log_column('transferred_from', $ctx, $args);
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	local $ctx->{__stash}{author} = MT->model('author')->load($author_id);
	defined(my $out = $builder->build($ctx, $tokens, $cond))
		or return $ctx->error( $builder->errstr );
	return $out;
}

sub hdlr_step_if_transferred {
	my ($ctx, $args, $cond) = @_;
	my $from_author_id = audit_log_column('transferred_from', $ctx, $args);
	my $to_author_id = audit_log_column('transferred_to', $ctx, $args);
	return ($from_author_id ne $to_author_id) ? 1 : 0;	
}

sub hdlr_step_id {
	return step_column('id', @_);
}

sub hdlr_step_name {
	return step_column('name', @_);
}

sub hdlr_step_description {
	return step_column('description', @_);
}

sub hdlr_step_order {
	return step_column('order', @_);
}

sub hdlr_step_note {
	return audit_log_column('note', @_);
}

sub hdlr_step_old_status {
	return audit_log_column('old_status', @_);
}

sub hdlr_step_new_status {
	return audit_log_column('new_status', @_);
}

sub audit_log_column {
	my ($col, $ctx, $args) = @_;
	my $al = $ctx->stash('workflow_audit_log')
		|| return $ctx->error('Not called from step context');
	return $al->$col;
}

sub step_column {
	my ($col, $ctx, $args) = @_;
	my $step = $ctx->stash('workflow_step')
		|| return $ctx->error('Not called from step context');
	return $step->$col;
}

1;