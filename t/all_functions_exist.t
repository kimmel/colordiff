#!./perl

use warnings;
use strict;
use Test::More qw( tests 7 );

BEGIN {
    use_ok('colordiff');
}

can_ok( __PACKAGE__, 'determine_diff_type' );
can_ok( __PACKAGE__, 'show_banner' );
can_ok( __PACKAGE__, 'parse_config_file' );
can_ok( __PACKAGE__, 'preprocess_input' );
can_ok( __PACKAGE__, 'parse_and_print' );
can_ok( __PACKAGE__, 'run' );
