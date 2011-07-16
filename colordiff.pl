#!/usr/bin/perl -w

########################################################################
#                                                                      #
# ColorDiff - a wrapper/replacment for 'diff' producing                #
#             colourful output                                         #
#                                                                      #
# Copyright (C)2002-2009 Dave Ewart (davee@sungate.co.uk)              #
#                                                                      #
########################################################################
#                                                                      #
# This program is free software; you can redistribute it and/or modify #
# it under the terms of the GNU General Public License as published by #
# the Free Software Foundation; either version 2 of the License, or    #
# (at your option) any later version.                                  #
#                                                                      #
# This program is distributed in the hope that it will be useful,      #
# but WITHOUT ANY WARRANTY; without even the implied warranty of       #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        #
# GNU General Public License for more details.                         #
#                                                                      #
########################################################################

use 5.008_000;
use warnings;
use strict;
use English qw( -no_match_vars );
use Getopt::Long qw(:config pass_through);
use IPC::Open2;
use Term::ANSIColor qw(:constants color);
use Module::Load::Conditional qw( can_load );
use Carp qw( carp croak );

#pull in Perl 6 given/when
use feature qw(:5.10);

if ( $PERL_VERSION < v5.12 ) {
    can_load( modules => { 'Switch' => '2.09', }, verbose => 1 );
}

# This may not be perfect - should identify most reasonably
# formatted diffs and patches
sub determine_diff_type {
    my $user_difftype = shift;
    my $input_ref     = shift;
    my $diff_type     = 'unknown';

DIFF_TYPE: foreach my $record ( @{$input_ref} ) {
        if ( defined $user_difftype ) {
            $diff_type = $user_difftype;
            last DIFF_TYPE;
        }

        given ($record) {

            # Unified diffs are the only flavour having '+++' or '---'
            # at the start of a line
            when (m/^(?:[+]{3}|---|@@)/xms) { $diff_type = 'diffu'; }

            # Context diffs are the only flavour having '***'
            # at the start of a line
            when (m/^[*]{3}/xms) { $diff_type = 'diffc'; }

            # Plain diffs have NcN, NdN and NaN etc.
            when (m/^\d+[acd]\d+$/xms) { $diff_type = 'diff'; }

         # FIXME - This is not very specific, since the regex matches could
         # easily match non-diff output.
         # However, given that we have not yet matched any of the *other* diff
         # types, this might be good enough
            when (m/(?:\s[|]\s|\s<$|\s>\s)/xms) { $diff_type = 'diffy'; }

            # wdiff deleted/added patterns
            # should almost always be pairwaise?
            when (m/\[-.*?-\]/xs)   { $diff_type = 'wdiff'; }
            when (m/\{\+.*?\+\}/xs) { $diff_type = 'wdiff'; }
        }

        if ( $diff_type ne 'unknown' ) {
            last DIFF_TYPE;
        }
    }

    return $diff_type;
}

sub show_banner {
    my $display = shift;

    exit if ( $display == 0 );

    my $app_name     = 'colordiff';
    my $version      = '2.0.0';
    my $author       = 'Dave Ewart';
    my $author_email = 'davee@sungate.co.uk';
    my $app_www      = 'http://colordiff.sourceforge.net/';
    my $copyright    = '(C)2002-2011';

    print {*STDERR} "$app_name $version ($app_www)\n";
    print {*STDERR} "$copyright $author, $author_email\n\n";

    return 0;
}

sub parse_config_file {
    my $color_ref    = shift;
    my $settings_ref = shift;
    my $location     = shift;
    my %colour       = %{$color_ref};
    my %settings     = %{$settings_ref};

    return %settings if ( !-e $location || !-r $location );

    open my $fh, '<', $location || croak "Cannot open $location: $OS_ERROR";
    my @contents = <$fh>;
    close $fh || croak "Cannot open $location: $OS_ERROR";

    foreach my $line (@contents) {
        my $colourval;
        chomp $line;
        $line =~ s/\s+//gxms;
        next if ( $line =~ m/^[#]/xms || $line =~ m/^$/xms );
        $line = lc $line;

        my ( $option, $value ) = split /=/xms, $line;
        if ( !defined $value ) {
            print {*STDERR} "$location Invalid configuration pair: '$line'\n";
            next;
        }

        if ( $option eq 'banner' ) {
            if ( $value eq 'no' ) {
                $settings{show_banner} = 0;
            }
            elsif ( $value eq 'yes' ) {
                $settings{show_banner} = 1;
            }
            next;
        }
        if ( $option eq 'color_patches' ) {
            if ( $value eq 'yes' ) {
                $settings{color_patch} = 1;
            }
            next;
        }

        if ( ( $value eq 'normal' ) || ( $value eq 'none' ) ) {
            $value = 'off';
        }

        #256 color support via specifiying the number in colordiffrc
        if ( $value =~ m/\d+/xms && $value >= 0 && $value <= 255 ) {

            if ( $value < 8 ) {
                $colourval = "\033[0;3${value}m";
            }
            elsif ( $value < 15 ) {
                $colourval = "\033[0;9${value}m";
            }
            else {
                $colourval = "\033[0;38;5;${value}m";
            }
        }
        elsif ( defined $colour{$value} ) {
            $colourval = $colour{$value};
        }
        else {
            print {*STDERR}
                "Invalid colour specification for setting $option ($value) in $location\n";
            next;
        }

        given ($option) {
            when ('plain')     { $settings{plain_text} = $colourval; }
            when ('oldtext')   { $settings{file_old}   = $colourval; }
            when ('newtext')   { $settings{file_new}   = $colourval; }
            when ('diffstuff') { $settings{diff_stuff} = $colourval; }
            when ('cvsstuff')  { $settings{cvs_stuff}  = $colourval; }
            default {
                print {
                    *STDERR
                }
                "Unknown option in $location: $option\n";
            }
        }
    }

    return %settings;
}

# ----------------------------------------------------------------------------

# ANSI sequences for colours
my %colour = (
    'white'   => "\033[1;37m",
    'yellow'  => "\033[1;33m",
    'green'   => "\033[1;32m",
    'blue'    => "\033[1;34m",
    'cyan'    => "\033[1;36m",
    'red'     => "\033[1;31m",
    'magenta' => "\033[1;35m",
    'black'   => "\033[1;30m",

    'darkwhite'   => "\033[0;37m",
    'darkyellow'  => "\033[0;33m",
    'darkgreen'   => "\033[0;32m",
    'darkblue'    => "\033[0;34m",
    'darkcyan'    => "\033[0;36m",
    'darkred'     => "\033[0;31m",
    'darkmagenta' => "\033[0;35m",
    'darkblack'   => "\033[0;30m",
    'off'         => "\033[0;0m",
);

# Default settings if /etc/colordiffrc or ~/.colordiffrc do not exist.
my %settings = (
    'plain_text'  => $colour{white},
    'file_old'    => $colour{red},
    'file_new'    => $colour{blue},
    'diff_stuff'  => $colour{magenta},
    'cvs_stuff'   => $colour{green},
    'show_banner' => 1,
    'color_patch' => 0,
);

%settings = parse_config_file( \%colour, \%settings, '/etc/colordiffrc' );
if ( defined $ENV{HOME} ) {
    %settings = parse_config_file( \%colour, \%settings,
        "$ENV{HOME}/.colordiffrc" );
}

# If output is to a file, switch off colours, unless 'color_patch' is set
# Relates to http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=378563
if ( ( -f STDOUT ) && ( $settings{color_patch} == 0 ) ) {
    $settings{plain_text} = q{};
    $settings{file_old}   = q{};
    $settings{file_new}   = q{};
    $settings{diff_stuff} = q{};
    $settings{cvs_stuff}  = q{};
    $colour{off}          = q{};
}

my $specified_difftype;
GetOptions( "difftype=s" => \$specified_difftype );

show_banner( $settings{show_banner} );

my @inputstream;

my $exitcode = 0;
if ( ( defined $ARGV[0] ) || ( -t STDIN ) ) {

    # More reliable way of pulling in arguments
    my $pid = open2( \*INPUTSTREAM, undef, 'diff', @ARGV );
    @inputstream = <INPUTSTREAM>;
    close INPUTSTREAM;
    waitpid $pid, 0;
    $exitcode = $CHILD_ERROR >> 8;
}
else {
    @inputstream = <STDIN>;
}

my $diff_type = determine_diff_type( $specified_difftype, \@inputstream );

# ------------------------------------------------------------------------------
# Special pre-processing for side-by-side diffs
# Figure out location of central markers: these will be a consecutive set of
# three columns where the first and third always consist of spaces and the
# second consists only of spaces, '<', '>' and '|'
# This is not a 100% certain match, but should be good enough

my %separator_col  = ();
my %candidate_col  = ();
my $diffy_sep_col  = 0;
my $mostlikely_sum = 0;
my $longest_record = 0;

if ( $diff_type eq 'diffy' ) {

    # Not very elegant, but does the job
    # Unfortunately requires parsing the input stream multiple times
    foreach my $line (@inputstream) {

        # Convert tabs to spaces
        while ( ( my $i = index $line, "\t" ) > -1 ) {
            substr $line, $i, 1,    # range to replace
                ( q{ } x ( 8 - ( $i % 8 ) ) );    # string to replace with
        }
        if ( length($line) > $longest_record ) {
            $longest_record = length $line;
        }
    }

    for my $i ( 0 .. $longest_record ) {
        $separator_col{$i} = 1;
        $candidate_col{$i} = 0;
    }

    foreach (@inputstream) {

        # Convert tabs to spaces
        while ( ( my $i = index $_, "\t" ) > -1 ) {
            substr $_, $i, 1,    # range to replace
                ( q{ } x ( 8 - ( $i % 8 ) ) );    # string to replace with
        }
        for my $i ( 0 .. ( length($_) - 3 ) ) {
            next if ( !defined $separator_col{$i} );
            next if ( $separator_col{$i} == 0 );
            my $subsub = substr $_, $i, 2;
            if (   ( $subsub ne q{  } )
                && ( $subsub ne ' |' )
                && ( $subsub ne ' >' )
                && ( $subsub ne ' <' ) )
            {
                $separator_col{$i} = 0;
            }
            if (   ( $subsub eq ' |' )
                || ( $subsub eq ' >' )
                || ( $subsub eq ' <' ) )
            {
                $candidate_col{$i}++;
            }
        }
    }

    for my $i ( 0 .. ( $longest_record - 3 ) ) {
        if ( $separator_col{$i} == 1 ) {
            if ( $candidate_col{$i} > $mostlikely_sum ) {
                $diffy_sep_col  = $i;
                $mostlikely_sum = $i;
            }
        }
    }
}

# ------------------------------------------------------------------------------

my $inside_file_old = 1;

foreach (@inputstream) {
    if ( $diff_type eq 'diff' ) {
        given ($_) {
            when (m/^</xms)  { print $settings{file_old}; }
            when (m/^>/xms)  { print $settings{file_new}; }
            when (m/^\d/xms) { print $settings{diff_stuff}; }
            when (
                m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                )
            {
                print $settings{cvs_stuff};
            }
            when (m/^Only[ ]in/xms) { print $settings{diff_stuff}; }
            default                 { print $settings{plain_text}; }
        }
    }
    elsif ( $diff_type eq 'diffc' ) {
        given ($_) {
            when (m/^-[ ]/xms)      { print $settings{file_old}; }
            when (m/^[+][ ]/xms)    { print $settings{file_new}; }
            when (m/^[*]{4,}/xms)   { print $settings{diff_stuff}; }
            when (m/^Only[ ]in/xms) { print $settings{diff_stuff}; }
            when (m/^[*]{3}[ ]\d+,\d+/xms) {
                print $settings{diff_stuff};
                $inside_file_old = 1;
            }
            when (m/^[*]{3}[ ]/xms) { print $settings{file_old}; }
            when (m/^---[ ]\d+,\d+/xms) {
                print $settings{diff_stuff};
                $inside_file_old = 0;
            }
            when (m/^---[ ]/xms) { print $settings{file_new}; }
            when (m/^!/xms) {
                $inside_file_old == 1
                    ? print $settings{file_old}
                    : print $settings{file_new};
            }
            when (
                m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                )
            {
                print $settings{cvs_stuff};
            }
            default { print $settings{plain_text}; }
        }
    }
    elsif ( $diff_type eq 'diffu' ) {
        given ($_) {
            when (m/^-/xms)         { print $settings{file_old}; }
            when (m/^[+]/xms)       { print $settings{file_new}; }
            when (m/^[@]/xms)       { print $settings{diff_stuff}; }
            when (m/^Only[ ]in/xms) { print $settings{diff_stuff}; }
            when (
                m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                )
            {
                print $settings{cvs_stuff};
            }
            default { print $settings{plain_text}; }
        }
    }

    # Works with previously-identified column containing the diff-y
    # separator characters
    elsif ( $diff_type eq 'diffy' ) {
        if ( length($_) > ( $diffy_sep_col + 2 ) ) {
            my $sepchars = substr $_, $diffy_sep_col, 2;
            if ( $sepchars eq ' <' ) {
                print $settings{file_old};
            }
            elsif ( $sepchars eq ' |' ) {
                print $settings{diff_stuff};
            }
            elsif ( $sepchars eq ' >' ) {
                print $settings{file_new};
            }
            else {
                print $settings{plain_text};
            }
        }
        elsif (m/^Only[ ]in/xms) {
            print $settings{diff_stuff};
        }
        else {
            print $settings{plain_text};
        }
    }
    elsif ( $diff_type eq 'wdiff' ) {
        $_ =~ s/(\[-[^]]*?-\])/$settings{file_old}$1$colour{off}/gms;
        $_ =~ s/(\{\+[^]]*?\+\})/$settings{file_new}$1$colour{off}/gms;
    }
    elsif ( $diff_type eq 'debdiff' ) {
        $_ =~ s/(\[-[^]]*?-\])/$settings{file_old}$1$colour{off}/gms;
        $_ =~ s/(\{\+[^]]*?\+\})/$settings{file_new}$1$colour{off}/gms;
    }

    print $_, color 'reset';
}

exit $exitcode;
