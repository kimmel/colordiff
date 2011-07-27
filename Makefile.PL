use ExtUtils::MakeMaker;

my $script_name = 'colordiff';

WriteMakefile(
    'NAME'      => $script_name,
    'VERSION'   => '2.0.0',
    'PREREQ_PM' => {
        "Carp"                      => 0,
        "English"                   => 0,
        "Getopt::Long"              => 0,
        "IPC::Open2"                => 0,
        "Module::Load::Conditional" => 0,
        "Pod::Usage"                => 0,
        "Term::ANSIColor"           => 0,
    },
    'MIN_PERL_VERSION' => 5.008_000,
);
