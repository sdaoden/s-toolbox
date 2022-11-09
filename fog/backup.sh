#!/bin/sh -
#@ Simple updater, places backup and metadata files in $(REPO_)?OUTPUT_DIR.
#@ default: (tar -rpf) backup.tar files changed since (timestamp of) last run
#@ -r/--reset: do not take care about timestamps, do create xy.dateTtime.tar.XY
#@ -c/--complete: other input (@COMPLETE_INPUT), always xy.dateTtime.tar.XY
#@ -t/--timestamp: don't backup, but set the timestamp to the current time
#@ -b/--basename: only with -r/-c: not xy.dateTtime.tar.XY but backup.tar.XY
#@ With either of -r and -c $ADDONS, if existent, is removed.
#@ 2015-10-09: add -b/--basename option, add $COMPRESSOR variable, start
#@       via shell and $PERL5OPT clear to avoid multibyte problems
#@ 2015-09-02: no longer following symbolic links
#@ 2015-12-25: excluding symbolic links from archives; change $SYMLINK_INCLUDE
#@       in the script header to change this.
#@ 2016-08-27: s-it-mode;  FIX faulty xarg/tar -c invocations (Ralph Corderoy)
#@ 2016-10-19: Renamed from backup.pl "now" that we start via sh(1).
#@ 2016-10-19: Removed support for Mercurial: not tested in years.
#@ ..2017-06-12: Various little fixes still due to the xarg/tar stuff.
#@ 2017-06-13,14: Add $HOOK mechanism.
#@ 2018-10-12: Fix $HOOK mechanism for filenames with spaces as shown by
#@       POSIX, assuming no newlines are in a name:
#@          sed −e 's/"/"\\""/g' −e 's/.*/"&"/'
#@ 2018-11-12: add -p option to tar.
#@ 2018-11-13: change builtin path set.
#@ 2020-09-03, 2021-02-23: change builtin path set.
#@ 2021-03-03: silence $COMPRESSOR
#
# 2010 - 2022 Steffen Nurpmeso <steffen@sdaoden.eu>.
# Public Domain.

# Now start perl(1) without PERL5OPT set to avoid multibyte sequence errors
PERL5OPT= PERL5LIB= exec perl -x "${0}" "${@}"
exit
# Thanks to perl(5) and it's -x / #! perl / __END__ mechanism!
# Why can env(1) not be used for such easy things in #!?
#!perl

## Note: all _absolute_ directories and _not_ globs ##

# Home directory of user
my $HOME = $ENV{'HOME'};
# EMail address to send result to
my $EMAIL = defined($ENV{'EMAIL'}) ? $ENV{'EMAIL'} : 'postmaster@localhost';

# Where to store backup(s) and metadata
my $OUTPUT_DIR = '/var/tmp/' . (getpwuid($<))[0] . '/backups';

# We are also able to create backup bundles for git(1).
# They are stored in the directory given here; note that these are *not*
# automatically backed up, so place them in @XY_INPUT so that they end up in
# the actual backup archive ...
# Simply comment this variable out if you don't want this.
my $REPO_OUTPUT_DIR = "$HOME/sec.arena/backups";

# What actually happens is that $REPO_SRC_DIR is walked.
# For git(1) this is xy.git (plus xy.git/.git).  Here we simply use the git(1)
# "bundle" command with all possible flags to create the backup for everything
# that is not found in --remotes, which thus automatically includes stashes
# etc. (for the latter .git/logs/refs/stash is also backed up)
my $REPO_SRC_DIR = "$HOME/src";

# Our metadata storage file
my $TSTAMP = "$OUTPUT_DIR/.-backup.dat";

# Sometimes there is temporarily a directory which also should be backed up,
# but adjusting the backup script is too blown for this.
# If this file here exists, each line is treated as the specification of such
# a directory (again: absolute paths, please).
# $ADDONS will be removed in complete/reset mode, if it exists.
my $ADDONS = "$OUTPUT_DIR/.backup-addons.txt";

# A hook can be registered for archive creation, it will read the file to be
# backup-up from standard input.
# It takes two arguments: a boolean that indicates whether complete/reset
# mode was used, and the perl $^O string (again: absolute paths, please).
my $HOOK = "$OUTPUT_DIR/.backup-hook.sh";

