use strict;
use warnings;

use lib 't/lib', 'lib', 'extlib';

use MT::Test qw( :db :data );

use Test::More tests => 21;

require MT::Object;
require_ok ('Workflow::Step');
ok (MT::Object->driver->table_exists ('Workflow::Step'), "Table exists for step data");

require MT::Blog;
my $blog = MT::Blog->load ( 1 );

is (Workflow::Step->first_step( 1 ), undef, "No first step");
is (Workflow::Step->last_step( 1 ), undef, "No last step");

# create a test step
my $step = Workflow::Step->new;
$step->blog_id ( 1 );
$step->name ( 'First Step' );
$step->description ( 'Testing first step' );
$step->order ( 1 );
ok ($step->save, "Saved test step") or diag ("Error saving step: " . $step->errstr);

is ($step->next, undef, "No next step");
is ($step->previous, undef, "No previous step");

is (Workflow::Step->first_step( 1 )->id, $step->id, "Only step is the first step");
is (Workflow::Step->last_step( 1 )->id, $step->id, "Only step is the last step");

my $step2 = Workflow::Step->new;
$step2->blog_id ( 1 );
$step2->name ( 'Second step' );
$step2->description ( 'Testing second step' );
$step2->order ( 2 );
ok ($step2->save, "saved second test step") or diag ("Error saving second step: " . $step2->errstr);

is (Workflow::Step->first_step( 1 )->id, $step->id, "First step is the first step");
is (Workflow::Step->last_step( 1 )->id, $step2->id, "Second step is the last step");

my $step0 = Workflow::Step->new;
$step0->blog_id ( 1 );
$step0->name ( 'Zeroth step' );
$step0->description ( 'Testing zeroth step' );
$step0->order ( 0 );
ok ($step0->save, "Saved zeroth test step") or diag ("Error saving zeroth step: " . $step0->errstr);

is (Workflow::Step->first_step( 1 )->id, $step0->id, "Zeroth step is the first step");
is (Workflow::Step->last_step( 1 )->id, $step2->id, "Second step is the last step");

my @members = $step->members;
is (scalar @members, 0, "Members list of an empty step should be empty");

require MT::Author;
my $author = MT::Author->load ( 1 );

require_ok ('Workflow::StepAssociation');
my $sa = Workflow::StepAssociation->new;
$sa->blog_id ( 1 );
$sa->step_id ( $step->id );
$sa->type ( 'author' );
$sa->assoc_id ( 1 );
ok ($sa->save, "Step association saved") or diag ("Error saving step association: " . $sa->errstr);

@members = $step->members;
is (scalar @members, 1, "Members list should have one author");
is ($members[0]->id, $author->id, "First author id matches");
is ($members[0]->name, $author->name, "First author name matches");
