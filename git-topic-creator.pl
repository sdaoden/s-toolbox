#!/usr/bin/perl
require 5.008;
#@ Create topic branches from a single line of history with "tagged" commit
#@ messages, removing those tags along the way (in the topic branches).
#@ See --help for more.
my $SELF = 'git-topic-creator.pl';
my $VERSION = 'v0.1.0';
my $COPYRIGHT =<<_EOT;
Copyright (c) 2012 Steffen Daode Nurpmeso <sdaoden\@users.sourceforge.net>
All rights reserved.
This software is published under the terms of the "New BSD license".
_EOT
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of the author nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

my $GIT = 'git';        # -g/--git
my $TOPICDIR = 'topic'; # Level under which all topic branches are created

##

use diagnostics -verbose;
use strict;
use warnings;

use Getopt::Long;

my $TOPICPATH = 'refs/heads/' . $TOPICDIR;
# I.e., '[BRANCH] normal message'
my $BRANCHRE = '[-_[:alnum:]]+';
my $TAGRE = ('^[[:space:]]*\[[[:space:]]*(' .
             $BRANCHRE . ')[[:space:]]*\][[:space:]]*' .
             '(.+)$');
# Reset unless --verbose
my $REDIR = '> /dev/null';

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

my ($ONTO, $REV_SPEC, $NODELETE, $TOPIC_MERGE, $TOPIC_DELETE);
my (@REFS, @TOPICS);

jMAIN: {
    command_line();

    check_git();

    if ($TOPIC_DELETE) {
        read_topics();
        delete_topics();
    } else {
        expand_rev_spec();
        read_check_commits();
        explode_topics();
        delete_topics() unless $NODELETE;
    }

    exit 0;
}

sub command_line { # {{{
    my $emsg = undef;
    Getopt::Long::Configure('bundling');
    unless (GetOptions(
                'git=s'         => \$GIT,
                'nodelete'      => \$NODELETE,
                'delete-topics' => \$TOPIC_DELETE,

                'h|help|?'      => sub { goto jdocu; },
                'd|debug'       => \$DEBUG,
                'v|verbose'     => \$VERBOSE)) {
        $emsg = 'Invocation failure';
        goto jdocu;
    }

    ++$VERBOSE if $DEBUG;
    $REDIR = '' if $VERBOSE != 0;

    if ($TOPIC_DELETE) {
        if ($NODELETE || scalar @ARGV) {
            $emsg = '--delete-topics is mutual exclusive with other options';
            goto jdocu;
        }
        return;
    }

    if (scalar @ARGV != 2) {
        $emsg = 'ONTO and/or REV-SPEC are missing';
        goto jdocu;
    }
    $ONTO = shift @ARGV;
    $REV_SPEC = join ' ', @ARGV;

    return;
jdocu:
    print STDERR "!PANIC $emsg\n\n" if defined $emsg;
    print STDERR <<_EOT;
${INTRO}Synopsis:
  $SELF [:-v|--verbose:] [--git=PATH] [--nodelete] ONTO REV-SPEC
  $SELF [:-v|--verbose:] [--git=PATH] --delete-topics

ONTO specifies the target commit, usually a branch name, onto which all the
REV-SPECs will be cherry-picked upon.  REV-SPECs are expanded via
'git rev-parse'.  If --nodelete is given then the topic branches remain, but
otherwise they're only temporary.

The second usage case deletes all heads under $TOPICPATH, which can be
used to get rid of the topic branches created by a failed run, or if --nodelete
has been given.

It's a simple script for a simple workflow like, given branches are ["master"],
"next" and "pu", and flow is pu->next[->master]:
  \$ git-topic-creator.pl next next..pu # (Or even pu...next)
  [left on the "next" branch here]
  \$ git branch -D pu
  \$ git checkout -b pu next            # Start next development cycle

And how does this script know?
It requires the first line of each commit message to start off with a special
TOPIC-TAG: "[topic-0123_branch-name] Mandatory normal commit message".
_EOT
    exit defined $emsg ? 1 : 0;
} # }}}

sub verb1 {
    return unless $VERBOSE > 0;
    print STDOUT '-V  ', shift, "\n";
    while (@_ != 0) { print STDOUT '-V  ++  ', shift, "\n" };
    return 1;
}
sub warns {
    print STDERR '*W  ', shift, "\n";
    while (@_ != 0) { print STDERR '*W  ++  ', shift, "\n" };
    return 1;
}
sub panic {
    my $dbg_exit = shift;
    print STDERR '!PANIC ', shift, "\n";
    while (@_ != 0) { print STDERR '!PANIC ++  ', shift, "\n" };
    exit 1 unless $DEBUG && !$dbg_exit;
    return 1;
}

