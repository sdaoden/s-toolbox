#!/usr/bin/perl
# Created: 2010-02-25
# default: (tar -rf) backup.tar files changed since last invocation
# -r/--reset: do not take care about timestamps, do create xy.dateTtime.tbz
# -c/--complete: other config ($COMPLETE_), always xy.dateTtime.tbz

# Note: all _absolute_ directories and _not_ globs

my $EMAIL = defined($ENV{'EMAIL'}) ? $ENV{'EMAIL'} : 'postmaster@localhost';
my $HOME = $ENV{'HOME'};

# Mercurial work-clone-dir/repo-dir day-by-day bundles+shelve+patch backups
my $HG_SRC_DIR = "$HOME/src";
my $HG_REPO_DIR = "$HOME/arena/code.repos";
my $HG_BUNDLE_DIR = "$HOME/arena/data/backups";
# Git work-clone-dir/repo-dir day-by-day bundles backups
my $GIT_SRC_DIR = "$HOME/src";
my $GIT_BUNDLE_DIR = "$HOME/arena/data/backups";

my @NORMAL_INPUT = (
    "$HOME/arena/code.extern.repos",
    "$HOME/arena/code.extern.balls",
    "$HOME/arena/code.repos",
    "$HOME/arena/docs.2wheel",
    "$HOME/arena/docs.4wheel",
    "$HOME/arena/docs.coding",
    "$HOME/arena/docs.misc",
    "$HOME/arena/movies.snapshots",
    "$HOME/arena/pics.artwork",
    "$HOME/arena/pics.snapshots"
);
my @COMPLETE_INPUT = (
#   "$HOME/arena",
    "$HOME/arena/code.repos",
    "$HOME/arena/movies.snapshots",
    "$HOME/arena/pics.artwork",
    "$HOME/arena/pics.snapshots"
);

my $EXGLOB = '._* *~ *.swp';
my @EXLIST = qw(.DS_Store .localized .Trash);

my $NORMAL_OUTPUT = "$HOME/traffic";
my $COMPLETE_OUTPUT = "$HOME/traffic";

my $NORMAL_TSTAMP = "$HOME/traffic/.-backup.dat";
my $COMPLETE_TSTAMP = $NORMAL_TSTAMP; #"$HOME/traffic/.-backup-complete.dat";

###

use diagnostics -verbose;
use warnings;
#use strict;
use sigtrap qw(die normal-signals);
use File::Temp;
use Getopt::Long;
use IO::Handle;

my ($COMPLETE, $RESET, $VERBOSE) = (0, 0, 0);
my $FS_TIME_ANDOFF = 3; # Filesystem precision adjust (must be mask) ...
my ($INPUT, $TSTAMP, $OUTPUT); # References to above syms

# Messages also go into this finally mail(1)ed file
my ($MFFH,$MFFN) = File::Temp::tempfile(UNLINK => 1);

jMAIN: {
    msg(0, "Parsing command line");
    Getopt::Long::Configure('bundling');
    GetOptions('c|complete' => \$COMPLETE, 'r|reset' => \$RESET,
               'v|verbose' => \$VERBOSE);
    if ($COMPLETE) {
        msg(1, 'Using "complete" backup configuration');
        $INPUT = \@COMPLETE_INPUT;
        $TSTAMP = \$COMPLETE_TSTAMP;
        $OUTPUT = \$COMPLETE_OUTPUT;
    } else {
        $INPUT = \@NORMAL_INPUT;
        $TSTAMP = \$NORMAL_TSTAMP;
        $OUTPUT = \$NORMAL_OUTPUT;
    }
    msg(1, 'Ignoring old timestamps due to "--reset" option') if $RESET;

    #Timestamp::create();
    #HGBundles::create();
    GitBundles::create();

exit(0);
    Filelist::create();
    unless (Filelist::is_any()) {
        Timestamp::save();
        do_exit(0);
    }

    Archive::create();
    Timestamp::save();
    do_exit(0);
}

sub msg {
    my $args = \@_;
    my $lvl = shift @$args;
    foreach my $a (@$args) {
        my $m = '- ' . ('  ' x $lvl) . $a . "\n";
        print STDOUT $m;
        print $MFFH $m;
    }
    $MFFH->flush();
}

sub err {
    my $args = \@_;
    my $lvl = shift @$args;
    foreach my $a (@$args) {
        my $m = '! ' . ('  ' x $lvl) . $a . "\n";
        print STDERR $m;
        print $MFFH $m;
    }
    $MFFH->flush();
}

