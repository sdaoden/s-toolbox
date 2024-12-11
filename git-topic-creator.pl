#!/usr/bin/env perl
require 5.008_001;
#@ Create topic branches from a single line of history with "tagged" commit
#@ messages, removing those tags along the way (in the topic branches).
#@ See --help for more.
my $SELF = 'git-topic-creator.pl';
my $VERSION = 'v0.2.1-dirty';
my $COPYRIGHT =<<__EOT__;
Copyright (c) 2012 - 2022 Steffen Nurpmeso <steffen\@sdaoden.eu>.
This software is provided under the terms of the ISC license.
__EOT__
# SPDX-License-Identifier: ISC
#
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

my $GIT = 'git'; # -g/--git
my $TOPICDIR = 'topic'; # Level under which all topic branches are created

##  --  >8  --  8<  --  ##

#use diagnostics -verbose;
use strict;
use warnings;

use Getopt::Long;

my $TOPICPATH = 'refs/heads/' . $TOPICDIR;
# I.e., '[BRANCH] normal message'
my $BRANCHRE = '[-_.[:alnum:]]+';
my $TAGRE = ('^[[:space:]]*\[[[:space:]]*(' . $BRANCHRE . ')[[:space:]]*\][[:space:]]*' .  '(.+)$');
# Reset unless --verbose
my $REDIR = '> /dev/null 2>&1';

$ENV{GIT_EDITOR} = ("perl".
	" -e 'open(F, \"<\", \$ARGV[0]) || die \$!;'" .
	" -e '\@lines = <F>;'" .
	" -e 'close F;'".
	" -e '\$lines[0] =~ s/" . $TAGRE . "/\$2/;'".
	" -e 'open(F, \">\", \$ARGV[0]) || die \$!;'".
	" -e 'print F \@lines;'".
	" -e 'close F;'");

my ($DEBUG, $VERBOSE) = (0, 0);
my $INTRO =<<_EOT;
$SELF ($VERSION)
$COPYRIGHT
_EOT

my ($SEEN_ANON, $ONTO, $REV_SPEC, $NODELETE, $REBASE, $TOPIC_DELETE);
my ($REV_NOT_REVERSED, @REFS, @TOPICS);

sub main_fun{ # {{{
	command_line();

	check_git();

	if($TOPIC_DELETE){
		read_topics();
		delete_topics(1)
	}else{
		expand_rev_spec();
		read_check_commits();
		explode_topics();
		delete_topics(0) unless $NODELETE
	}

	exit 0
} # }}}

sub command_line{ # {{{
	my $emsg = undef;
	Getopt::Long::Configure('bundling');
	unless(GetOptions('git=s' => \$GIT, 'nodelete' => \$NODELETE, 'rebase' => \$REBASE,
			'delete-topics' => \$TOPIC_DELETE, 'h|help|?' => sub {goto jdocu},
			'd|debug' => \$DEBUG, 'v|verbose' => \$VERBOSE)){
		$emsg = 'Invocation failure';
		goto jdocu
	}

	++$VERBOSE if $DEBUG;
	$REDIR = '' if $VERBOSE != 0;

	if($TOPIC_DELETE){
		if($NODELETE || scalar @ARGV){
			$emsg = '--delete-topics is mutual exclusive with other options';
			goto jdocu
		}
		return
	}

	if(scalar @ARGV != 2){
		$emsg = 'ONTO and/or REV-SPEC are missing';
		goto jdocu
	}
	$ONTO = shift @ARGV;
	$REV_SPEC = join ' ', @ARGV;

	return;
jdocu:
	print STDERR "!PANIC $emsg\n\n" if defined $emsg;
	print STDERR <<__EOT__;
${INTRO}  $SELF [:-v|--verbose:] [--git=PATH] [--rebase] \
      [--nodelete] ONTO REV-SPEC
  $SELF [:-v|--verbose:] [--git=PATH] --delete-topics

ONTO specifies the target commit, usually a branch name, onto which all the
REV-SPECs will be placed upon.  REV-SPECs are expanded via 'git rev-parse'.
If --nodelete is given then the topic branches remain, but otherwise they're
only temporary.  If --rebase is given then each topic branch is rebased onto
ONTO before it is merged in; this mode is automatically activated if unnamed
topic branches exist ([-]), since commits from those will be cherry-picked
onto instead of merged into ONTO and so the others must follow.

The second usage case deletes all heads under $TOPICPATH, which can be
used to get rid of the topic branches created by a failed run.
You may want to use --verbose to see git(1) failures, then.

It's a simple script for a simple workflow like, given branches are ["master"],
"next" and "pu", and flow is pu->next[->master]:
  \$ git-topic-creator.pl next next..pu # (Or even pu...next)
  [left on the "next" branch here]
  \$ git checkout -B pu next # Start next development cycle

And how does this script know?
It requires the first line of each commit message to start off with a special
TOPIC-TAG: "[topic-0123_branch-name] Mandatory normal commit message".
The special tag "[-]" is an unnamed topic that is cherry-picked not merged.
__EOT__
    exit defined $emsg ? 1 : 0
} # }}}

sub verb1{
	return unless $VERBOSE > 0;
	print STDOUT '-V  ', shift, "\n";
	while(@_ != 0) {print STDOUT '-V  ++  ', shift, "\n"};
	return 1
}
sub warns{
	print STDERR '*W  ', shift, "\n";
	while (@_ != 0) { print STDERR '*W	++  ', shift, "\n" };
	return 1
}
sub panic{
	my $dbg_exit = shift;
	print STDERR '!PANIC ', shift, "\n";
	while(@_ != 0) {print STDERR '!PANIC ++  ', shift, "\n"};
	print STDERR '!PANIC .. You may need to run "git cherry-pick --abort"', "\n",
		'!PANIC .. followed by "git reset --hard"', "\n",
		'!PANIC .. followed by "git-topic-creator.pl --delete-topics"', "\n";
	exit 1 unless $DEBUG && !$dbg_exit;
	return 1
}

sub check_git{
	my $i = `$GIT rev-parse --is-inside-work-tree 2>/dev/null`;
	panic(1, "Cannot execute '$GIT rev-parse --is-inside-work-tree'") unless defined $i;
	panic(1, "$SELF must be run from within a git(1) working directory") unless $i =~ /true/;

	# It seems rev-parse output has been order-reversed somewhen.  Assume it was version 1.8
	$i = `$GIT --version`;
	$i =~ s/^\w+\s+\w+//;
	if($i =~ /(\d+)\.(\d+)/){
		my ($m, $s) = (int($1), int($2));
		$REV_NOT_REVERSED = ($m > 1 || $s >= 8) ? 1 : 0
	}else{
		$REV_NOT_REVERSED = 1
	}

	$i = `$GIT status --porcelain`;
	panic(1, "Cannot execute '$GIT status --porcelain'") unless defined $i;
	chomp $i;
	panic(1, 'Working directory not clean, consider \'reset --hard\' first') if length $i
}

sub expand_rev_spec{ # {{{
	my ($git);
	$git = `$GIT rev-parse --verify --symbolic $ONTO`;
	panic(1, "Rev-spec '$ONTO' seems to be invalid: $!") if $? != 0;
	chomp $git;
	panic('ONTO must be a single commit') if 1 < (() = split /\s+/, $git);
	$ONTO = $git;

	$git = `$GIT rev-parse $REV_SPEC`;
	panic(1, "Rev-spec '$REV_SPEC' seems to be invalid: $!") if $? != 0;
	chomp $git;
	@REFS = split /\s+/, $git;

	$git = 0;
	foreach(@REFS){
		my $i = $_ =~ /^\^/;
		$git += $i
	}
	warns('REV-SPEC excludes multiple commits.',
			'Because this script is simple, this is most likely an error.',
			'Do not	expect anything to work properly but linear histories.')
		if $git > 1;

	$REV_SPEC = join ' ', @REFS;
	verb1("REV_SPEC expanded: $REV_SPEC")
} # }}}

