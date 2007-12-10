package Workflow::CMS;

sub edit_workflow {
    my $app = shift;
    
    $app->load_tmpl ('workflow_edit.tmpl', {});
}

1;