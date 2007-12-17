package Workflow::Workflowable;

sub get_audit_log {
    my $obj = shift;
    
    require Workflow::AuditLog;
}

sub workflow_step {
    my $obj = shift;
    
    if (my $status = $obj->workflow_status) {
        require Workflow::Step;
        return Workflow::Step->load ($status->step_id);
    }
    else {
        return undef;
    }
}

sub workflow_status {
    my $obj = shift;
    
    require Workflow::Status;
    return Workflow::Status->load ({ object_id => $obj->id, object_datasource => $obj->datasource });
}

sub init_workflow {
    my $class = shift;
    $class = ref ($class) if (ref ($class));
    my (%params) = @_;
    
    # Edit fields
    if ($params{TextFields}) {
        $params{TextFields} = [ $params{TextFields} ] if (!ref ($params{TextFields}));
        $class->{__workflow}->{edit_fields} = $param{TextFields};
    }
    else {
        $class->{__workflow}->{edit_fields} = [];
    }
    
    if ($params{StatusField} || $class->has_column ('status')) {
        my $status_col = $params{StatusField} || 'status';
        $class->{__workflow}->{status_field} = $status_col;
    }
    
    if ($params{OwnerField} || $class->has_column ('author_id')) {
        my $owner_field = $params{OwnerField} || 'author_id';
        $class->{__workflow}->{owner_field} = $owner_field;
    }
}

sub workflow_update {
    my $obj = shift;
    my ($orig, $direction, $note) = @_;
    
    my $class = ref ($obj);
    
    require Workflow::AuditLog;
    my $al = Workflow::AuditLog->new;
    $al->object_id ($obj->id);
    $al->object_datasource ($obj->datasource);
    if (my $status_field = $class->{__workflow}->{status_field}) {
        $al->new_status ($obj->$status_field);
        $al->old_status ($orig ? $orig->$status_field : 0);
    }
    if (!$orig) {
        # New object!
        $al->edited (0);
    }
    else {
        # Check the various text fields for changes
        my $is_edited = 0;
        foreach my $field (@{$class->{__workflow}->{edit_fields}}) {
            $is_edited ||= ($obj->$field ne $orig->$field);
        }
        $al->edited ($is_edited);
    }
    $al->save;
    
    # No need to keep going unless it's something *other* than 0
    return unless ($direction);
    
    if ($direction > 0) {
        # move it along to the next user in the workflow
        $plugin->_automatic_transfer ($cb, $app, $app->user, $obj) or return $cb->error ($cb->errstr);
    }
    elsif ($direction < 0) {
        # bounce it back to the previous owner
        my $prev_owner = $obj->workflow_previous_owner;
        my $old_prev_owner;
        
        # to get prev prev owner (to support firing things back up multiple steps)
        my $step = $obj->workflow_step;
        if ($step) {
            if (my $prev = $step->previous) {
                # find the most recent audit log instance where the obj was transferred to this step
                my $prev_al = Workflow::AuditLog->load ({ object_id => $obj->id, object_datasource => $obj->datasource, new_step_id => $prev->id},
                    { sort => 'created_on', direction => 'descend', limit => 1 }
                );
                if ($prev_al) {
                    $old_prev_owner = $prev_al->transferred_from;
                }
            }
        }
        
        if ($prev_owner) {
            $obj->workflow_transfer ($prev_owner, $old_prev_owner) or return $obj->error ("Error transferring: " . $obj->errstr);
        }
    }
    else {
        return;
    }
    
    my $prev_owner = $obj->workflow_previous_owner;
    my $owner      = $obj->workflow_owner;

    # There was a transfer, so add that to the log
    $al->transferred_from ($prev_owner->id) if ($prev_owner);
    $al->transferred_to ($owner->id) if ($owner);
    $al->note ($note);
    $al->save;
}

sub workflow_transfer {
    my $obj = shift;
    my ($to, $prev) = @_;
    
    # Make sure we have an author reference here
    require MT::Author;
    $to = MT::Author->load ($to) if (!ref ($to));
    
    # Kick out if there's nobody to transfer to
    return if (!$to);
    
    if (MT->run_callbacks ('Workflow::CanTransfer.' . $obj->datasource, $obj, $to)) {
        
        # Grab the current author
        my $old_owner = $obj->workflow_owner;
        if ($prev) {
            $prev = MT::Author->load ($prev) if (!ref ($prev));
            $old_owner = $prev if ($prev);
        }
        
        # Why separate CanTransfer from PreTransfer?  I'm honestly not sure
        # Probably because it will allow callback writers to assume that the transfer has been approved
        # by the time the PreTransfer callback is made.
        # That is not an assumption that can be made in CanTransfer as a later callback might kick back a disapproval
        MT->run_callbacks ('Workflow::PreTransfer.' . $obj->datasource, $obj, $old_owner, $to);
        
        # Perform the actual entry transfer
        # $plugin->_transfer_entry ($eh, $app, %params) or return $eh->error ($eh->errstr);
     
        $obj->workflow_previous_owner ($old_owner) or return $obj->error ("Error setting previous owner: " . $obj->errstr);
        $obj->workflow_owner ($to) or return $obj->error ("Error setting new owner: " . $obj->errstr);
        $obj->save or return $obj->error ("Error transferring: " . $obj->errstr);
        
        # Run the PostTransfer callbacks
        MT->run_callbacks ('Workflow::PostTransfer.' . $obj->datasource, $obj, $old_owner, $to);
        
        # Entry was successfully transfereed, so return a true value
        return 1;
    }
    else {
        return $obj->error ("Cannot be transfered");
    }
}

sub workflow_owner {
    my $obj = shift;
    my $class = ref ($obj);
    my ($new_owner) = @_;
    
    my $status = $obj->workflow_status;
    require MT::Author;
    if ($new_owner) {
        $new_owner = MT::Author->load ($new_owner) if (!ref ($new_owner));
        return $obj->error ("Unknown user") if (!$new_owner);
        
        $status->owner_id ($new_owner->id);
        $status->save;
        if (my $owner_field = $class->{__workflow}->{owner_field}) {
            $obj->$owner_field ($new_owner->id);
        }
        
        return $new_owner;
    }
    else {
        my $owner_id;
        if (my $owner_field = $class->{__workflow}->{owner_field}) {
            $owner_id = $obj->$owner_field;
        }
        else {
            my $status = $obj->workflow_status;
            $owner_id = $status->owner_id if ($status);
        }
        return if (!$owner_id);
        return MT::Author->load ($owner_id);        
    }
}

sub workflow_previous_owner {
    my $obj = shift;
    my $class = ref ($obj);
    my ($new_prev) = @_;
    
    my $status = $obj->workflow_status;
    require MT::Author;
    if ($new_prev) {
        $new_prev = MT::Author->load ($new_prev) if (!ref ($new_prev));
        return $obj->error ("Unknown user") if (!$new_prev);
        
        $status->previous_owner_id ($new_prev->id);
        $status->save;
        
        return $new_prev;        
    }
    
    # return a defined but false value for no existing previous owner
    return 0 if (!$status || !$status->previous_owner_id);
    
    return MT::Author->load ($status->previous_owner_id);
}


1;