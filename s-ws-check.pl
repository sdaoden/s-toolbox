#!/usr/bin/env perl
require 5.008_001;
#@ Check indentation and whitespace in program source files.
#@ (Adjusted version of my git-pre-commit.sh pre-commit hook.)
my $SELF = 's-ws-check.pl';
my $VERSION = 'v0.0.1';
my $COPYRIGHT =<<__EOT__;
Copyright (c) 2012 Steffen "Daode" Nurpmeso <sdaoden\@users.sf.net>
This software is provided under the terms of the ISC license.
__EOT__
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

##  --  >8  --  8<  --  ##

use diagnostics -verbose;
use strict;
use warnings;

use Getopt::Long;

my ($NSPACEINDENT, $TABINDENT, $MIXINDENT) = (0, 0, 0);
my $INTRO =<<__EOT__;
$SELF ($VERSION)
$COPYRIGHT
__EOT__

my ($STANDALONE, $INFD, $ESTAT, $FILE, $LNO) = (1);
my ($nspaceindent, $tabindent, $mixindent, $l);

sub main_fun {
   $NSPACEINDENT = 1 if defined $ENV{NSPACEINDENT};
   $TABINDENT = 1 if defined $ENV{TABINDENT};
   $MIXINDENT = 1 if defined $ENV{MIXINDENT};
   Getopt::Long::Configure('bundling');
   unless (GetOptions(
            'h|help|?'   => sub { help(0); },
            'nspace' => \$NSPACEINDENT,
            'tabs' => \$TABINDENT,
            'mix' => \$MIXINDENT)) {
      help(1);
   }
   $nspaceindent = $NSPACEINDENT;
   $mixindent = $MIXINDENT;
   $tabindent = $MIXINDENT ? 1 : $TABINDENT;

   my ($good, $bad) = (0, 0);
   while (@ARGV) {
      $FILE = shift @ARGV;
      open($INFD, '<', $FILE) || die "Cannot open $FILE: $^E";
      $ESTAT = 0;
      $LNO = 0;
      while (defined rdline()) {
         ++$LNO;
         check_line();
      }
      ++$good unless $ESTAT;
      ++$bad if $ESTAT;
      close $INFD;
   }
   print "============\nOk : $good\nBad: $bad\n";
   $ESTAT = 1 if $bad;

   exit $ESTAT;
}

sub help {
   print STDERR <<__EOT__;
${INTRO}Synopsis
   s-ws-check.pl -h|--help|-?
   s-ws-check.pl [--tabindent] [--mixindent] FILE [:FILE:]

Options
   -h|--help|-?   Print this help
   --nspace       Do not allow space indentation.  Automatically set if the
                  environment variable NSPACEINDENT is found.
   --tabs         Do allow tabulator indent.  Automatically set if
                  the environment variable TABINDENT is found.
   --mix          Check for mixed space/tabulator indent (space-before-tabs,
                  implies --tabs).  Automatically set if the environment
                  variable MIXINDENT is found.
__EOT__
   exit $_[0];
}

sub check_diff {
   # XXX May not be able to swallow all possible diff output yet
   for (;;) { exit $ESTAT unless rdline(); last if $l =~ /^diff/; }
   for (;;) { head(); exit $ESTAT unless defined hunk(); }
}

sub rdline {
   $l = <$INFD>;
   chomp $l if $l;
   $l;
}

sub head {
   # Skip anything, including options and entire rename and delete diffs,
   # until we see the ---/+++ line pair
   for (;;) {
      last if $l =~ /^---/;
      return $l unless rdline();
   }

   return $l unless rdline();
   die "$FILE: head, 1.: cannot parse diff!" unless $l =~ /^\+\+\+ /;
   unless ($STANDALONE) {
      $FILE = substr $l, 4;
      $FILE = substr $FILE, 2 if $FILE =~ /^b\//;
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

      check_line();
   }
}

sub check_line {
   if (index($l, "\x{00A0}") != -1) {
      $ESTAT = 1;
      print "$FILE:$LNO: non-breaking space (NBSP, U+00A0).\n";
   }
   if ($l =~ /\s+$/) {
      $ESTAT = 1;
      print "$FILE:$LNO: trailing whitespace.\n";
   }

   my $h = $1 if $l =~ /^(\s+)/;
   return unless defined $h;
   $h =~ s/(\x{0020}+)$//;
   $h = defined $1 ? $1 : "" unless length $h;

   if ($nspaceindent && $h =~ /\x{0020}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: spaces in indent.\n";
   }
   if (! $tabindent && $h =~ /\x{0009}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: tabulator in indent.\n";
   }
   if (! $mixindent && $h =~ /\x{0009}/ && $h =~ /\x{0020}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: space(s) before tabulator(s) in indent.\n";
   }
}

{package main; main_fun();}

# vim:set fenc=utf-8 syntax=perl ts=8 sts=3 sw=3 et tw=79:
