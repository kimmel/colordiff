#!./perl

use warnings;
use strict;
use Test::More qw( tests 7 );
use lib 'lib';

BEGIN {
    use_ok('colordiff');
}

my @colordiff_subs = (
    'determine_diff_type', 'show_banner',
    'parse_config_file',   'preprocess_input',
    'parse_and_print',     'run',
);

foreach my $sub (@colordiff_subs) {
    can_ok( __PACKAGE__, $sub );
}