sub read_check_commits{
	panic(1, "Cannot execute '$GIT rev-list' on '$REV_SPEC': $!")
		unless open(GIT, "$GIT rev-list --reverse --oneline " .join(' ', @REFS). " |");
	@REFS = ();
	while(<GIT>){
		chomp;
		push @REFS, [split /\s+/, $_, 2]
	}
	close GIT;

	my $errs = 0;
	foreach my $c (@REFS){
		if($c->[1] =~ /$TAGRE/o){
			push @$c, $1
		}else{
			++$errs;
			warns("Commit $c->[0] does not have a (valid) TOPIC-TAG line")
		}
	}
	panic(1, 'Some commits are not classifieable') if $errs
}

sub explode_topics{ # {{{
	our ($i, $shas, $onto, $anon);

	# Commits are in correct order for an array, but in wrong for cherry-pick, so prepare all we need
	sub __push{
		$i = 'anonymous-' . ++$SEEN_ANON if ($anon = $i eq '-');
		push @TOPICS, [$i, $shas, $anon]
	}

	$i = '';
	foreach(@REFS){
		if($_->[2] ne $i){
			__push() if length $i;
			$i = $_->[2];
			$shas = []
		}
		if($REV_NOT_REVERSED){
			push @$shas, $_->[0]
		}else{
			unshift @$shas, $_->[0]
		}
	}
	__push();

	# Create topic branches and cherry-pick
	$onto = ' ' . $ONTO;
	$anon = 0;
	foreach(@TOPICS){
		$i = $_;
		verb1("Creating <$i->[0]> and cherry-picking onto it");
		panic(1, "Cannot create $TOPICDIR/$i->[0]")
			unless system("$GIT checkout -b $TOPICDIR/$i->[0]$onto $REDIR") == 0;
		panic(1, "Cannot cherry pick in $i->[0]") unless
			system("$GIT cherry-pick --edit @{$i->[1]} $REDIR") == 0;
		$onto = ''
	}

	# we and delete_topics() need only the names, so to avoid calling
	# read_topics() simply adjust @TOPICS (not calling read_topics()..)
	my @isff;
	foreach(@TOPICS){
		push @isff, $_->[2] ? $_->[1] : undef;
		$_ = $_->[0]
	}

	# Checkout $ONTO again, and merge all the topics
	verb1("Re-checking-out <$ONTO> and merging topic branches");
	panic(1, "Cannot re-checkout $ONTO") unless system("$GIT checkout -f $ONTO $REDIR") == 0;

	foreach(@TOPICS){
		my ($br, $cpc) = ($_, shift @isff);

		if(defined $cpc){
			panic(1, "Cannot ff-merge $br into $ONTO")
				unless system("$GIT cherry-pick --edit @{$cpc} $REDIR") == 0;
			next
		}

		if($REBASE || $SEEN_ANON){
			panic(1, "Cannot rebase $br onto $ONTO")
				unless system("$GIT rebase $ONTO $TOPICDIR/$br $REDIR") == 0;
			panic(1, "Cannot re-checkout $ONTO") unless system("$GIT checkout -f $ONTO $REDIR") == 0;
		}
		panic(1, "Cannot merge $br into $ONTO")
			unless system("$GIT merge -n --no-ff --commit --log=1000 $TOPICDIR/$br $REDIR") == 0;
	}
} # }}}

sub read_topics{
	my ($git);
	$git = `$GIT show-ref --heads`;
	panic(1, "Cannot '$GIT show-ref --heads': $!") if $? != 0;
	@REFS = split /\s+/, $git;

	$git = 0;
	foreach(@REFS){
		next unless $_ =~ /$TOPICPATH\/($BRANCHRE)/o;
		push @TOPICS, $1
	}
	panic(1, 'There are no topic branches') unless scalar @TOPICS
}

sub delete_topics{
	foreach(@TOPICS){
		verb1("Deleting topic-branch $_");
		panic(1, "Cannot delete topic-branch $TOPICPATH/$_")
			unless system("$GIT update-ref -d $TOPICPATH/$_ $REDIR") == 0;
	}
}

{package main; main_fun()}

# s-itt-mode
