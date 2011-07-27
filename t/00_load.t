#!/usr/bin/perl

use warnings;
use strict;

use Test::More qw( tests 14 );

BEGIN {
    my @classes = qw(
        Carp
        English
        Getopt::Long
        IPC::Open2
        Module::Load::Conditional
        Pod::Usage
        Term::ANSIColor
        Test::More
        Test::Most
        Test::Output
        Test::Pod
        Test::Pod::Coverage
        Test::Spelling
        IO::All
    );

    foreach my $class (@classes) {
        use_ok $class or BAIL_OUT("Could not load $class");
    }
}
