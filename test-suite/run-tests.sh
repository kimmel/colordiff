#!/bin/bash

# -----------------------------------------------------------------------------
# colordiff test suite: run this script and verify, by eye, that all 
#                       appropriate colour markup is present in the output
# -----------------------------------------------------------------------------
#
# Suggestion: run this script using './run-tests.sh | less -R' to provide 
# paged, coloured output through 'less'.
#
# Output for plain2.diffy requires >160 character wide terminal (it's two ~80
# character outputs side by side

echo 
echo
echo --------------------------------------------------------------------------
echo Simple diff:
echo --------------------------------------------------------------------------
echo
echo
cat plain.diff | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Unified diff:
echo --------------------------------------------------------------------------
echo
echo
cat plain.diffu | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Context diff:
echo --------------------------------------------------------------------------
echo
echo
cat plain.diffc | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Side-by-side diff:
echo --------------------------------------------------------------------------
echo
echo
cat plain.diffy | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Alternate side-by-side diff:
echo --------------------------------------------------------------------------
echo
echo
cat plain2.diffy | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Simple CVS diff
echo --------------------------------------------------------------------------
echo
echo
cat cvs.diff | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Unified CVS diff
echo --------------------------------------------------------------------------
echo
echo
cat cvs.diffu | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo Context CVS diff
echo --------------------------------------------------------------------------
echo
echo
cat cvs.diffc | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo SVN diff
echo --------------------------------------------------------------------------
echo
echo
cat svn.diff | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo p4 plain diff
echo --------------------------------------------------------------------------
echo
echo
cat p4.diff | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo p4 unified diff
echo --------------------------------------------------------------------------
echo
echo
cat p4.diffu | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo p4 context diff
echo --------------------------------------------------------------------------
echo
echo
cat p4.diffc | ../colordiff.pl
echo
echo
echo --------------------------------------------------------------------------
echo wdiff tests...
echo --------------------------------------------------------------------------
echo
echo
wdiff -n wdiff1.txt wdiff2.txt |../colordiff.pl
echo
echo
wdiff -n wdiff3.txt wdiff4.txt |../colordiff.pl
echo
echo
wdiff -n wdiff5.txt wdiff6.txt |../colordiff.pl
echo
echo
wdiff -n wdiff7.txt wdiff8.txt |../colordiff.pl
echo
echo
