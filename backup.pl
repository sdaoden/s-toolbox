#!/usr/bin/perl
#@ -backup: if $TSTAMP file does not exist or is invalid, only that
#@ file is updated (to enable future incremental backups) and script exits.
#@ (Otherwise) --full may be specified to force a non-incremental backup.
#
# Created: 2010-01-04

my $HOME = $ENV{'HOME'};
my $TSTAMP = "$HOME/.traffic/.backup.dat";
my $EMAIL = defined($ENV{'EMAIL'}) ? $ENV{'EMAIL'} : 'postmaster@localhost';
my $FS_TIME_ANDOFF = 3; # Filesystem precision adjust (must be mask) ...

# (All _absolute_ directories)
my $OUTPUT = "$HOME/misc";
my @INPUT = (	"$HOME/misc/cvsroot",
		"$HOME/misc/devel.cvsroot",
		"$HOME/Pictures"
);
# Pathnames (i.e., files or directories)
my @EXCLUDES = ('.DS_Store', '.localized', '.Trash',
		'iChat Icons',
		'.', '..' # DON'T drop!
);

use warnings;
use strict;
use File::Temp;

# Messages also go into this finally mail(1)ed file
my ($mffh,$mffn) = File::Temp::tempfile(UNLINK => 1);

&input_check();

my $ctime = time();
$ctime &= ~$FS_TIME_ANDOFF;
my $cdate = &format_epoch($ctime);
&msg(0, "Current timestamp: $ctime ($cdate)");

my ($ltime, $ldate) = (916053071, '1999-01-11T11:11:11 GMT');
&tstamp_get();

my ($full, $verbose) = (0, 0);
&command_line_parse();

my @filelist;
&filelist_create();

&archive_create();

&do_exit(0);

sub msg {
	my $args = \@_;
	my $lvl = shift @$args;
	foreach my $a (@$args) {
		my $m = ("\t" x $lvl) . $a . "\n";
		print STDOUT $m;
		print $mffh $m;
	}
}

sub err {
	my $args = \@_;
	my $lvl = shift @$args;
	foreach my $a (@$args) {
		my $m = '!' . ("\t" x $lvl) . $a . "\n";
		print STDERR $m;
		print $mffh $m;
	}
}

sub do_exit {
	my $estat = $_[0];
	if ($estat == 0) {
		&msg(0, 'mail(1)ing report and exit success');
	} else {
		&err(0, 'mail(1)ing report and exit FAILURE');
	}
	$| = 1;
	system("mail -s 'Backup report' $EMAIL < $mffn >/dev/null 2>&1");
	$| = 0;
	exit $estat;
}

sub input_check {
	&msg(0, 'Checking input directories:');
	for (my $i = 0; $i < @INPUT;) {
		my $dir = $INPUT[$i++];
		if (! -d $dir) {
			splice(@INPUT, --$i, 1);
			&err(1, "- <$dir>: DROP!",
				'   Not a (n accessible) directory!');
		} else {
			&msg(1, "- <$dir>: added");
		}
	}
	if (@INPUT == 0) {
		&err(0, 'BAILING OUT: no (accessible) directories found');
		&do_exit(1);
	}
}

sub format_epoch {
	my @e = gmtime($_[0]);
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d GMT',
			($e[5] + 1900), ($e[4] + 1), $e[3],
			$e[2], $e[1], $e[0]);
}

sub tstamp_get {
	&msg(0, "Reading old timestamp from <$TSTAMP>:");
	unless (&_tstamp_read()) {
		&err(1, '- Timestamp file does not exist or is invalid.',
			'  Creating it - call once again to perform backup');
		&_tstamp_write();
		&do_exit(1);
	}
	unless (&_tstamp_write()) {
		&err(1, '- Failed to write timestamp file.',
			'  Please ensure writeability and re-call script');
		&do_exit(1);
	}
	$ltime &= ~$FS_TIME_ANDOFF;
	if ($ltime >= $ctime) {
		&err(1, '- Timestamp unacceptable (too young)');
		&do_exit(1);
	}
	$ldate = &format_epoch($ltime);
	&msg(1, "- Got $ltime ($ldate)");
}

sub _tstamp_read {
	return 0 unless (-f $TSTAMP);
	unless (open(TSTAMP, "<$TSTAMP")) {
		&err(1, "- Open failed: $^E");
		return 0;
	}
	my $l = <TSTAMP>;
	close(TSTAMP);
	chomp $l;
	$ltime = int($l);
	return 1;
}

sub _tstamp_write {
	unless (open(TSTAMP, ">$TSTAMP")) {
		&err(1, "- Failed to open for writing: $^E");
		return 0;
	}
	print TSTAMP "$ctime\n(That's $cdate.)\n";
	close(TSTAMP);
	return 1;
}

sub command_line_parse {
	&msg(0, "Parsing command line");
	while (@ARGV > 0) {
		my $a = shift @ARGV;
		if ($a eq '--full') {
			&msg(1, '- Enabled full backup (ignoring timestamp)');
			$full = 1;
			$ltime = 0;
		} elsif ($a eq '--verbose') {
			&msg(1, '- Enabled verbose mode');
			$verbose = 1;
		} else {
			&err(1, "- Ignoring unknown option <$a>");
		}
	}
}

sub filelist_create {
	&msg(0, "Creating backup filelist");
	foreach (@INPUT) { &_parse_dir($_); }
	if (@filelist == 0) {
		&msg(0, 'No files to backup, bailing out');
		&do_exit(0);
	}
	&msg(0, '... scheduled ' .@filelist. ' files for backup');
}

sub _parse_dir {
	my $fdp = $_[0];
	unless (opendir(DIR, $fdp)) {
		&err(1, "- opendir($fdp) failed: $^E");
		return;
	}
	&msg(1, "- In <$fdp>") if ($verbose);
	my @dents = readdir(DIR);
	closedir(DIR);

	my @subdirs;
OUTER:	foreach my $f (@dents) {
		foreach my $i (@EXCLUDES) { next OUTER if ($f eq $i); }
		my $fpf = "$fdp/$f";
		if (-d $fpf) {
			push(@subdirs, $fpf);
		} elsif (-f _) {
			if (! -r _) {
				&err(2, "- <$fpf> not readable");
				next OUTER;
			}
			my $mtime = (stat(_))[9] & ~$FS_TIME_ANDOFF;
			next OUTER unless ($full || $mtime >= $ltime);
			push(@filelist, $fpf);
			&msg(2, "+ Added <$f>") if ($verbose);
		}
	}
	foreach my $sd (@subdirs) { &_parse_dir($sd); }
}

sub archive_create {
	select $mffh; $| = 1;
	select STDOUT; $| = 1;
	if ($full) {
		my $ar = $cdate;
		$ar =~ s/:/_/g;
		$ar =~ s/^(.*?)[[:space:]]+[[:alpha:]]+[[:space:]]*$/$1/;
		$ar = "$OUTPUT/backup.${ar}.tbz";
		&msg(0, "Creating archive <$ar>");
		my ($lffh,$lffn) = File::Temp::tempfile(UNLINK => 1);
		foreach my $p (@filelist) { print $lffh $p, "\n"; }
		select $lffh; $| = 1;
		$ar = system("tar cjLf $ar -T $lffn > /dev/null 2>> $mffn");
		if (($ar >> 8) != 0) {
			&err(1, "tar(1) execution had errors");
			&do_exit(1);
		}
	} else {
		my $ar = "$OUTPUT/backup.incremental.tar";
		&msg(0, "Creating/Updating archive <${ar}>");
		unless (open(XARGS, '| xargs -0 '
				. "tar rLf $ar > /dev/null 2>> $mffn")) {
			&err(1, "Failed creating pipe: $^E");
			&do_exit(1);
		}
		foreach my $p (@filelist) { print XARGS $p, "\x00"; }
		close(XARGS);
	}
	select STDOUT; $| = 0;
	select $mffn; $| = 0;
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=8 sts=8 sw=8 tw=79:
