#!/usr/bin/perl

# See the POD at the end of the file.

use warnings;
use strict;
use diagnostics;

use English qw( -no_match_vars );
use Getopt::Long qw( GetOptions :config pass_through );
use Pod::Usage qw( pod2usage );
use IPC::Open2;
use Term::ANSIColor qw(:constants color colorvalid);
use Module::Load::Conditional qw( can_load );
use Carp qw( carp croak );

use AppConfig::File;

package main;

#pull in Perl 6 given/when
use feature qw(:5.10);

if ( $PERL_VERSION < v5.12 ) {
    can_load( modules => { 'Switch' => '2.09', }, verbose => 1 )
        or die "$ERRNO Cannot load module Switch.\n";
}

# This may not be perfect - should identify most reasonably
# formatted diffs and patches
sub determine_diff_type {
    my $input_ref = shift;
    my $diff_type = 'unknown';

DIFF_TYPE: foreach my $record ( @{$input_ref} ) {
        given ($record) {

            # Unified diffs are the only flavour having '+++' or '---'
            # at the start of a line
            when (m/^(?:[+]{3}|---|@@)/xms) { $diff_type = 'diffu'; }

            # Context diffs are the only flavour having '***'
            # at the start of a line
            when (m/^[*]{3}/xms) { $diff_type = 'diffc'; }

            # Plain diffs have NcN, NdN and NaN etc.
            when (m/^\d+[acd]\d+$/xms) { $diff_type = 'diff'; }

            # FIXME - This is not very specific, since the regex matches
            # could easily match non-diff output.  However, given that we
            # have not yet matched any of the *other* diff types, this might
            # be good enough
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

    return if ( $display == 0 );

    my $app_name     = 'colordiff';
    my $version      = '2.0.0alpha';
    my $author       = 'Dave Ewart';
    my $author_email = 'davee@sungate.co.uk';
    my $app_www      = 'http://colordiff.sourceforge.net/';
    my $copyright    = '(C)2002-2011';

    print {*STDERR} "$app_name $version ($app_www)\n";
    print {*STDERR} "$copyright $author, $author_email\n\n";

    return 0;
}

sub _validate_config_option {
    my $name  = shift;
    my $value = shift;

    return 0 if ( $value =~ m/(none| normal| off)/ixms );
    return 1 if ( colorvalid($value) );
    return 1 if ( $value =~ m/\d{1,3}/xms and $value >= 0 and $value <= 255 );

    return 0;
}

sub parse_config_file {

    # Default settings if /etc/colordiffrc and ~/.colordiffrc do not exist.
    my @boolean_options = (
        [ 'banner',        'yes', '(yes|no)', ],
        [ 'color_patches', 'no',  '(yes|no)', ],
    );
    my @color_codes = (
        [ 'plain',     'white', ],
        [ 'newtext',   'blue', ],
        [ 'oldtext',   'red', ],
        [ 'diffstuff', 'magenta', ],
        [ 'cvsstuff',  'green', ],
        [ 'off',       'off', ],
    );
    my $state = AppConfig::State->new(
        {   GLOBAL => { ARGCOUNT => 1, },
            ERROR  => sub        { },
        }
    );

    foreach my $v (@boolean_options) {
        $state->define( @{$v}[0],
            { DEFAULT => @{$v}[1], VALIDATE => @{$v}[2] } );
    }
    foreach my $v (@color_codes) {
        $state->define( @{$v}[0],
            { DEFAULT => @{$v}[1], VALIDATE => \&_validate_config_option } );
    }

    my $conf_file = AppConfig::File->new($state);

    $conf_file->parse( '/etc/colordiffrc', "$ENV{HOME}/.colordiffrc" );

    foreach my $v (@boolean_options) {
        $state->{VARIABLE}{ @{$v}[0] }
            = $state->{VARIABLE}{ @{$v}[0] } eq 'yes' ? 1 : 0;
    }
    foreach my $v (@color_codes) {
        my $key = @{$v}[0];
        $state->{VARIABLE}{$key} = lc $state->{VARIABLE}{$key};

        if ( $state->{VARIABLE}{$key} =~ m/\d+/xms ) {
            if ( $state->{VARIABLE}{$key} < 8 ) {
                $state->{VARIABLE}{$key}
                    = "\033[0;3$state->{VARIABLE}{ $key }m";
            }
            elsif ( $state->{VARIABLE}{$key} < 15 ) {
                $state->{VARIABLE}{$key}
                    = "\033[0;9$state->{VARIABLE}{ $key }m";
            }
            else {
                $state->{VARIABLE}{$key}
                    = "\033[0;38;5;$state->{VARIABLE}{ $key }m";
            }
        }
    }
    return $state->{VARIABLE};
}

sub preprocess_input {
    my $input_ref = shift;

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

    # Not very elegant, but does the job
    # Unfortunately requires parsing the input stream multiple times
    foreach my $line ( @{$input_ref} ) {

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

    foreach ( @{$input_ref} ) {

        # Convert tabs to spaces
        while ( ( my $i = index $_, "\t" ) > -1 ) {
            substr $_, $i, 1,    # range to replace
                ( q{ } x ( 8 - ( $i % 8 ) ) );    # string to replace with
        }
        for my $i ( 0 .. ( length($_) - 3 ) ) {
            next if ( !defined $separator_col{$i} );
            next if ( $separator_col{$i} == 0 );
            my $subsub = substr $_, $i, 2;
            if (    ( $subsub ne q{  } )
                and ( $subsub ne ' |' )
                and ( $subsub ne ' >' )
                and ( $subsub ne ' <' ) )
            {
                $separator_col{$i} = 0;
            }
            if (   ( $subsub eq ' |' )
                or ( $subsub eq ' >' )
                or ( $subsub eq ' <' ) )
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

    return $diffy_sep_col;
}

sub parse_and_print {
    my $settings       = shift;
    my @input          = @{ (shift) };
    my $type           = shift;
    my $diffy_sep_col  = shift;
    my $inside_oldtext = 1;

    my $to_print = q{};

    foreach (@input) {
        if ( $type eq 'diff' ) {
            given ($_) {
                when (m/^</xms)  { $to_print = $settings->{oldtext}; }
                when (m/^>/xms)  { $to_print = $settings->{newtext}; }
                when (m/^\d/xms) { $to_print = $settings->{diffstuff}; }
                when (
                    m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                    )
                {
                    $to_print = $settings->{cvsstuff};
                }
                when (m/^Only[ ]in/xms) {
                    $to_print = $settings->{diffstuff};
                }
                default { $to_print = $settings->{plain}; }
            }
        }
        elsif ( $type eq 'diffc' ) {
            given ($_) {
                when (m/^-[ ]/xms)    { $to_print = $settings->{oldtext}; }
                when (m/^[+][ ]/xms)  { $to_print = $settings->{newtext}; }
                when (m/^[*]{4,}/xms) { $to_print = $settings->{diffstuff}; }
                when (m/^Only[ ]in/xms) {
                    $to_print = $settings->{diffstuff};
                }
                when (m/^[*]{3}[ ]\d+,\d+/xms) {
                    $to_print       = $settings->{diffstuff};
                    $inside_oldtext = 1;
                }
                when (m/^[*]{3}[ ]/xms) { $to_print = $settings->{oldtext}; }
                when (m/^---[ ]\d+,\d+/xms) {
                    $to_print       = $settings->{diffstuff};
                    $inside_oldtext = 0;
                }
                when (m/^---[ ]/xms) { $to_print = $settings->{newtext}; }
                when (m/^!/xms) {
                    $inside_oldtext == 1
                        ? $to_print
                        = $settings->{oldtext}
                        : $to_print = $settings->{newtext};
                }
                when (
                    m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                    )
                {
                    $to_print = $settings->{cvsstuff};
                }
                default { $to_print = $settings->{plain}; }
            }
        }
        elsif ( $type eq 'diffu' ) {
            given ($_) {
                when (m/^-/xms)   { $to_print = $settings->{oldtext}; }
                when (m/^[+]/xms) { $to_print = $settings->{newtext}; }
                when (m/^[@]/xms) { $to_print = $settings->{diffstuff}; }
                when (m/^Only[ ]in/xms) {
                    $to_print = $settings->{diffstuff};
                }
                when (
                    m/^(?:Index:[ ]|={4,}|RCS[ ]file:[ ]|retrieving[ ]|diff[ ])/xms
                    )
                {
                    $to_print = $settings->{cvsstuff};
                }
                default { $to_print = $settings->{plain}; }
            }
        }

        # Works with previously-identified column containing the diff-y
        # separator characters
        elsif ( $type eq 'diffy' ) {
            if ( length($_) > ( $diffy_sep_col + 2 ) ) {
                my $sepchars = substr $_, $diffy_sep_col, 2;
                if ( $sepchars eq ' <' ) {
                    $to_print = $settings->{oldtext};
                }
                elsif ( $sepchars eq ' |' ) {
                    $to_print = $settings->{diffstuff};
                }
                elsif ( $sepchars eq ' >' ) {
                    $to_print = $settings->{newtext};
                }
                else {
                    $to_print = $settings->{plain};
                }
            }
            elsif (m/^Only[ ]in/xms) {
                $to_print = $settings->{diffstuff};
            }
            else {
                $to_print = $settings->{plain};
            }
        }
        elsif ( $type eq 'wdiff' ) {
            $_ =~ s/(\[-[^]]*?-\])/$settings->{oldtext}$1$settings->{off}/gms;
            $_
                =~ s/([{][+][^]]*?[+][}])/$settings->{newtext}$1$settings->{off}/gms;
        }
        elsif ( $type eq 'debdiff' ) {
            $_ =~ s/(\[-[^]]*?-\])/$settings->{oldtext}$1$settings->{off}/gms;
            $_
                =~ s/([{][+][^]]*?[+][}])/$settings->{newtext}$1$settings->{off}/gms;
        }

        if ( $to_print =~ m/\d/xms ) {
            print $to_print;
        }
        else {
            print color($to_print);
        }
        print $_, color('reset');
    }
    return;
}

# ----------------------------------------------------------------------------

sub run {
    my $specified_difftype;

    GetOptions(
        'difftype=s' => \$specified_difftype,
        'help|?'     => sub { pod2usage( -verbose => 1 ) },
        'man'        => sub { pod2usage( -verbose => 2 ) },
        'usage'      => sub { pod2usage( -verbose => 0 ) },
        'version'    => sub { show_banner(1); exit 1; },
    );

    my $settings = parse_config_file();

   # If output is to a file, switch off colours, unless 'color_patches' is set
   # Relates to http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=378563
    if ( ( -f STDOUT ) and ( $settings->{color_patches} == 0 ) ) {
        $settings->{plain}     = q{};
        $settings->{oldtext}   = q{};
        $settings->{newtext}   = q{};
        $settings->{diffstuff} = q{};
        $settings->{cvsstuff}  = q{};
        $settings->{off}       = q{};
    }

    show_banner( $settings->{banner} );

    my @inputstream;

    my $exitcode = 0;
    if ( ( defined $ARGV[0] ) or ( -t STDIN ) ) {

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

    my $diff_type;
    if (    $specified_difftype
        and $specified_difftype
        =~ m/(diffu | diffc | diff | diffy | wdiff)/xms )
    {
        $diff_type = $specified_difftype;
    }
    else {
        $diff_type = determine_diff_type( \@inputstream );
    }

    my $diffy_sep_col = 0;

    if ( $diff_type eq 'diffy' ) {
        $diffy_sep_col = preprocess_input( \@inputstream );
    }

    parse_and_print( $settings, \@inputstream, $diff_type, $diffy_sep_col );

    exit $exitcode;
}

run() unless caller;

__END__

#-----------------------------------------------------------------------------

=pod

=head1 NAME

C<colordiff> - a wrapper/replacment for 'diff' producing colourful output

=head1 VERSION

=head1 USAGE

  cmd_line_example [ options ]
  cmd_line_example [ -c | --config ]
  cmd_line_example { --help | --man | --usage | --version }

=head1 REQUIRED ARGUMENTS

=head1 ARGUMENTS

=head1 OPTIONS

  These are the application options.

=over

=item C<--difftype>

  Specify the diff type to use.

=item C<--help>

  Displays a brief summary of options and exits.

=item C<--man>

  Displays the complete manual and exits.

=item C<--usage>

  Displays the basic application usage.

=item C<--version>

  Displays the version number and exits.

=back

=head1 DESCRIPTION

  A wrapper to colorize the output from a diff program.

=head1 DIAGNOSTICS

=head1 EXIT STATUS

  1 - Program exited normally. --help, --man, and --version return 1.
  2 - Program exited normally. --usage returns 2.

=head1 CONFIGURATION

=head1 DEPENDENCIES

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 HOMEPAGE

=head1 AUTHOR

Dave Ewart - davee@sungate.co.uk
Kirk Kimmel - https://github.com/kimmel

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2002-2011 Dave Ewart
Copyright (C) 2011 Kirk Kimmel

This program is free software; you can redistribute it and/or modify it under
the GPL v2+. The full text of this license can be found online at 
< http://opensource.org/licenses/GPL-2.0 >

=cut