sub do_exit {
    my $estat = $_[0];
    if ($estat == 0) { msg(0, 'mail(1)ing report and exit success'); }
    else             { err(0, 'mail(1)ing report and exit FAILURE'); }
    $| = 1;
    system("mail -s 'Backup report (" . Filelist::count() .
           " file(s))' $EMAIL < $MFFN >/dev/null 2>&1");
    $| = 0;
    exit $estat;
}

{package Timestamp;
    $CURRENT = 0;
    $CURRENT_DATE = '';
    $LAST = 916053068;
    $LAST_DATE = '1999-01-11T11:11:08 GMT';

    sub create {
        $CURRENT = time();
        $CURRENT &= ~$FS_TIME_ANDOFF;
        $CURRENT_DATE = _format_epoch($CURRENT);
        ::msg(0, "Current timestamp: $CURRENT ($CURRENT_DATE)");
        _read() unless $RESET;
    }

    sub save {
        ::msg(0, "Writing current timestamp to <$$TSTAMP>");
        unless (open(TSTAMP, ">$$TSTAMP")) {
            ::err(1, "Failed to open for writing: $^E",
                     'Ensure writeability and re-run!');
            ::do_exit(1);
        }
        print TSTAMP "$CURRENT\n(That's $CURRENT_DATE)\n";
        close(TSTAMP);
    }

    sub _read {
        ::msg(0, "Reading old timestamp from <$$TSTAMP>");
        unless (open(TSTAMP, "<$$TSTAMP")) {
            ::err(1, 'Timestamp file cannot be read - setting --reset option');
            $RESET = 1;
        } else {
            my $l = <TSTAMP>;
            close(TSTAMP);
            chomp $l;
            $l = int($l);

            $l &= ~$FS_TIME_ANDOFF;
            if ($l >= $CURRENT) {
                ::err(1, 'Timestamp corrupted - setting --reset option');
                $RESET = 1;
            } else {
                $LAST = $l;
                $LAST_DATE = _format_epoch($LAST);
                ::msg(1, "Got $LAST ($LAST_DATE)");
            }
        }
    }

    sub _format_epoch {
        my @e = gmtime($_[0]);
        return sprintf('%04d-%02d-%02dT%02d:%02d:%02d GMT',
                ($e[5] + 1900), ($e[4] + 1), $e[3],
                $e[2], $e[1], $e[0]);
    }
}

{package HGBundles;
    my @HG_Dirs;

    sub create {
        _create_list();
        _create_backups();
    }

    sub _create_list {
        ::msg(0, 'Collecting repo information');
        unless (-d $HG_BUNDLE_DIR) {
            ::err(0, 'FAILURE: no HG backup-bundle/-shelve/-patch dir found');
            ::do_exit(1);
        }

        unless (opendir(DIR, $HG_SRC_DIR)) {
            ::err(1, "opendir($HG_SRC_DIR) failed: $^E");
            ::do_exit(1);
        }
        my @dents = readdir(DIR);
        closedir(DIR);

        foreach my $dent (@dents) {
            next if $dent eq '.' || $dent eq '..';
            my $abs = $HG_SRC_DIR . '/' . $dent;
            next unless -d $abs;
            next unless $abs =~ /\.hg$/;
            next unless -d "$abs/.hg";
            push(@HG_Dirs, $dent);
            ::msg(1, "added <$dent>");
        }
    }

    sub _create_backups {
        ::msg(0, "Creating HG bundle/shelve/patch backups");
        foreach my $e (@HG_Dirs) {
            ::msg(1, "Processing $e");
            my $src = $HG_SRC_DIR . '/' . $e;
            unless (chdir($src)) {
                ::err(2, "HGBundles: cannot chdir($src): $^E");
                ::do_exit(1);
            }

            _do_bundle($e);
            _do_shelves_or_patches($e, 'shelves');
            _do_shelves_or_patches($e, 'patches');
        }
    }

    sub _do_bundle {
        my $e = shift;
        my ($target, $dest, $flag, $omodt);
        ::msg(2, 'Checking for new bundle') if $VERBOSE;

        $target = "$HG_BUNDLE_DIR/$e";
        $target = $1 if $target =~ /(.+)\..+$/;
        $target .= '.bundle';
        $dest = "$HG_REPO_DIR/$e";
        $flag = $VERBOSE ? '-v' : '';
        ::msg(3, "... target: $target") if $VERBOSE;
        if (-d $dest) {
            ::msg(3, "... dest-repo: $dest") if $VERBOSE;
        } else {
            ::msg(3, "... using --all: no dest-repo: $dest") if $VERBOSE;
            $dest = '';
            $flag .= ' --all';
        }

        # hg bundle (also) returns 1 if no changes have been found, so use
        # modification times to decide wether an error occurred.
        # If not we can also throw away the old bundle..
        $omodt = -1;
        {   my @x = stat($target);
            if (@x) { $omodt = $x[9]; }
        }
        $flag = system("hg bundle $flag $target $dest >> $MFFN 2>&1");
        if (($flag >> 8) != 0) {
            my ($nmodt, @x) = (-1, stat($target));
            if (@x) { $nmodt = $x[9]; }

            if ($omodt == $nmodt) {
                ::msg(3, 'No updates available, dropping outdated bundles')
                    if $VERBOSE;
                ::err(3, "Failed to unlink outdated bundle $target: $^E")
                    unless ($nmodt == -1 || unlink($target) == 1);
            } else {
                ::err(3, "hg(1) bundle failed for $target");
                ::do_exit(1);
            }
        }
    }

    sub _do_shelves_or_patches {
        my ($e, $what) = @_;
        my ($target, $dest, $flag);
        ::msg(2, "Checking for $what") if $VERBOSE;

        $target = "$HG_BUNDLE_DIR/$e";
        $target = $1 if $target =~ /(.+)\..+$/;
        $target .= "-$what.tbz";
        ::msg(3, "... target: $target") if $VERBOSE;
        $dest = ".hg/$what";
        unless (-d $dest) {
            ::msg(3, "No $dest directory, skipping") if $VERBOSE;
            return;
        }

        # Only if none-empty
        unless (opendir(DIR, $dest)) {
            ::err(3, "opendir($dest) failed: $^E");
            return;
        }
        $flag = 0;
        {   my @dents = readdir(DIR);
            closedir(DIR);
            foreach my $dent (@dents) {
                next if $dent eq '.' || $dent eq '..';
                $flag = 1;
                last;
            }
        }

        if ($flag == 0) {
            ::msg(3, "No $what, dropping directory and outdated backups")
                if $VERBOSE;
            ::err(3, "Failed to unlink outdated $what backup: $^E")
                unless (! -f $target || unlink($target) == 1);
            ::err(3, "Failed to rmdir empty $dest: $^E")
                unless rmdir($dest) == 1;
        } else {
            ::msg(3, "Creating new $what backup") if $VERBOSE;
            $flag = system("tar cjLf $target $dest > /dev/null 2>> $MFFN");
            ::err(3, "tar(1) execution failed for $target")
                if ($flag >> 8) != 0;
        }
    }
}

{package GitBundles;
    my @Git_Dirs;

    sub create {
        _create_list();
        _create_backups();
    }

    sub _create_list {
        ::msg(0, 'Collecting repo information');
        unless (-d $GIT_BUNDLE_DIR) {
            ::err(0, 'FAILURE: no Git backup-bundle dir found');
            ::do_exit(1);
        }

        unless (opendir(DIR, $GIT_SRC_DIR)) {
            ::err(1, "opendir($GIT_SRC_DIR) failed: $^E");
            ::do_exit(1);
        }
        my @dents = readdir(DIR);
        closedir(DIR);

        foreach my $dent (@dents) {
            next if $dent eq '.' || $dent eq '..';
            my $abs = $GIT_SRC_DIR . '/' . $dent;
            next unless -d $abs;
            next unless $abs =~ /\.git$/;
            next unless -d "$abs/.git";
            push(@Git_Dirs, $dent);
            ::msg(1, "added <$dent>");
        }
    }

    sub _create_backups {
        ::msg(0, "Creating Git bundle backups");
        foreach my $e (@Git_Dirs) {
            ::msg(1, "Processing $e");
            my $src = $GIT_SRC_DIR . '/' . $e;
            unless (chdir($src)) {
                ::err(2, "GitBundles: cannot chdir($src): $^E");
                ::do_exit(1);
            }

            _do_bundle($e);
        }
    }

    sub _do_bundle {
        my $e = shift;
        my ($target, $flag, $omodt);
        ::msg(2, 'Checking for new bundle') if $VERBOSE;

        $target = "$GIT_BUNDLE_DIR/$e";
        $target = $1 if $target =~ /(.+)\..+$/;
        $target .= '.bundle';
        $flag = '--all --not --remotes';
        ::msg(3, "... target: $target") if $VERBOSE;

        $flag = system("git bundle create $target $flag >> $MFFN 2>&1");
        # Does not create an empty bundle: 128
        if (($flag >> 8) == 128) {
            ::msg(3, 'No updates available, dropping outdated bundles, if any')
                if $VERBOSE;
            ::err(3, "Failed to unlink outdated bundle $target: $^E")
                if (-f $target && unlink($target) != 1);
        } elsif (($flag >> 8) != 0) {
            ::err(3, "git(1) bundle failed for $target");
            ::do_exit(1);
        }
    }
}

{package Filelist;
    my @List;

    sub create {
        ::msg(0, 'Checking input directories');
        for (my $i = 0; $i < @$INPUT;) {
            my $dir = $$INPUT[$i++];
            if (! -d $dir) {
                splice(@$INPUT, --$i, 1);
                ::err(1,  "DROPPED <$dir>");
            } else {
                ::msg(1, "added <$dir>");
            }
        }
        if (@$INPUT == 0) {
            ::err(0, 'FAILURE: no (accessible) directories found');
            ::do_exit(1);
        }

        ::msg(0, 'Creating backup filelist');
        _parse_dir($_) foreach @$INPUT;
        ::msg(0, '... scheduled ' .@List. ' files for backup');
    }

    sub is_any { return @List > 0; }
    sub count { return scalar @List; }
    sub get_listref { return \@List; }

    sub _parse_dir {
        my ($abspath) = @_;
        # Need to chdir() due to glob(@EXGLOB) ...
        ::msg(1, ".. checking <$abspath>") if $VERBOSE;
        unless (chdir($abspath)) {
            ::err(1, "Cannot chdir($abspath): $^E");
            return;
        }
        unless (opendir(DIR, '.')) {
            ::err(1, "opendir($abspath) failed: $^E");
            return;
        }
        my @dents = readdir(DIR);
        closedir(DIR);
        my @exglob = glob($EXGLOB);

        my @subdirs;
jOUTER:     foreach my $dentry (@dents) {
            next if $dentry eq '.' || $dentry eq '..';
            foreach (@exglob) {
                if ($dentry eq $_) {
                    ::msg(2, "<$dentry> glob-excluded") if $VERBOSE;
                    next jOUTER;
                }
            }
            foreach (@EXLIST) {
                if ($dentry eq $_) {
                    ::msg(2, "<$dentry> list-excluded") if $VERBOSE;
                    next jOUTER;
                }
            }

            my $path = "$abspath/$dentry";
            if (-d $dentry) {
                push(@subdirs, $path);
                ::msg(2, "<$dentry> dir-traversal enqueued") if $VERBOSE;
            } elsif (-f _) {
                if (! -r _) {
                    ::err(2, "<$path> not readable");
                    next jOUTER;
                }
                my $mtime = (stat(_))[9] & ~$FS_TIME_ANDOFF;
                if ($RESET || $mtime >= $Timestamp::LAST) {
                    push(@List, $path);
                    if ($VERBOSE) { ::msg(2, "added <$dentry>"); }
                    else          { ::msg(1, "a <$path>"); }
                } elsif ($VERBOSE) {
                    ::msg(2, "time-miss <$dentry>");
                }
            }
        }
        foreach (@subdirs) { _parse_dir($_); }
    }
}

{package Archive;
    sub create {
        my $listref = Filelist::get_listref();
        my $backup = $COMPLETE ? 'complete-backup' : 'backup'; 

        if ($RESET || $COMPLETE) {
            my $ar = $Timestamp::CURRENT_DATE;
            $ar =~ s/:/_/g;
            $ar=~s/^(.*?)[[:space:]]+[[:alpha:]]+[[:space:]]*$/$1/;
            $ar = "$$OUTPUT/$backup.${ar}.tbz"; # ALGO below!
            ::msg(0, "Creating archive <$ar>");

            my ($lffh,$lffn) = File::Temp::tempfile(UNLINK => 1);
            foreach my $p (@$listref) { print $lffh $p, "\n"; }
            select $lffh; $| = 1;

            $ar = system("tar cjLf $ar -T $lffn > /dev/null 2>> $MFFN");
            if (($ar >> 8) != 0) {
                ::err(1, "tar(1) execution had errors");
                ::do_exit(1);
            }
        } else {
            my $ar = "$$OUTPUT/$backup.tar";
            ::msg(0, "Creating/Updating archive <$ar>");
            unless (open(XARGS, '| xargs -0 '
                  . "tar rLf $ar > /dev/null 2>> $MFFN")) {
                ::err(1, "Failed creating pipe: $^E");
                ::do_exit(1);
            }
            foreach my $p (@$listref) { print XARGS $p, "\x00"; }
            close(XARGS);
        }
    }
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