# A fileglob (may really be a glob) and a list of directories to always exclude
my $EXGLOB = '._* *~ %* *.swp .encfs*.xml';
my @EXLIST = qw(.DS_Store .localized .Trash);

# List of input directories for normal mode/--complete mode, respectively.
# @NORMAL_INPUT is regulary extended by all directories found in $ADDONS, iff
my @NORMAL_INPUT = (
   "$HOME/arena",
   "$HOME/.secweb-mozilla",
   "$HOME/.sec.arena",
   "$HOME/.sic",
   "/x/doc"
);
my @COMPLETE_INPUT = (
   "$HOME/arena",
   "$HOME/.secweb-mozilla",
   "$HOME/.sec.arena",
   "$HOME/.sic"
);

# Symbolic links will be skipped actively if this is true.
# Otherwise they will be added to the backup as symbolic links!
my $SYMLINK_INCLUDE = 0;

# Compressor for --complete and --reset.  It must compress its filename
# argument to FILENAME${COMPRESSOR_EXT}.  If it does not remove the original
# file, we will do
my $COMPRESSOR = 'zstd -19 -T0 -q';
my $COMPRESSOR_EXT = '.zst';

###  --  >8  --  8<  --  ###

#use diagnostics -verbose;
use warnings;
#use strict;
use sigtrap qw(die normal-signals);
use File::Temp;
use Getopt::Long;
use IO::Handle;

my ($COMPLETE, $RESET, $TIMESTAMP, $BASENAME, $VERBOSE) = (0, 0, 0, 0, 0);
my $FS_TIME_ANDOFF = 3; # Filesystem precision adjust (must be mask) ...
my $INPUT; # References to above syms

# Messages also go into this finally mail(1)ed file
my ($MFFH,$MFFN) = File::Temp::tempfile(UNLINK => 1);

jMAIN:{
   msg(0, "Parsing command line");
   Getopt::Long::Configure('bundling');
   GetOptions('c|complete' => \$COMPLETE, 'r|reset' => \$RESET,
         't|timestamp' => \$TIMESTAMP, 'b|basename' => \$BASENAME,
         'v|verbose' => \$VERBOSE);
   if($COMPLETE){
      msg(1, 'Using "complete" backup configuration');
      $INPUT = \@COMPLETE_INPUT
   }else{
      $INPUT = \@NORMAL_INPUT
   }
   $RESET = 1 if $TIMESTAMP;
   msg(1, 'Ignoring old timestamps due to "--reset"') if $RESET;
   msg(1, 'Only updating the timestamp due to "--timestamp"') if $TIMESTAMP;
   err(1, '-b/--basename only meaningful with "--complete" or "--reset"')
      if $BASENAME && !($COMPLETE || $RESET);

   Timestamp::query();
   unless($TIMESTAMP){
      Addons::manage($COMPLETE || $RESET);

      GitBundles::create();

      Filelist::create();
      unless(Filelist::is_any()){
         Timestamp::save();
         do_exit(0)
      }

      if(Hook::exists()){
         Hook::call()
      }else{
         Archive::create()
      }
   }
   Timestamp::save();

   exit(0) if $TIMESTAMP;
   do_exit(0)
}

sub msg{
   my $args = \@_;
   my $lvl = shift @$args;
   foreach my $a (@$args){
      my $m = '- ' . ('  ' x $lvl) . $a . "\n";
      print STDOUT $m;
      print $MFFH $m
   }
   $MFFH->flush()
}

sub err{
   my $args = \@_;
   my $lvl = shift @$args;
   foreach my $a (@$args){
      my $m = '! ' . ('  ' x $lvl) . $a . "\n";
      print STDERR $m;
      print $MFFH $m
   }
   $MFFH->flush()
}

sub do_exit{
   my $estat = $_[0];
   if($estat == 0){ msg(0, 'mail(1)ing report and exit success') }
   else{ err(0, 'mail(1)ing report and exit FAILURE') }
   $| = 1;
   system("mail -s 'Backup report (" . Filelist::count() . # XXX use sendmail
         " file(s))' $EMAIL < $MFFN >/dev/null 2>&1");
   $| = 0;
   exit $estat
}

{package Timestamp;
   $CURRENT = 0;
   $CURRENT_DATE = '';
   $LAST = 916053068;
   $LAST_DATE = '1999-01-11T11:11:08 GMT';

   sub query{
      $CURRENT = time;
      $CURRENT &= ~$FS_TIME_ANDOFF;
      $CURRENT_DATE = _format_epoch($CURRENT);
      ::msg(0, "Current timestamp: $CURRENT ($CURRENT_DATE)");
      _read() unless $RESET
   }

   sub save{
      ::msg(0, "Writing current timestamp to <$TSTAMP>");
      unless(open TSTAMP, '>', $TSTAMP){
         ::err(1, "Failed to open for writing: $^E",
               'Ensure writeability and re-run!');
         ::do_exit(1)
      }
      print TSTAMP "$CURRENT\n(That's $CURRENT_DATE)\n";
      close TSTAMP
   }

   sub _read{
      ::msg(0, "Reading old timestamp from <$TSTAMP>");
      unless(open TSTAMP, '<', $TSTAMP){
         ::err(1, 'Timestamp file cannot be read - setting --reset option');
         $RESET = 1
      }else{
         my $l = <TSTAMP>;
         close TSTAMP;
         chomp $l;
         if($l !~ /^\d+$/){
            ::err(1, 'Timestamp corrupted - setting --reset option');
            $RESET = 1;
            return
         }
         $l = int $l;

         $l &= ~$FS_TIME_ANDOFF;
         if($l >= $CURRENT){
            ::err(1, 'Timestamp corrupted - setting --reset option');
            $RESET = 1
         }else{
            $LAST = $l;
            $LAST_DATE = _format_epoch($LAST);
            ::msg(1, "Got $LAST ($LAST_DATE)")
         }
      }
   }

   sub _format_epoch{
      my @e = gmtime $_[0];
      return sprintf('%04d-%02d-%02dT%02d:%02d:%02d GMT',
            ($e[5] + 1900), ($e[4] + 1), $e[3], $e[2], $e[1], $e[0])
   }
}

{package Addons;
   sub manage{
      unless(-f $ADDONS){
         ::msg(0, "Addons: \"$ADDONS\" does not exist, skip");
         return
      }
      (shift != 0) ? _drop() : _load()
   }

   sub _load{
      ::msg(0, "Addons: reading \"$ADDONS\"");
      unless(open AO, '<', $ADDONS){
         ::err(1, 'Addons file cannot be read');
         ::do_exit(1)
      }
      foreach my $l (<AO>){
         chomp $l;
         unless(-d $l){
            ::err(1, "Addon \"$l\" is not accessible");
            ::do_exit(1)
         }
         ::msg(1, "Adding-on \"$l\"");
         unshift @$INPUT, $l
      }
      close AO
   }

   sub _drop{
      ::msg(0, "Addons: removing \"$ADDONS\"");
      unless(unlink $ADDONS){
         ::err(1, "Addons file cannot be deleted: $^E");
         ::do_exit(1)
      }
   }
}

{package GitBundles;
   my @Git_Dirs;

   sub create{
      return unless defined $REPO_OUTPUT_DIR;
      _create_list();
      _create_backups() if @Git_Dirs
   }

   sub _create_list{
      ::msg(0, 'Collecting git(1) repo information');
      unless(-d $REPO_OUTPUT_DIR){
         ::err(0, 'FAILURE: no Git backup-bundle dir found');
         ::do_exit(1)
      }

      unless(opendir DIR, $REPO_SRC_DIR){
         ::err(1, "opendir($REPO_SRC_DIR) failed: $^E");
         ::do_exit(1)
      }
      my @dents = readdir DIR;
      closedir DIR;

      foreach my $dent (@dents){
         next if $dent eq '.' || $dent eq '..';
         my $abs = $REPO_SRC_DIR . '/' . $dent;
         next unless -d $abs;
         next unless $abs =~ /\.git$/;
         next unless -d "$abs/.git";
         push @Git_Dirs, $dent;
         ::msg(1, "added <$dent>")
      }
   }

   sub _create_backups{
      ::msg(0, "Creating Git bundle backups");
      foreach my $e (@Git_Dirs){
         ::msg(1, "Processing $e");
         my $src = $REPO_SRC_DIR . '/' . $e;
         unless(chdir $src){
            ::err(2, "GitBundles: cannot chdir($src): $^E");
            ::do_exit(1)
         }

         _do_bundle($e)
      }
   }

   sub _do_bundle{
      my $repo = shift;
      my ($target, $flag, $pop_stash, $omodt);
      ::msg(2, 'Checking for new bundle') if $VERBOSE;

      $target = "$REPO_OUTPUT_DIR/$repo";
      $target = $1 if $target =~ /(.+)\..+$/;
      $target .= '.bundle';
      $flag = '--all --not --remotes --tags';
      ::msg(3, "... target: $target") if $VERBOSE;

      $pop_stash = system('git update-index -q --refresh; ' .
            'git diff-index --quiet --cached HEAD ' .
               '--ignore-submodules -- && ' .
            'git diff-files --quiet --ignore-submodules && ' .
            'test -z "$(git ls-files -o -z)"');
      $pop_stash >>= 8;
      if($pop_stash != 0){
         ::msg(3, 'Locale modifications exist, stashing them away')
            if $VERBOSE;
         $pop_stash = system('git stash --all >/dev/null 2>&1');
         $pop_stash >>= 8;
         if($pop_stash++ != 0){
            ::err(3, '"git(1) stash --all" away local modifications ' .
               "failed in $repo");
            ::do_exit(1)
         }
      }

      $flag = system("git bundle create $target $flag >> $MFFN 2>&1");
      seek $MFFH, 0, 2;
      # Does not create an empty bundle: 128
      if($flag >> 8 == 128){
         ::msg(3, 'No updates available, dropping outdated bundles, if any')
            if $VERBOSE;
         ::err(3, "Failed to unlink outdated bundle $target: $^E")
            if (-f $target && unlink($target) != 1);
         ::err(3, "Failed to unlink outdated $target.stashlog: $^E")
            if (-f "$target.stashlog" && unlink("$target.stashlog") != 1)
      }elsif($flag >> 8 != 0){
         ::err(3, "git(1) bundle failed for $repo ($target)");
         ::do_exit(1)
      }
      # Unfortunately stashes in bundles are rather useless without the
      # additional log file (AFAIK)!
      elsif(-f ".git/logs/refs/stash"){
         ::msg(3, ".git/logs/refs/stash exists, creating $target.stashlog")
            if $VERBOSE;
         unless(open SI, '<', '.git/logs/refs/stash'){
            ::err(4, 'Failed to read .git/logs/refs/stash');
            ::do_exit(1)
         }
         unless(open SO, '>', "$target.stashlog"){
            ::err(4, "Failed to write $target.stashlog");
            ::do_exit(1)
         }
         print SO "# Place this in .git/logs/refs/stash\n" ||
            ::do_exit("Failed to write $target.stashlog");
         print SO $_ || ::do_exit("Failed to write $target.stashlog")
            foreach(<SI>);
         close SO;
         close SI
      }
      # And then, there may be a bundle but no (more) stash
      elsif(-f "$target.stashlog" && unlink("$target.stashlog") != 1){
         ::err(3, "Failed to unlink outdated $target.stashlog: $^E")
      }

      if($pop_stash != 0){
         ::msg(3, 'Locale modifications existed, popping the stash')
            if $VERBOSE;
         $pop_stash = system('git stash pop >/dev/null 2>&1');
         ::err(3, '"git(1) stash pop" the local modifications ' .
               "failed in $repo") if ($pop_stash >> 8 != 0)
      }
   }
}

{package Filelist;
   my @List;

   sub create{
      ::msg(0, 'Checking input directories');
      for(my $i = 0; $i < @$INPUT;){
         my $dir = $$INPUT[$i++];
         if(! -d $dir){
            splice @$INPUT, --$i, 1;
            ::err(1,  "DROPPED <$dir>")
         }else{
            ::msg(1, "added <$dir>")
         }
      }
      if(@$INPUT == 0){
         ::err(0, 'FAILURE: no (accessible) directories found');
         ::do_exit(1)
      }

      ::msg(0, 'Creating backup filelist');
      _parse_dir($_) foreach @$INPUT;
      ::msg(0, '... scheduled ' .@List. ' files for backup')
   }

   sub is_any{ return @List > 0 }
   sub count{ return scalar @List }
   sub get_listref{ return \@List }

   sub _parse_dir{
      my ($abspath) = @_;
      # Need to chdir() due to glob(@EXGLOB) ...
      ::msg(1, ".. checking <$abspath>") if $VERBOSE;
      unless(chdir $abspath){
         ::err(1, "Cannot chdir($abspath): $^E");
         return
      }
      unless(opendir DIR, '.'){
         ::err(1, "opendir($abspath) failed: $^E");
         return
      }
      my @dents = readdir DIR;
      closedir DIR;
      my @exglob = glob $EXGLOB;

      my @subdirs;
jOUTER:
      foreach my $dentry (@dents){
         next if $dentry eq '.' || $dentry eq '..';
         foreach(@exglob){
            if($dentry eq $_){
               ::msg(2, "<$dentry> glob-excluded") if $VERBOSE;
               next jOUTER
            }
         }
         foreach(@EXLIST){
            if($dentry eq $_){
               ::msg(2, "<$dentry> list-excluded") if $VERBOSE;
               next jOUTER
            }
         }

         my $path = "$abspath/$dentry";
         if(-d $dentry){
            push(@subdirs, $path);
            ::msg(2, "<$dentry> dir-traversal enqueued") if $VERBOSE
         }elsif(-f _){
            if(!-r _){
               ::err(2, "<$path> not readable");
               next jOUTER
            }
            if(!$SYMLINK_INCLUDE){
               lstat $dentry;
               if(-l _){
                  ::msg(2, "excluded symbolic link <$dentry>")
                     if $VERBOSE;
                  next jOUTER
               }
            }

            my $mtime = (stat _)[9] & ~$FS_TIME_ANDOFF;
            if($RESET || $mtime >= $Timestamp::LAST){
               push @List, $path;
               if($VERBOSE){ ::msg(2, "added <$dentry>") }
               else{ ::msg(1, "a <$path>") }
            }elsif($VERBOSE){
               ::msg(2, "time-miss <$dentry>")
            }
         }
      }
      foreach(@subdirs){ _parse_dir($_) }
   }
}

{package Archive;
   sub create{
      my $backup = 'backup'; #$COMPLETE ? 'complete-backup' : 'backup';

      my ($ar, $far);
      if($RESET || $COMPLETE){
         if(!$BASENAME){
            $ar = $Timestamp::CURRENT_DATE;
            $ar =~ s/:/_/g;
            $ar =~ s/^(.*?)[[:space:]]+[[:alpha:]]+[[:space:]]*$/$1/;
            $ar = "$OUTPUT_DIR/monthly-$backup-$ar.tar"
         }else{
            $ar = "$OUTPUT_DIR/$backup.tar"
         }
         $far = $ar . $COMPRESSOR_EXT;
         ::msg(0, "Creating complete archive <$far>");
         if(-e $far){
            ::err(3, "Archive <$far> already exists");
            ::do_exit(1)
         }
         if(-e $ar && !unlink $ar){
            ::err(1, "Old archive <$ar> exists but cannot be deleted: $^E");
            ::do_exit(1)
         }
      }else{
         $ar = "$OUTPUT_DIR/$backup.tar";
         ::msg(0, "Creating/Updating archive <$ar>")
      }

      unless(open XARGS, "| xargs -0 tar -r -p -f $ar >>$MFFN 2>&1"){
         ::err(1, "Failed to create pipe: $^E");
         ::do_exit(1)
      }
      my $listref = Filelist::get_listref();
      foreach my $p (@$listref){ print XARGS $p, "\x00" }
      close XARGS;

      if($RESET || $COMPLETE){
         system("</dev/null $COMPRESSOR $ar >>$MFFN 2>&1");
         unless(! -f $ar || unlink $ar){
            ::err(1, "Temporary archive $ar cannot be deleted: $^E");
            ::do_exit(1)
         }
      }

      seek $MFFH, 0, 2
   }
}

{package Hook;
   sub exists{
      -x $HOOK
   }

   sub call{
      unless(open HOOK, "| $HOOK " . ($COMPLETE || $RESET) .
            " $^O >>$MFFN 2>&1"){
         ::err(1, "Failed to create hook pipe: $^E");
         ::do_exit(1)
      }else{
         my ($stop, $listref) = (0, Filelist::get_listref());
         local *hdl = sub{ $stop = 1 };
         local $SIG{PIPE} = \&hdl;
         foreach my $p (@$listref){
            last if $stop;
            $p =~ s/\"/\"\\\"\"/g;
            $p = '"' . $p . '"';
            print HOOK $p, "\n"
         }
      }
      close HOOK;

      seek $MFFH, 0, 2
   }
}

# vim:set ft=perl:s-it-mode
