package Workflow::Tags;

use Data::Dumper;
use Workflow::Step;
use Workflow::AuditLog;

sub hdlr_blog_workflow_steps {
	my ($ctx, $args, $cond)
	my $blog = $ctx->stash('blog')
		|| return $ctx->error('Not called from blog context');
	my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
	my %terms = (
		blog_id => $blog->id,
	);
	my %load_args = (
		sort => $args->{sort_by} || 'order',
		direction => $args->{sort_order} || 'ascend',
	);
	my $result = '';
	for my $step (MT->model('workflow_step')->load(\%terms, \%load_args)) {
		local $ctx->{__stash}{workflow_step} = $step;
        defined(my $out = $builder->build($ctx, $tokens, $cond))
            or return $ctx->error( $builder->errstr );
		$result .= $out;
	}
	return $result;
}

sub hdlr_entry_workflow_steps {
	my ($ctx, $args, $cond)
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
	my %terms = (
		object_id => $entry->id,
		object_datasource => 'entry',
	);
	if ($args->{'id'}) {
		$terms{old_step_id} = $args->{'id'};
	} elsif ($args->{'name'}) {
		my $step = MT->model('workflow_step')->load({ name => $args->{name} });
		$step && ($terms{old_step_id})
	} elsif (my $step = $ctx->stash('workflow_step')) {
		$terms{old_step_id} = $step->id;
	}
	if (!$terms{old_step_id}) {
		return $ctx->error('No step specified');
	}
	my $al = MT->model('workflow_audit_log')->load(\%terms);
	return $al ? 1 : 0;
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
	return audit_log_column('note', @_);
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