sub check_git {
    my ($git);
    $git = `$GIT rev-parse --is-inside-work-tree 2>/dev/null`;
    panic(1, "Can't execute '$GIT rev-parse --is-inside-work-tree'")
        unless defined $git;
    panic(1, "$SELF must be run from within a git(1) working directory")
        unless $git =~ /true/;

    $git = `$GIT status --porcelain`;
    panic(1, "Can't execute '$GIT status --porcelain'")
        unless defined $git;
    chomp $git;
    panic(1, 'Working directory not clean, consider \'reset --hard\' first')
        if length $git;
}

sub expand_rev_spec { # {{{
    my ($git);
    $git = `$GIT rev-parse --verify --symbolic $ONTO`;
    panic(1, "Rev-spec '$ONTO' seems to be invalid: $!") if $? != 0;
    chomp $git;
    panic('ONTO must be a single commit') if 1 < (() = split /\s+/, $git);
    $ONTO = $git;

    $git = `$GIT rev-parse $REV_SPEC`;
    panic(1, "Rev-spec '$REV_SPEC' seems to be invalid: $!")
        if $? != 0;
    chomp $git;
    @REFS = split /\s+/, $git;

    $git = 0;
    foreach (@REFS) {
        my $i = $_ =~ /^\^/;
        $git += $i;
    }
    warns('REV-SPEC excludes multiple commits.',
          'Because this script is simple, this is most likely an error.',
          'Don\'t expect anything to work properly but linear histories.')
        if $git > 1;

    $REV_SPEC = join ' ', @REFS;
    verb1("REV_SPEC expanded: $REV_SPEC");
} # }}}

sub read_check_commits {
    open GIT, "$GIT rev-list --reverse --oneline " . join(' ', @REFS) . " |" ||
        panic(1, "Can't execute '$GIT rev-list' on '$REV_SPEC': $!");
    @REFS = ();
    while (<GIT>) {
        chomp;
        push @REFS, [split /\s+/, $_, 2];
    }
    close GIT;

    my $errs = 0;
    foreach my $c (@REFS) {
        if ($c->[1] =~ /$TAGRE/o) {
            push @$c, $1;
        } else {
            ++$errs;
            warns("Commit $c->[0] does not have a (valid) TOPIC-TAG line");
        }
    }
    panic(1, 'Some commits are not classifieable') if $errs;
}

sub explode_topics { # {{{
    my ($i, $shas, $onto) = ('');

    # Commits are in correct order for an array, but in wrong order for
    # cherry-pick, so prepare all the data we need
    foreach (@REFS) {
        if ($_->[2] ne $i) {
            push @TOPICS, [$i, $shas] if length $i;
            $i = $_->[2];
            $shas = [];
        }
        unshift @$shas, $_->[0];
    }
    push @TOPICS, [$i, $shas];

    # Create topic branches and cherry-pick
    $onto = ' ' . $ONTO;
    foreach (@TOPICS) {
        $i = $_;
        verb1("Creating <$i->[0]> and cherry-picking onto it");

        system("$GIT checkout -b $TOPICDIR/$i->[0]$onto $REDIR") == 0 ||
            panic(1, "Can't create $TOPICDIR/$i->[0]; run --delete-topics");
        system("$GIT cherry-pick --edit @{$i->[1]} $REDIR") == 0 ||
            panic(1, "Can't cherry pick in $i->[0]; run --delete-topics");

        $onto = '';
    }

    # we and delete_topics() need only the names, so to avoid calling
    # read_topics() simply adjust @TOPICS (not calling read_topics()..)
    $_ = $_->[0] foreach (@TOPICS);

    # Checkout $ONTO again, and merge all the topics
    verb1("Re-checking-out <$ONTO> and merging topic branches");
    system("$GIT checkout -f $ONTO $REDIR") == 0 ||
        panic(1, "Can't re-checkout $ONTO; run --delete-topics");

    foreach (@TOPICS) {
        system("$GIT merge --no-ff --commit --stat --log=1000 --verbose " .
               "$TOPICDIR/$_ $REDIR") == 0 ||
            panic(1, "Can't merge $_ into $ONTO; run --delete-topics");
    }
} # }}}

sub read_topics {
    my ($git);
    $git = `$GIT show-ref --heads`;
    panic(1, "Can't '$GIT show-ref --heads': $!")
        if $? != 0;
    @REFS = split /\s+/, $git;

    $git = 0;
    foreach (@REFS) {
        next unless $_ =~ /$TOPICPATH\/($BRANCHRE)/o;
        push @TOPICS, $1;
    }
    panic(1, 'There are no topic branches') unless scalar @TOPICS;
}

sub delete_topics {
    foreach (@TOPICS) {
        verb1("Deleting topic-branch $_");
        system("$GIT update-ref -d $TOPICPATH/$_ $REDIR") == 0 ||
            panic(1, "Can't delete topic-branch $TOPICPATH/$_");
    }
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
