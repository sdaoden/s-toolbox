#!/bin/sh -
#@ Check indentation and whitespace in program source files.
#@ Somewhat in sync with s-ws-check.pl.
# Public Domain.

# If $GIT_NO_PRECOMMIT is nonempty, simply exit success at once.
# This is to avoid problems in rebases when some commit contains files that
# have been accepted already, i.e., Makefiles need to have tabulator indents
# due to the standard..
[ -n "$GIT_NO_PRECOMMIT" ] && exit 0

# Wether spaces are not allowed as indentation
[ -z "$NSPACEINDENT" ] && NSPACEINDENT=0 || NSPACEINDENT=1
# Wether tabulators in indention is checked
[ -z "$TABINDENT" ] && TABINDENT=0 || TABINDENT=1
# Wether tabulator/space mix in indention is checked (space before tab)
[ -z "$MIXINDENT" ] && MIXINDENT=0 || MIXINDENT=1

##  --  >8  --  8<  --  ##

#if git rev-parse --verify HEAD >/dev/null 2>&1
#then
    against=HEAD
#else
    # Initial commit: diff against an empty tree object
#   against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
#fi

# Oh no, unfortunately not: exec git diff-index --check --cached $against --
git diff --cached $against |
perl -CI \
   -e "\$nspaceindent = \"$NSPACEINDENT\";" \
   -e "\$tabindent= \"$TABINDENT\";" \
   -e "\$mixindent = \"$MIXINDENT\";" \
   -e '
   $nspaceindent = 0 if $mixindent;
   $tabindent = 1 if $mixindent;
   # This is rather in sync with s-ws-check.pl..
   my ($STANDALONE, $INFD, $ESTAT, $FILE, $LNO) = (0, *STDIN, 0);

   #sub check_diff {
      # XXX May not be able to swallow all possible diff output yet
      for (;;) { exit $ESTAT unless rdline(); last if $l =~ /^diff/ }
      for (;;) { head(); exit $ESTAT unless defined hunk() }
   #}

   sub rdline {
      $l = <$INFD>;
      chomp $l if $l;
      $l
   }

   sub head {
      # Skip anything, including options and entire rename and delete diffs,
      # until we see the ---/+++ line pair
      for (;;) {
         last if $l =~ /^---/;
         return $l unless rdline()
      }

      return $l unless rdline();
      die "$FILE: head, 1.: cannot parse diff!" unless $l =~ /^\+\+\+ /;
      unless ($STANDALONE) {
         $FILE = substr $l, 4;
         $FILE = substr $FILE, 2 if $FILE =~ /^b\//
      }
   }

   sub hunk() {
      return $l unless rdline();
      die "$FILE: hunk, 1.: cannot parse diff!" unless $l =~ /^@@ /;
   JHUNK:
      # regex shamelessly stolen from git(1), and modified
      $l =~ /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/;
      $LNO = $1 - 1;

      for (;;) {
         return $l unless rdline();
         return if $l =~ /^diff/;      #  Different file?
         goto JHUNK if $l =~ /^@@ /;   # Same file, different hunk?
         next if $l =~ /^-/;           # Ignore removals

         ++$LNO;
         next if $l =~ /^ /;
         $l = substr $l, 1;

         check_line()
      }
   }

   sub check_line {
      if (index($l, "\x{00A0}") != -1) {
         $ESTAT = 1;
         print "$FILE:$LNO: non-breaking space (NBSP, U+00A0).\n"
      }
      if ($l =~ /\s+$/) {
         $ESTAT = 1;
         print "$FILE:$LNO: trailing whitespace.\n"
      }

      my $h = $1 if $l =~ /^(\s+)/;
      return unless $h;

      if ($nspaceindent && $h =~ /\x{0020}/) {
         $ESTAT = 1;
         print "$FILE:$LNO: spaces in indent.\n"
      }
      if (! $tabindent && $h =~ /\x{0009}/) {
         $ESTAT = 1;
         print "$FILE:$LNO: tabulator in indent.\n"
      }
      if ($mixindent && $h =~ /^\x{0020}+/ && $h =~ /\x{0009}/) {
         $ESTAT = 1;
         print "$FILE:$LNO: space(s) before tabulator(s) in indent.\n"
      }
   }
'

# vim:set fenc=utf-8:s-it-mode
