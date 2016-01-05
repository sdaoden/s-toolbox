#!/usr/bin/env perl
require 5.008_001;
#@ Check indentation and whitespace in program source files.
#@ Somewhat in sync with git-pre-commit.sh.
my $SELF = 's-ws-check.pl';
my $VERSION = 'v0.0.4';
my $COPYRIGHT =<<__EOT__;
Copyright (c) 2012 - 2016 Steffen (Daode) Nurpmeso <steffen\@sdaoden.eu>
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

my ($NSPACEINDENT, $TABINDENT, $MIXINDENT, $MKFILEDIG) = (0, 0, 0, 0);
my $INTRO =<<__EOT__;
$SELF ($VERSION)
$COPYRIGHT
__EOT__

my ($STANDALONE, $INFD, $ESTAT, $FILE, $MKFILE, $LNO) = (1);
my ($nspaceindent, $tabindent, $mixindent, $l);

sub main_fun {
   $ESTAT = 0;
   $NSPACEINDENT = 1 if defined $ENV{NSPACEINDENT};
   $TABINDENT = 1 if defined $ENV{TABINDENT};
   $MIXINDENT = 1 if defined $ENV{MIXINDENT};
   $MKFILEDIG = 1 if defined $ENV{MKFILEDIG};
   Getopt::Long::Configure('bundling');
   unless (GetOptions(
            'h|help|?'   => sub { help(0); },
            'nspace' => \$NSPACEINDENT,
            'tabs' => \$TABINDENT,
            'mix' => \$MIXINDENT,
            'mkfiledig' => \$MKFILEDIG)) {
      help(1);
   }
   help(1) unless @ARGV;
   $mixindent = $MIXINDENT;
   $tabindent = $MIXINDENT ? 1 : $TABINDENT;
   $nspaceindent = $MIXINDENT ? 0 : $NSPACEINDENT;

   my ($good, $bad) = (0, 0);
   while (@ARGV) {
      $FILE = shift @ARGV;
      $MKFILE = ($FILE =~ /^[Mm]akefile$/ || $FILE =~ /\.mk$/);
      open($INFD, '<', $FILE) || die "Cannot open $FILE: $^E";
      $ESTAT = 0;
      $LNO = 0;
      while (defined rdline()) {
         ++$LNO;
         check_line()
      }
      ++$good unless $ESTAT;
      ++$bad if $ESTAT;
      close $INFD;
   }
   print "============\nOk : $good\nBad: $bad\n";
   $ESTAT = 1 if $bad;

   exit $ESTAT
}

sub help {
   print STDERR <<__EOT__;
${INTRO}Synopsis
   s-ws-check.pl -h|--help|-?
   s-ws-check.pl [--nspace] [--tabs] [--mix] [--mkfiledig] FILE [:FILE:]

Options
   -h|--help|-?   Print this help
   --nspace       Do not allow space indentation.  Automatically set if the
                  environment variable NSPACEINDENT is found.
   --tabs         Do allow tabulator indent.  Automatically set if
                  the environment variable TABINDENT is found.
   --mix          Check for mixed space/tabulator indent (space-before-tabs,
                  implies --tabs).  Automatically set if the environment
                  variable MIXINDENT is found.  Overrides NSPACEINDENT.
   --mkfiledig    Enable special treatment for [Mm]akefile and *.mk files.
__EOT__
   exit $_[0]
}

sub rdline {
   $l = <$INFD>;
   chomp $l if $l;
   $l
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

   if ((($MKFILEDIG && $MKFILE) || $nspaceindent) && $h =~ /\x{0020}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: spaces in indent.\n"
   }
   if ((!$tabindent && (!$MKFILEDIG || !$MKFILE)) && $h =~ /\x{0009}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: tabulator in indent.\n"
   }
   if ((($MKFILEDIG && $MKFILE) || $mixindent) &&
         $h =~ /^\x{0020}+/ && $h =~ /\x{0009}/) {
      $ESTAT = 1;
      print "$FILE:$LNO: space(s) before tabulator(s) in indent.\n"
   }
}

{package main; main_fun();}

# vim:set fenc=utf-8:s-it-mode
