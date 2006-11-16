#!/usr/bin/perl -w

use strict;

my ($MT_DIR);
BEGIN {
    my $programpath = $ENV{SCRIPT_FILENAME} || $0;

    # If we have slashes, we have a path
    # If not, we just have a program name
    if ($programpath !~ m![/\\]!) {
        foreach ('.','..','../..') {
            if (-r "$_/lib/MT.pm") {
                $MT_DIR = "$_/";
                last;
            }
        }
    } else {
        $programpath =~ s!([/\\]){2}!$1!g;
        $programpath =~ s![/\\]plugins[/\\]Workflow!!;
        $programpath =~ s!(.+[/\\]).*!$1!;
        $MT_DIR = $programpath;
    }
    unshift @INC, $MT_DIR . 'lib';
    unshift @INC, $MT_DIR . 'extlib';
}

use lib './lib';
use lib './plugins/Workflow/lib';
use Workflow::App;

eval {
    my $app = Workflow::App->new(#AltTemplatePath => './tmpl',
				 Config => $MT_DIR . 'mt.cfg',
                                 Directory => $MT_DIR )
        or die Workflow::App->errstr;
    local $SIG{__WARN__} = sub { $app->trace($_[0]) };
    $app->run;
};
if ($@) {
    print "Content-Type: text/html\n\n";
    print "An error occurred: $@";
}

