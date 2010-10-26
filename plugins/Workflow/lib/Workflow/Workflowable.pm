############################################################################
# Copyright © 2006-2010 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

package Workflow::Workflowable;

use Data::Dumper;

sub get_audit_log {
    my $obj = shift;

    require Workflow::AuditLog;
}

sub workflow_step {
    my $obj = shift;

    if (my $status = $obj->workflow_status) {
        return undef unless $status->step_id;
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
    my $status = Workflow::Status->load ({ object_id => $obj->id, object_datasource => $obj->datasource });
    return $status if ($status);

    my $class = ref ($obj);
    $status = Workflow::Status->new;

    # Set the step bits
    my $first_step = Workflow::Step->first_step ($obj->blog_id);
    $status->step_id ($first_step->id) if ($first_step);

    # Set the db pointing bits
    $status->object_id ($obj->id);
    $status->object_datasource ($obj->datasource);

    # Grab the 'owner', either from the owner field
    # or from the current app user
    if (my $owner_field = $class->{__workflow}->{owner_field}) {
        $status->owner_id ($obj->$owner_field);
    }
    else {
        require MT::App;
        my $app = MT::App->instance;
        $status->owner_id ($app->user->id) if ($app->user);
    }

    # There can't be a previous owner, since we're just starting here
    $status->previous_owner_id (0);

    $status->save or return $obj->error ("Error creating status: " . $status->errstr);
    return $status;
}

sub workflow_init {
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
    my ($orig, $direction, $note, $transfer) = @_;

    my $class = ref ($obj);

    my $status = $obj->workflow_status or die $obj->errstr;

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

    # No need to keep going unless it's something *other* than 0
    return 0 unless ($direction);

    # explicit transfer
    if ($direction == -2) {
        $obj->workflow_transfer ($note, $transfer) or return $obj->error ("Error transferring: " . $obj->errstr);
        return 1;
    }

    # At this point, there will be a transfer one way or the other,
    # so snag the current step for the audit log
    my $current_step = $status->step;
    my $new_step;
    if ($direction > 0) {
        if ($status) {
            if ($current_step) {
                $new_step = $current_step->next;
                if ($new_step) {
                    # get the list of possible owners from the next step
                    my @editors = $new_step->members;

                    # sort them somehow and grab the first one
                    # - callback?
                    # - the original automatic transfer sort based on published entries?
                    # - simple random selection?
                    # - all of those can be done with callbacks, to be honest, I just worry about doing db-based sorting in callbacks
                    #   but that could be handled with a little caching

                    $obj->_clear_transfer_score_cache;
                    @editors = sort { $obj->_transfer_score ($a) <=> $obj->_transfer_score ($b) } @editors;

                    my $next_owner = $editors[0];
                    $obj->workflow_transfer ($note, $next_owner) or return $obj->error ("Error transferring: " . $obj->errstr);
                }
            }
        }
        # move it along to the next user in the workflow
        # $plugin->_automatic_transfer ($cb, $app, $app->user, $obj) or return $cb->error ($cb->errstr);
    }
    elsif ($direction < 0) {
        # bounce it back to the previous owner
        my $prev_owner = $obj->workflow_previous_owner;
        my $old_prev_owner;

        # to get prev prev owner (to support firing things back up multiple steps)
        if ($current_step) {
            if ($new_step = $current_step->previous) {
                # find the most recent audit log instance where the obj was transferred to this step
                my $prev_al = Workflow::AuditLog->load ({ object_id => $obj->id, object_datasource => $obj->datasource, new_step_id => $new_step->id},
                    { sort => 'created_on', direction => 'descend', limit => 1 }
                );
                if ($prev_al) {
                    $old_prev_owner = $prev_al->transferred_from;
                }
            }
        }

        if ($prev_owner) {
            $obj->workflow_transfer ($note, $prev_owner, $old_prev_owner) or return $obj->error ("Error transferring: " . $obj->errstr);

        }
    }

    my $prev_owner = $obj->workflow_previous_owner;
    my $owner      = $obj->workflow_owner;

    # There was a transfer, so add that to the log
    $al->transferred_from ($prev_owner->id) if ($prev_owner);
    $al->transferred_to ($owner->id) if ($owner);
    $al->old_step_id ($current_step ? $current_step->id : 0);
    $al->new_step_id ($new_step_id ? $new_step->id : $current_step ? $current_step->id : 0);
    $status->step_id ($new_step->id) if ($new_step);
    $al->note ($note);
    $al->save or die $al->errstr;
    $status->save or die $status->errstr;
}

sub workflow_transfer {
    my $obj = shift;
    my ($note, $to, $prev) = @_;

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
        MT->run_callbacks ('Workflow::PreTransfer.' . $obj->datasource, $obj, $old_owner, $to, $note);

        # Perform the actual entry transfer
        # $plugin->_transfer_entry ($eh, $app, %params) or return $eh->error ($eh->errstr);

        $obj->workflow_previous_owner ($old_owner) or return $obj->error ("Error setting previous owner: " . $obj->errstr);
        $obj->workflow_owner ($to) or return $obj->error ("Error setting new owner: " . $obj->errstr);
        $obj->save or return $obj->error ("Error transferring: " . $obj->errstr);

        # Run the PostTransfer callbacks
        MT->run_callbacks ('Workflow::PostTransfer.' . $obj->datasource, $obj, $old_owner, $to, $note);

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

sub _clear_transfer_score_cache {
    my $obj = shift;
    $obj->{__workflow}->{transfer_score} = {};
}

sub _transfer_score {
    my $obj = shift;
    my ($author) = @_;

    # Grab from cache if it exists (because it could be a 0 value)
    return $obj->{__workflow}->{transfer_score}->{$author->id} if (exists $obj->{__workflow}->{transfer_score}->{$author->id});

    # for now, we'll just get the latest status change they are involved in
    require Workflow::Status;
    my $status = Workflow::Status->load ({ modified_by => $author->id }, { sort => 'modified_on', direction => 'descend', limit => 1 });
    $obj->{__workflow}->{transfer_score}->{$author->id} = $status ? $status->modified_on : 0;
}

1;
