#!./perl

use warnings;
use strict;
use Test::Pod::Coverage;
use Carp qw( carp croak );
use Term::ANSIColor qw(:constants color);

all_pod_coverage_ok();
