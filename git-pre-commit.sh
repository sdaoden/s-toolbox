#!/bin/sh

#if git rev-parse --verify HEAD >/dev/null 2>&1
#then
    against=HEAD
#else
    # Initial commit: diff against an empty tree object
#   against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
#fi

# Oh no, unfortunately not: exec git diff-index --check --cached $against --
git diff  $against | perl -e '
    # XXX May not be able to swallow all possible diff output yet
    my ($estat, $l, $fname) = (0, undef, undef);

    for (;;) { last if stdin() =~ /^diff/o; }
    for (;;) { head(); hunk(); }

    sub stdin {
        $l = <STDIN>;
        exit($estat) unless $l;
        chomp($l);
        return $l;
    }

    sub head {
        # Skip anything, including options and entire rename and delete diffs,
        # until we see the ---/+++ line pair
        for (;;) {
            last if $l =~ /^---/o;
            stdin();
        }

        stdin();
        die "head, 1.: cannot parse diff!" unless $l =~ /^\+\+\+ /o;
        $fname = substr($l, 4);
        $fname = substr($fname, 2) if $fname =~ /^b\//o;
    }

    sub hunk() {
        stdin();
        die "hunk, 1.: cannot parse diff!" unless $l =~ /^@@ /o;
JHUNK:
        # regex shamelessly stolen from git(1), and modified
        $l =~ /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/;
        my $lno = $1 - 1;

        for (;;) {
            stdin();
            return if $l =~ /^diff/o;       # Different file?
            goto JHUNK if $l =~ /^@@ /o;    # Same file, different hunk?
            next if $l =~ /^-/o;            # Ignore removals

            ++$lno;
            next if $l =~ /^ /o;
            $l = substr($l, 1);

            if (index($l, "\xA0") != -1) {
                $estat = 1;
                print "$fname:$lno: non-breaking space (NBSP, U+A0).\n";
            }
            if ($l =~ /\s+$/o) {
                $estat = 1;
                print "$fname:$lno: trailing whitespace.\n";
            }
            if ($l =~ /^(\s+)/o && $1 =~ /\x09/o) {
                $estat = 1;
                print "$fname:$lno: tabulator in indent.\n";
            }
        }
    }
    '

# vim:set fenc=utf-8 ts=4 sts=4 sw=4 et tw=79:
