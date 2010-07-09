#!/usr/bin/perl
require 5.008;
#@ S-Disc-Ripper - part of S-MusicBox; this one handles ripping of Audio-CD's.
#@ Requirements:
#@	- dd(1) (standart UNIX tool)
#@	- CDDB.pm (www.CPAN.org)
#@	- sox(1) (sox.sourceforge.net)
#@	- if MP3 is used: lame(1) (www.mp3dev.org)
#@	- if MP4/AAC is used: faac(1) (www.audiocoding.com)
#@	- if Ogg/Vorbis is used: oggenc(1) (www.xiph.org)
#@ TODO: Implement CDDB query ourselfs
#@ TODO: Recognize changes in [CDDB] section and upload the corrected entries
#@ TODO: BIG FAT TODO in database_stuff()!
#@ TODO: Rewrite: use Title OBJECT, drop SRC_FILES etc.; use Data::Dumper to
#@	store those objects, i.e. always perform CDDB query (then optional) on
#@	first invocation??? A rip is finished if all tracks have been ripped
#@	(individual may be deselected or dropped if rip fails) AND have been
#@	encoded AND database has been written - no earlier.
#@	ONLY THEN drop temporaries, state YET EXISTS etc.
#@	Later individual tracks may be re-ripped - auto-use database for this!
#@	I.e.: even title->rip(), title->remove() and PTF to real impl....
#
# Created: 2010-06-21
# $SFramework$
#
my $COPYRIGHTS = 'Copyright (c) 2010 Steffen Daode Nurpmeso.';
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer, without
#    modification, immediately at the beginning of the file.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# May be changed for different site-global default settings
my ($MP3HI,$MP3LO, $AACHI,$AACLO, $OGGHI,$OGGLO) = (0,0, 1,1, 1,0);
# (changing defaults via environment should still be possible though for these)
my $MUSICDB = (defined $ENV{S_MUSICBOX} ? $ENV{S_MUSICBOX}
		: "$ENV{HOME}/arena/music.db");
my $CDROM = defined $ENV{CDROM} ? $ENV{CDROM} : undef;
my $CDROMDEV = (defined $ENV{CDROMDEV} ? $ENV{CDROMDEV}
		: defined $CDROM ? $CDROM : undef);

# FORCE UTF-8 HERE so that never ever anything bad happens
$ENV{LANG} = $ENV{LC_ALL} = 'en_US.UTF-8';
use diagnostics -verbose;
use warnings;
use strict;

use CDDB;
use Encode;
use File::Path;
use Getopt::Long;

die "I need a valid and accessible TMPDIR (environment variable)"
	unless (exists $ENV{TMPDIR} && -d $ENV{TMPDIR});

my @Genres = (
	[ 123, 'A Cappella' ],	[ 34, 'Acid' ],		[ 74, 'Acid Jazz' ],
	[ 73, 'Acid Punk' ],	[ 99, 'Acoustic' ],	[ 20, 'Alternative' ],
	[ 40, 'Alt. Rock' ],	[ 26, 'Ambient' ],	[ 145, 'Anime' ],
	[ 90, 'Avantgarde' ],	[ 116, 'Ballad' ],	[ 41, 'Bass' ],
	[ 135, 'Beat' ],	[ 85, 'Bebob' ],	[ 96, 'Big Band' ],
	[ 138, 'Black Metal' ],	[ 89, 'Bluegrass' ],	[ 0, 'Blues' ],
	[ 107, 'Booty Bass' ],	[ 132, 'BritPop' ],	[ 65, 'Cabaret' ],
	[ 88, 'Celtic' ],	[ 104, 'Chamber Music' ], [ 102, 'Chanson' ],
	[ 97, 'Chorus' ],	[ 136, 'Christian Gangsta Rap' ],
	[ 61, 'Christian Rap' ], [ 141, 'Christian Rock' ],
	[ 32, 'Classical' ],	[ 1, 'Classic Rock' ],	[ 112, 'Club' ],
	[ 128, 'Club-House' ],	[ 57, 'Comedy' ],
	[ 140, 'Contemporary Christian' ],
	[ 2, 'Country' ],	[ 139, 'Crossover' ],	[ 58, 'Cult' ],
	[ 3, 'Dance' ],		[ 125, 'Dance Hall' ],	[ 50, 'Darkwave' ],
	[ 22, 'Death Metal' ],	[ 4, 'Disco' ],		[ 55, 'Dream' ],
	[ 127, 'Drum & Bass' ],	[ 122, 'Drum Solo' ],	[ 120, 'Duet' ],
	[ 98, 'Easy Listening' ], [ 52, 'Electronic' ],	[ 48, 'Ethnic' ],
	[ 54, 'Eurodance' ],	[ 124, 'Euro-House' ],	[ 25, 'Euro-Techno' ],
	[ 84, 'Fast-Fusion' ],	[ 80, 'Folk' ],		[ 115, 'Folklore' ],
	[ 81, 'Folk/Rock' ],	[ 119, 'Freestyle' ],	[ 5, 'Funk' ],
	[ 30, 'Fusion' ],	[ 36, 'Game' ],		[ 59, 'Gangsta Rap' ],
	[ 126, 'Goa' ],		[ 38, 'Gospel' ],	[ 49, 'Gothic' ],
	[ 91, 'Gothic Rock' ],	[ 6, 'Grunge' ],	[ 129, 'Hardcore' ],
	[ 79, 'Hard Rock' ],	[ 137, 'Heavy Metal' ],	[ 7, 'Hip-Hop' ],
	[ 35, 'House' ],	[ 100, 'Humour' ],	[ 131, 'Indie' ],
	[ 19, 'Industrial' ],	[ 33, 'Instrumental' ],
	[ 46, 'Instrumental Pop' ], [ 47, 'Instrumental Rock' ],
	[ 8, 'Jazz' ],		[ 29, 'Jazz+Funk' ],	[ 146, 'JPop' ],
	[ 63, 'Jungle' ],	[ 86, 'Latin' ],	[ 71, 'Lo-Fi' ],
	[ 45, 'Meditative' ],	[ 142, 'Merengue' ],	[ 9, 'Metal' ],
	[ 77, 'Musical' ],	[ 82, 'National Folk' ],
	[ 64, 'Native American' ],
	[ 133, 'Negerpunk' ],	[ 10, 'New Age' ],	[ 66, 'New Wave' ],
	[ 39, 'Noise' ],	[ 11, 'Oldies' ],	[ 103, 'Opera' ],
	[ 12, 'Other' ],	[ 75, 'Polka' ],	[ 134, 'Polsk Punk' ],
	[ 13, 'Pop' ],		[ 53, 'Pop-Folk' ],	[ 62, 'Pop/Funk' ],
	[ 109, 'Porn Groove' ],	[ 117, 'Power Ballad' ], [ 23, 'Pranks' ],
	[ 108, 'Primus' ],	[ 92, 'Progressive Rock' ],
	[ 67, 'Psychedelic' ],	[ 93, 'Psychedelic Rock' ],
	[ 43, 'Punk' ],		[ 121, 'Punk Rock' ],	[ 15, 'Rap' ],
	[ 68, 'Rave' ],		[ 14, 'R&B' ],		[ 16, 'Reggae' ],
	[ 76, 'Retro' ],	[ 87, 'Revival' ],
	[ 118, 'Rhythmic Soul' ], [ 17, 'Rock' ],	[ 78, 'Rock & Roll' ],
	[ 143, 'Salsa' ],	[ 114, 'Samba' ],	[ 110, 'Satire' ],
	[ 69, 'Showtunes' ],	[ 21, 'Ska' ],		[ 111, 'Slow Jam' ],
	[ 95, 'Slow Rock' ],	[ 105, 'Sonata' ],	[ 42, 'Soul' ],
	[ 37, 'Sound Clip' ],	[ 24, 'Soundtrack' ],
	[ 56, 'Southern Rock' ], [ 44, 'Space' ],	[ 101, 'Speech' ],
	[ 83, 'Swing' ],	[ 94, 'Symphonic Rock' ], [ 106, 'Symphony' ],
	[ 147, 'Synthpop' ],	[ 113, 'Tango' ],	[ 18, 'Techno' ],
	[ 51, 'Techno-Industrial' ], [ 130, 'Terror' ],
	[ 144, 'Thrash Metal' ], [ 60, 'Top 40' ],	[ 70, 'Trailer' ],
	[ 31, 'Trance' ],	[ 72, 'Tribal' ],	[ 27, 'Trip-Hop' ],
	[ 28, 'Vocal' ]
);

my ($RIP_ONLY, $ENC_ONLY, $VERBOSE) = (0, 0, 0);

my $INTRO = "s-disc-ripper.pl\n$COPYRIGHTS\nAll rights reserved.\n\n";
my ($CDID, @TRACK_OFFSETS, $TOTAL_SECONDS);
my (@SRC_FILES, $TARGET_DIR, $WORK_DIR,
	%TAG, $DBERROR, @DBCONTENT,
	$VOL_ADJUST, $AACTAG, $OGGTAG);

jMAIN: {
	command_line();

	$SIG{INT} = sub { print STDERR "\nInterrupted ... bye\n"; exit 1; };
	print $INTRO, "Press <CNTRL-C> at any time to interrupt\n\n";

	unless ($ENC_ONLY) {
		print "Assuming an Audio-CD is in the drive ...\n";
		{	no strict 'refs';
			die "Operating system <$^O> not supported"
				unless defined *{"::cdsuck_$^O"};
			&{"::cdsuck_${^O}"}();
		}
		create_dir_and_dat();
		user_tracks();
		database_stuff() unless $RIP_ONLY;
		rip_files();
	} else {
		print "Resuming rip for CD(DB)ID $CDID\n",
			"S-MusicBox DB directory: $MUSICDB\n";
		resume_file_list();
		database_stuff();
	}

	unless ($RIP_ONLY) {
		calculate_volume_adjust();
		encode_all_files();
	}

	# END{}: remove $WORK_DIR ok
	$ENC_ONLY = 2;
	exit(0);
}

END {	if (defined $WORK_DIR && -d $WORK_DIR) {
		if ($RIP_ONLY) {
			print '--rip-only mode: ',
				"use --encode-only=$CDID to resume rip ...\n";
		} elsif ($ENC_ONLY != 2) {
			print "Error occurred: NOT removing <$WORK_DIR>!\n";
		} elsif ($VERBOSE) {
			v("--verbose mode: NOT removing <$WORK_DIR>");
		} else {
			print "Removing temporary <$WORK_DIR>\n";
			File::Path::rmtree($WORK_DIR);
		}
	}
}

sub command_line {
	my $emsg = undef;
	Getopt::Long::Configure('bundling');
	unless (GetOptions(	'h|help|?'		=> sub { goto jdocu; },
				'g|genre-list'		=> sub {
					foreach my $tr (@Genres) {
						printf("%3d %s\n",
							$tr->[0], $tr->[1]);
					}
					exit(0);
				},
				'musicdb=s'		=> \$MUSICDB,
				'cdrom=s'		=> \$CDROM,
				'cdromdev=s'		=> \$CDROMDEV,
				'r|rip-only'		=> \$RIP_ONLY,
				'e|encode-only=s'	=> \$ENC_ONLY,
				'mp3hi=i'		=> \$MP3HI,
				'mp3lo=i'		=> \$MP3LO,
				'aachi=i'		=> \$AACHI,
				'aaclo=i'		=> \$AACLO,
				'ogghi=i'		=> \$OGGHI,
				'ogglo=i'		=> \$OGGLO,
				'v|verbose'		=> \$VERBOSE)) {
		$emsg = 'Invocation failure';
		goto jdocu;
	}

	unless (-d $MUSICDB && -w _) {
		$emsg = "S-MusicBox DB directory <$MUSICDB> unaccessible";
		goto jdocu;
	}
	if ($ENC_ONLY) {
		if ($RIP_ONLY) {
			$emsg = '--rip-only and --encode-only are mutual ' .
				'exclusive';
			goto jdocu;
		}
		if ($ENC_ONLY !~ /[[:alnum:]]+/) {
			$emsg = "$ENC_ONLY is not a valid CD(DB)ID";
			goto jdocu;
		}
		$CDID = $ENC_ONLY;
		$ENC_ONLY = 1;
	}
	return;

jdocu:	print STDERR "!PANIC $emsg\n\n" if defined $emsg;
	print STDERR <<_EOT;
${INTRO}S-Disc-Ripper is the CD-ripper of the S-MusicBox set of tools.
It will rip CD's, query CDDB servers and finally encode the raw data to MP3,
and/or AAC (MP4) and/or Ogg Vorbis.
Setting the EDITOR environment gives more comfort (currently <$ENV{EDITOR}>).

USAGE:
s-disc-ripper.pl -h|--help
s-disc-ripper.pl -g|--genre-list
s-disc-ripper.pl [-v|--verbose] [--musicdb=PATH]
                 [--cdrom=SPEC] [--cdromdev=SPEC]
                 [-r|--rip-only] [-e|--encode-only=CD(DB)ID]
                 [--mp3hi] [--mp3lo] [--aachi] [--aaclo] [--ogghi] [--ogglo]

 -h,--help        prints this help text
 -g,--genre-list  dumps out a list of all GENREs
 -v,--verbose     mostly debug, prints more status messages and does not
                  delete the temporary raw files and their directory
 --musicdb=PATH   specifies the path to the S-MusicBox database directory.
                  Default setting is the S_MUSICBOX environment variable.
                  Currently <$MUSICDB>
 --cdrom=SPEC,--cdromdev=SPEC
                  set CDROM drive/device to be used.  SPEC is system-dependend
                  and may be something like </dev/cdrom> or </dev/acd1c>;
                  on Mac OS X it is simply the number of the drive, e.g. <1>;
                  there it may be necessary to specify a different device node
                  (cdrom= is used for the drutil(1) '-drive' option, cdromdev=
                  only for /dev/diskXY lookup - try it if cdrom= alone fails).
                  Default settings are the CDROM/CDROMDEV environ variables.
 -r,--rip-only    exit after the data rip is completed
 -e CDID,--encode-only=CDID
                  resume a --rip-only session.  CDID is the CDDB ID of the
                  CDROM, and has been printed out by --rip-only before ...
 --mp3hi=BOOL,--mp3lo=.., --aachi=..,--aaclo=.., --ogghi=..,--ogglo=..
                  by default one adjusts the script header once for the
                  requirements of a specific site, but these command line
                  options can also be used to defined which output files shall
                  be produced: MP3, MP4/AAC and OGG (quality: high,low).
                  Current settings: $MP3HI,$MP3LO, $AACHI,$AACLO, $OGGHI,$OGGLO
_EOT
	exit(defined $emsg ? 1 : 0);
}

sub v {
	return unless $VERBOSE > 0;
	print STDOUT '-V  ', shift, "\n";
	while (@_ != 0) { print STDOUT '-V  ++  ', shift, "\n" };
	return 1;
}

sub genre {
	my $g = shift;
	if ($g =~ /^(\d+)$/) {
		$g = $1;
		foreach my $tr (@Genres) {
			return $tr->[1] if $tr->[0] == $g;
		}
	} else {
		$g = lc($g);
		foreach my $tr (@Genres) {
			return $tr->[1] if lc($tr->[1]) eq $g;
		}
	}
	return undef;
}

# Used only for valid genre-names
sub genre_id {
	my $g = shift;
	foreach my $tr (@Genres) {
		return $tr->[0] if $tr->[1] eq $g;
	}
}

sub cdsuck_openbsd {
	my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
	v("CD-Suck OpenBSD: using drive $drive");
}

sub cdsuck_freebsd {
	my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
	v("CD-Suck FreeBSD: using drive $drive");
	#$cdid = `/usr/sbin/cdcontrol $drive cdid 2>/dev/null`;
}

sub cdsuck_darwin {
	my $drive = defined $CDROM ? $CDROM : 1;
	my $disk = defined $CDROMDEV ? $CDROMDEV : $drive;
	print "CD-Suck darwin/Mac OS X: using drive $drive, /dev/disk$disk\n";

	# Unfortunately running drutil(1) may block the FS layer - in fact it
	# does not, so that glob succeeds but returns an empty list!!
	# Thus glob first and drutil afterwards ... (MacOS X 10.6)
	@SRC_FILES = sort {
		$a =~ /(\d+)$/;	my $xa = $1;
		$b =~ /(\d+)$/;	my $xb = $1;
		$xa <=> $xb;
	} glob("/dev/disk${disk}s[1-9]*");
	v("Glob results for </dev/disk${disk}s[1-9]*>:",
		join(', ', @SRC_FILES));
	die "Drive $drive: no track informations found" unless @SRC_FILES > 0;

	v("Invoking drutil(1) -drive $drive toc");
	my $l = `drutil -drive $drive toc`; # Success even if no media...
	my @res = split("\n", $l);
	die "Drive $drive: failed reading TOC: $! -- $^E" if $?;

	my (@cdtoc, $leadout);
	for(;;) {
		$l = shift(@res);
		die "Drive $drive: no lead-out information found"
			unless defined $l;
		if ($l =~ /^\s*Lead-out:\s+(\d+):(\d+)\.(\d+)/) {
			$leadout = "999 $1 $2 $3";
			last;
		}
	}
	for (my $li = 0;; ++$li) {
		$l = shift(@res);
		last unless defined $l;
		last unless $l =~ /^\s*Session\s+\d+,\s+Track\s+(\d+):
					\s+(\d+):(\d+)\.(\d+)
			.*/x;
		die "Drive $drive: corrupted TOC: $1 follows $li"
			unless $1 == $li+1;
		$cdtoc[$li] = "$1 $2 $3 $4";
	}
	die "Drive $drive: no track information found" unless @cdtoc > 0;
	push(@cdtoc, $leadout);

	_calc_cdid(\@cdtoc);
}

sub _calc_cdid {
	# This code is a stripped down version of CDDB.pm::calculate_id()
	my $cdtocr = shift;
	my ($sec_first, $sum);

	foreach (@$cdtocr) {
		my ($no, $min, $sec, $fra) = split(/\s+/, $_, 4);

		my $frame_off = (($min * 60 + $sec) * 75) + $fra;
		my $sec_begin = int($frame_off / 75);

		$sec_first = $sec_begin unless defined $sec_first;
		# Track 999 was chosen for the lead-out information.
		if ($no == 999) {
			$TOTAL_SECONDS = $sec_begin;
			last;
		}

		map { $sum += $_; } split(//, $sec_begin);
		push(@TRACK_OFFSETS, $frame_off);
	}

	$CDID = sprintf("%02x%04x%02x",
			($sum % 255), ($TOTAL_SECONDS - $sec_first),
			scalar(@TRACK_OFFSETS));
	v("Calculated CDID: $CDID");
}

sub user_confirm {
	print ' [Nn (or else)] ';
	my $u = <STDIN>;
	return $u =~ /n/i ? 0 : 1;
}

sub create_dir_and_dat {
	$TARGET_DIR = "$MUSICDB/DISC.$CDID";
	$WORK_DIR = "$ENV{TMPDIR}/s-disc-ripper.$CDID";
	v('Directories:', "WORK: <$WORK_DIR>", "TARGET: <$TARGET_DIR>");

	if (-d $TARGET_DIR && -f "$TARGET_DIR/musicbox.dat") {
		print "It seems that this CD has yet been ripped,\n",
			"because the directory <$TARGET_DIR> yet exists.\n";
		exit(7);
	}
	mkdir($WORK_DIR) or die "Cannot create <$WORK_DIR>: $! -- $^E"
		unless -d $WORK_DIR;

	print "Target directory: {S-MusicBox DB}/DISC.$CDID\n",
		"Working directory: ENVIRONMENT{TMPDIR}/s-disc-ripper.$CDID\n";

	unless (-f "$WORK_DIR/ripper.dat") {
		v("Creating $WORK_DIR/ripper.dat");
		open(DAT, ">$WORK_DIR/ripper.dat")
			or die "Cannot open <$WORK_DIR/ripper.dat>: $! -- $^E";
		print DAT "# $WORK_DIR/ripper.dat\n",
			"# S-Disc-Ripper CDDB info for project $CDID\n",
			"# Don't modify! or project needs to be re-ripped!!\n",
			"# CD track offsets:\n",
			join(' ', @TRACK_OFFSETS), "\n",
			"# CD total seconds:\n",
			$TOTAL_SECONDS, "\n";
		close(DAT)
			or die "Can't close <$WORK_DIR/ripper.dat>: $! -- $^E";
	} else {
		v("$WORK_DIR/ripper.dat yet exists");
	}
}

sub user_tracks {
	print	"\nThe CD $CDID contains ", scalar @SRC_FILES, ' songs - ',
		'shall all be ripped?';
	if (user_confirm()) {
		print "Whee - all songs will be ripped\n";
		return;
	}

	my ($line, @dt, @res);
jREDO:	print 'So, then: enter a space separated list of the ',
		"desired track numbers\n";
	$line = <STDIN>;
	chomp($line);
	@dt = split(/\s+/, $line);
	print "Is the following list correct?\n\t", join(' ', @dt);
	goto jREDO unless user_confirm();

	$#res = @SRC_FILES - 1;
	foreach my $i (@dt) {
		if ($i == 0 || $i > @SRC_FILES) {
			print "\tTrack number $i does not exist!\n\n";
			goto jREDO;
		}
		--$i;
		$res[$i] = $SRC_FILES[$i];
	}
	@SRC_FILES = @res;
}

sub resume_file_list {
	v("resume_file_list() for $CDID");
	$TARGET_DIR = "$MUSICDB/DISC.$CDID";
	$WORK_DIR = "$ENV{TMPDIR}/s-disc-ripper.$CDID";
	die "No --rip-only directory for $CDID exists ($WORK_DIR)"
		unless -d $WORK_DIR;

	print "Target directory: {S-MusicBox DB}/DISC.$CDID\n",
		"Working directory: ENVIRONMENT{TMPDIR}/s-disc-ripper.$CDID\n";

	open(DAT, "<$WORK_DIR/ripper.dat")
		or die "Cannot open <$WORK_DIR/ripper.dat>: $! -- $^E.\n" .
			'This project cannot be continued! ' .
			"\nRemove <$WORK_DIR> and re-rip the CD!";
	while (<DAT>) {
		s/^\s*(.*)\s*$/$1/;
		next if /^#/;
		@TRACK_OFFSETS = split(/\s+/) and next
			unless @TRACK_OFFSETS > 0;
		$TOTAL_SECONDS = $1 and last
			if /^(\d+)$/;
		die "<$WORK_DIR/ripper.dat> is corrupted - remove and re-rip!";
	}
	close(DAT) or die "Cannot close <$WORK_DIR/ripper.dat>: $! -- $^E";
	v("Resumed ripper.dat content:",
		'TRACK_OFFSETS: ' . join(' ', @TRACK_OFFSETS),
		"TOTAL_SECONDS: $TOTAL_SECONDS");

	my @res = glob("$WORK_DIR/*.raw");
	v("Glob results for <$WORK_DIR/*.raw>:", join(', ', @res));
	die "No dangling files for $CDID can be found" unless @res > 0;

	$#SRC_FILES = @TRACK_OFFSETS - 1;
	foreach my $f (@res) {
		$f =~ /(\d+)\.raw$/;
		die "Illegal file found - rerip of entire disc needed!"
			unless (defined $1 && $1 > 0 && $1 <= @SRC_FILES);
		$SRC_FILES[$1 - 1] = $f;
	}
}

sub database_stuff {
# TODO if yet exists and musicbox.dat exists etc simlpy read it in and fill in
# @DBCONTENT (drop CDDB query) - then let user reedit as usual -
# user must be able to choose special tracks to rip first
# like this individual tracks can be postinstalled / fieede
# needs diff. control flow with dir_and_dat() and jMAIN etc..
	unless (-d $TARGET_DIR) {
		mkdir($TARGET_DIR)
			or die "Can't create <$TARGET_DIR>: $! -- $^E";
	}
	cddb_query();
	create_database();
}

sub cddb_query {
	print "\nStarting CDDB query for $CDID\n";
	my $cddb = new CDDB or die "Cannot create CDDB object: $! -- $^E";
	my @discs = $cddb->get_discs($CDID, \@TRACK_OFFSETS, $TOTAL_SECONDS);

	if (@discs == 0) {
		print	"CDDB did not find an entry - i would fake!\n",
			'Is this ok - or is simply the network down? - ',
			"shall i quit? ";
		exit(10) if user_confirm();

jFAKE:		%TAG = ();
		$TAG{GENRE} = 'Humour';
		$TAG{ARTIST} = 'Unknown';
		Encode::_utf8_off($TAG{ARTIST});
		$TAG{ALBUM} = 'Unknown';
		Encode::_utf8_off($TAG{ALBUM});
		$TAG{YEAR} = '2001';
		my @tits;
		$TAG{TITLES} = \@tits;
		for (my $i = 0; $i < @SRC_FILES; ++$i) {
			my $s = 'TITLE ' . ($i + 1);
			Encode::_utf8_off($s);
			push(@tits, $s);
		}
		return;
	}

	my ($usr, $dinf);
jAREDO:	$usr = 1;
	foreach (@discs) {
		my ($genre, undef, $title) = @$_; # (cddb_id)
		print "\t[$usr] Genre:$genre, Title:$title\n";
		++$usr;
	}
	print "\t[0] None of those (creates a local fake entry)\n";

jREDO:	print 'Choose the number to use: ';
	$usr = <STDIN>;
	chomp($usr);
	unless ($usr =~ /\d+/ && ($usr = int($usr)) >= 0 && $usr <= @discs) {
		print "I'm expecting one of the [numbers] ... !\n";
		goto jREDO;
	}
	if ($usr == 0) {
		print "OK, creating a local fake entry\n";
		goto jFAKE;
	}
	$usr = $discs[--$usr];

	print 'Starting CDDB detail read for ', $usr->[0], "/$CDID\n";
	$dinf = $cddb->get_disc_details($usr->[0], $CDID);
	die "CDDB failed to return disc details" unless defined $dinf;

	# Prepare TAG as UTF-8 (CDDB entries may be ISO-8859-1 or UTF-8)
	%TAG = ();
	$TAG{GENRE} = genre($usr->[0]);
	unless (defined $TAG{GENRE}) {
		$TAG{GENRE} = 'Humour';
		print "CDDB entry has illegal GENRE - using $TAG{GENRE}\n";
	}
	{	my $aa = $usr->[2];
		# Shouldn't happen even for things like "B 52's / B 52's", but
		my ($art, $alb, $i);
		$i = index($aa, '/');
		if ($i < 0) {
			$art = $alb = $aa;
		} else {
			$art = substr($aa, 0, $i);
			$alb = substr($aa, ++$i);
		}
		$art =~ s/^\s*(.*?)\s*$/$1/;
			$i = $art;
			eval { Encode::from_to($art, 'iso-8859-1', 'utf-8'); };
			$art = $i if $@;
			Encode::_utf8_off($art);
		$TAG{ARTIST} = $art;
		$alb =~ s/^\s*(.*?)\s*$/$1/;
			$i = $alb;
			eval { Encode::from_to($alb, 'iso-8859-1', 'utf-8'); };
			$alb = $i if $@;
			Encode::_utf8_off($alb);
		$TAG{ALBUM} = $alb;
	}
	$TAG{YEAR} = defined $dinf->{dyear} ? $dinf->{dyear} : '';
	foreach (@{$dinf->{ttitles}}) {
		s/^\s*(.*?)\s*$/$1/;
		my $save = $_;
		eval { Encode::from_to($_, 'iso-8859-1', 'utf-8'); };
		$_ = $save if $@;
		Encode::_utf8_off($_);
	}
	$TAG{TITLES} = $dinf->{ttitles};
	print	"Full CD info for CD(DB)ID=$CDID\n",
		"(NOTE: terminal may not be able to display charset):\n",
		"\tGenre=$TAG{GENRE}, Year=$TAG{YEAR}\n",
		"\tArtist=$TAG{ARTIST}\n",
		"\tAlbum=$TAG{ALBUM}\n",
		"\tTitles in order:\n\t\t",
			join("\n\t\t", @{$TAG{TITLES}}),
		"\nIs this *really* the desired CD? ";
	goto jAREDO unless user_confirm();
}

sub create_database {
	# This uses the DBEntry package defined at the end of the file
	my ($tar, $db, $i) = ($TAG{TITLES});

	# Write template
	$db = "$WORK_DIR/content.dat";
	v("Creating editable DB template as <$db>");
	open(DB, ">$db") or die "Cannot open <$db>: $! -- $^E";
	if (@DBCONTENT > 0) {
		print DB "\n# CONTENT OF LAST USER EDIT AT END OF FILE!\n\n"
			or die "Error writing <$db>: $! -- $^E";
	}
	print DB DBEntry::db_help_text(),
	   "\n[ALBUM]\nTITLE = $TAG{ALBUM}\nTRACKCOUNT = ", scalar @$tar, "\n",
		((length($TAG{YEAR}) > 0) ? "YEAR = $TAG{YEAR}\n" : ''),
		"GENRE = $TAG{GENRE}\n",
	   "\n[CAST]\nARTIST = $TAG{ARTIST}\n\n"
		or die "Error writing <$db>: $! -- $^E";
	for ($i = 0; $i < @SRC_FILES; ++$i) {
		my $j = $i + 1;
		my $pre = (defined $SRC_FILES[$i] ? ''
			: "# TRACK $j NOT SELECTED - IT WILL NOT BE RIPPED\n");
		my $t = defined $tar->[$i] ? $tar->[$i] : "TITLE $j";
		print DB "${pre}[TRACK]\nNUMBER = $j\nTITLE = $t\n\n"
			or die "Error writing <$db>: $! -- $^E";
	}
	if (@DBCONTENT > 0) {
		print DB "\n# CONTENT OF LAST USER EDIT:\n"
			or die "Error writing <$db>: $! -- $^E";
		print DB "#$_\n" or die "Error writing <$db>: $! -- $^E"
			foreach (@DBCONTENT);
	}
	print DB
	 '# vim:set fenc=utf-8 filetype=txt syntax=cfg ts=8 sts=8 sw=8 tw=79:',
			"\n"
		or die "Error writing <$db>: $! -- $^E";
	close(DB) or die "Cannot close <$db>: $! -- $^E";

	# Let user verify, adjust and fill-in
	{	my $ed = defined $ENV{EDITOR} ? $ENV{EDITOR} : '/usr/bin/vi';
		print	"\nEditable database: <$db>\n",
			"Please do verify and edit this file as necessary\n",
			"Shall i invoke EDITOR <$ed>? ";
		if (user_confirm()) {
			my @args = ($ed, $db);
			system(@args);
		} else {
			print "Waiting: hit <RETURN> to continue ...";
			$ed = <STDIN>;
		}
	}

	# Re-Read final database
	# Working with objects may have been the easier approach
	$DBERROR = 0;
	@DBCONTENT = ();
	open(DB, "<$db")
		or die "Cannot open <$db>: $! -- $^E";
	my ($em, $ename, $entry) = (undef, undef, undef);
	while (<DB>) {
		s/^\s*(.*?)\s*$/$1/;
		next if length() == 0 || /^#/;
		my $line = $_;

		if ($line =~ /^\[(.*?)\]$/) {
			my $c = $1;
			if (defined $entry) {
				$em = $entry->finalize();
				if (defined $em) {
					$DBERROR = 1;
					print "ERROR: $em\n";
					$em = undef;
				}
				$entry = undef;
			}

			$ename = $c;
			next if $ename eq 'CDDB';
			no strict 'refs';
			my $class = "DBEntry::${ename}";
			my $sym = "${class}::new";
			unless (defined %{"${class}::"}) {
				$em = "Illegal command: [$ename]";
				goto jERROR;
			}
			$entry = &$sym($class, \$em);
		} elsif ($line =~ /^(.*?)\s*=\s*(.*)$/) {
			my ($k, $v) = ($1, $2);
			next if (defined $ename && $ename eq 'CDDB');
			unless (defined $entry) {
				$em = "KEY=VALUE line without group: <$k=$v>";
				goto jERROR;
			}
			$em = $entry->set_tuple($k, $v);
		} else {
			$em = "Found illegal line <$_>";
		}

		if (defined $em) {
jERROR:			$DBERROR = 1;
			print "ERROR: $em\n";
			$em = undef;
		}
	}
	if (defined $entry && defined($em = $entry->finalize())) {
		$DBERROR = 1;
		print "ERROR: $em\n";
	}
	close(DB) or die "Cannot close <$db>: $! -- $^E";
	DBEntry::finalize_db_read();

	if ($DBERROR) {
		print 'Errors detected - the database will be rewritten; ',
			"edit once again!\n";
		create_database();
		return;
	}

	print "\nPlease verify the database:\n";
	print "\t$_\n" foreach (@DBCONTENT);
	print "Is the database OK? ";
	unless (user_confirm()) {
		$DBERROR = 1;
		DBEntry::finalize_db_read();
		create_database();
		return;
	}

	$db = "$TARGET_DIR/musicbox.dat";
	v("Creating final DB as <$db>");
	open(DB, ">$db") or die "Cannot open <$db>: $! -- $^E";
	print DB "[CDDB]\nCDID = $CDID\nTRACK_OFFSETS = ",
				join(' ', @TRACK_OFFSETS),
			"\nTOTAL_SECONDS = $TOTAL_SECONDS\n",
		or die "Error writing <$db>: $! -- $^E";
	print DB $_, "\n" or die "Error writing <$db>: $! -- $^E"
		foreach (@DBCONTENT);
	close(DB) or die "Cannot close <$db>: $! -- $^E";
}

sub rip_files {
	print "\nRipping files\n";
	my @tfiles;
	for (my $i = 0; $i < @SRC_FILES; ++$i) {
		next unless defined $SRC_FILES[$i];
		my $t = $i + 1;
		my ($sf, $tf) = ($SRC_FILES[$i], "$WORK_DIR/$t.raw");

		if (-f $tf) {
			print	"Track $t has yet been ripped?! ",
				'Shall i re-rip it? ';
			unless (user_confirm()) {
				push(@tfiles, $tf);
				next;
			}
		}

		print "\tRipping track $t ($sf)\n";
		system "dd bs=2352 if=$sf of=$tf";
		if (($? >> 8) == 0) {
			push(@tfiles, $tf);
		} else {
			print	"Error ripping track $t: $! -- $^E\n",
				'Track will be excluded from ripping. - ',
				"shall i quit? ";
			exit(5) if user_confirm();
		}
	}
	@SRC_FILES = @tfiles;
}

sub calculate_volume_adjust {
	print "\nCalculating average volume adjustment over all files\n";
	$VOL_ADJUST = undef;
	foreach my $f (@SRC_FILES) {
		open(SOX, "sox -t raw -r44100 -c2 -w -s $f -e stat -v 2>&1 |")
			or die "Cannot open SOX status pipe for $f: $! -- $^E";
		my $avg = <SOX>;
		close(SOX) or die "Cannot close SOX status pipe: $! -- $^E";
		chomp($avg);

		print "\t<$f>: $avg\n";
		$VOL_ADJUST = $avg unless defined $VOL_ADJUST;
		$VOL_ADJUST = $avg if $avg < $VOL_ADJUST;
	}
	print "\tMinimum volume adjustment: $VOL_ADJUST\n";
}

sub encode_all_files {
	print "\nEncoding files\n";
	foreach my $f (@SRC_FILES) {
		$f =~ /(\d+)\.raw$/;
		my $i = $1;
		my $tpath = "$TARGET_DIR/" . sprintf('%03d', $i);
		_mp3tag_file($i, $tpath) if ($MP3HI || $MP3LO);
		_faac_comment($i) if ($AACHI || $AACLO);
		_oggenc_comment($i) if ($OGGHI || $OGGLO);
		_encode_file($f, $tpath);
	}
}

sub _mp3tag_file {
	# Stuff in (parens) refers to the ID3 tag version 2.3.0, www.id3.org.
	my ($no, $tpath) = @_;
	my $hr = $TAG{$no};
	v("Creating MP3 tag file headers");

	my $tag;
	$tag .= _mp3_frame('TPE1', $hr->{TPE1});
	$tag .= _mp3_frame('TCOM', $hr->{TCOM}) if defined $hr->{TCOM};
	$tag .= _mp3_frame('TALB', $hr->{TALB});
	$tag .= _mp3_frame('TIT1', $hr->{TIT1}) if defined $hr->{TIT1};
	$tag .= _mp3_frame('TIT2', $hr->{TIT2});
	$tag .= _mp3_frame('TRCK', $hr->{TRCK});
	$tag .= _mp3_frame('TPOS', $hr->{TPOS}) if defined $hr->{TPOS};
	$tag .= _mp3_frame('TCON', '(' . $hr->{GENREID} . ')' . $hr->{GENRE});
	$tag .= _mp3_frame('TYER', $hr->{YEAR}, 'NUM') if defined $hr->{YEAR};
	$hr = $hr->{COMM};
	if (defined $hr) {
		$hr = "engS-MUSICBOX:COMM\x00$hr";
		$tag .= _mp3_frame('COMM', $hr, 'UNI');
	}

	# (5.) Apply unsynchronization to all frames
	my $has_unsynced = int($tag =~ s/\xFF/\xFF\x00/gs);

	# (3.1.) Prepare the header
	# ID3v2, version 2
	my $header = 'ID3' . "\x03\00";
	# Flags 1 byte: bit 7 (first bit MSB) =$has_unsynced
	$header .= pack('C', ($has_unsynced > 0) ? 0x80 : 0x00);
	# Tag size: 4 bytes as 4*7 bits
	{	my $l = length($tag);
		my $r;
		# Don't use my own carry-flag beatin' version, but the
		# MP3-Info.pm one ...
		#$r =   $l       & 0x0000007F;
		#$r |= ($l << 1) & 0x00007F00;
		#$r |= ($l << 2) & 0x007F0000;
		#$r |= ($l << 3) & 0x7F000000;
		$r  = ($l & 0x0000007F);
		$r |= ($l & 0x00003F80) << 1;
		$r |= ($l & 0x001FC000) << 2;
		$r |= ($l & 0x0FE00000) << 3;
		$header .= pack('N', $r);
	}

	for (my $i = 0; $i < 2; ++$i) {
		if ($i == 0) {
			$no = "$tpath.hi.mp3";
			next if $MP3HI == 0;
		} else {
			$no = "$tpath.lo.mp3";
			next if $MP3LO == 0;
		}
		open(F, ">$no") or die "Cannot open <$no>: $! -- $^E";
		binmode(F) or die "binmode <$no> failed: $! -- $^E";
		print F $header, $tag or die "Error writing <$no>: $! -- $^E";
		close(F) or die "Cannot close <$no>: $! -- $^E";
	}
}

sub _mp3_frame {
	my ($fid, $ftxt) = @_;
	my ($len, $txtenc);
	# Numerical strings etc. always latin-1
	if (@_ > 2) {
		my $add = $_[2];
		if ($add eq 'NUM') {
			$len = length($ftxt);
			$txtenc = "\x00";
		} else { #if ($add eq 'UNI') {
			$txtenc = _mp3_string(1, \$ftxt, \$len);
		}
	} else {
		$txtenc = _mp3_string(0, \$ftxt, \$len);
	}
	# (3.3) Frame header
	# [ID=4 chars;] Size=4 bytes=size - header (10); Flags=2 bytes
	++$len; # $txtenc
	$fid .= pack('CCCCCC',
		($len & 0xFF000000) >> 24,
			($len & 0x00FF0000) >> 16,
			($len & 0x0000FF00) >>  8,
			($len & 0x000000FF),
		0, 0);
	# (4.2) Text information
	$fid .= $txtenc;
	$fid .= $ftxt;
	return $fid;
}

sub _mp3_string {
	my ($force_uni, $txtr, $lenr) = @_;
	my $i = $$txtr;
	my $isuni;
	unless ($force_uni) {
		eval { $isuni = Encode::from_to($i, 'utf-8', 'iso-8859-1',1);};
	}
	if ($force_uni || $@ || !defined $isuni) {
		Encode::from_to($$txtr, 'utf-8', 'utf-16');
		$$lenr = bytes::length($$txtr);
		return "\x01";
	} else {
		$$txtr = $i;
		#$$lenr = length($$txtr);
		$$lenr = $isuni;
		return "\x00";
	}
}

sub _faac_comment {
	my ($no) = @_;
	my $hr = $TAG{$no};
	my $i;
	$AACTAG = '';
	$i = $hr->{ARTIST}; $i =~ s/"/\\"/g; $AACTAG .= "--artist \"$i\" ";
	$i = $hr->{ALBUM};  $i =~ s/"/\\"/g; $AACTAG .= "--album \"$i\" ";
	$i = $hr->{TITLE};  $i =~ s/"/\\"/g; $AACTAG .= "--title \"$i\" ";
	$AACTAG .= "--track \"$hr->{TRCK}\" "
		. (defined $hr->{TPOS} ? "--disc \"$hr->{TPOS}\" " : '')
		. "--genre '$hr->{GENRE}' "
		. (defined $hr->{YEAR} ? "--year \"$hr->{YEAR}\"" : '');
	$i = $hr->{COMM};
	if (defined $i) {
		$i =~ s/"/\\"/g;
		$AACTAG .=" --comment \"S-MUSICBOX:COMM=$i\"";
	}
	v("AACTAG: $AACTAG");
}

sub _oggenc_comment {
	my ($no) = @_;
	my $hr = $TAG{$no};
	my $i;
	$OGGTAG = '';
	$i = $hr->{ARTIST}; $i =~ s/"/\\"/g; $OGGTAG .= "--artist \"$i\" ";
	$i = $hr->{ALBUM};  $i =~ s/"/\\"/g; $OGGTAG .= "--album \"$i\" ";
	$i = $hr->{TITLE};  $i =~ s/"/\\"/g; $OGGTAG .= "--title \"$i\" ";
	$OGGTAG .= "--tracknum \"$hr->{TRACKNUM}\" "
		. (defined $hr->{TPOS} ? "--comment=\"TPOS=$hr->{TPOS}\" " :'')
		. "--comment=\"TRCK=$hr->{TRCK}\" "
		. "--genre \"$hr->{GENRE}\" "
		. (defined $hr->{YEAR} ? "--date \"$hr->{YEAR}\"" : '');
	$i = $hr->{COMM};
	if (defined $i) {
		$i =~ s/"/\\"/g;
		$OGGTAG .=" --comment \"S-MUSICBOX:COMM=$i\"";
	}
	v("OGGTAG: $OGGTAG");
}

sub _encode_file {
	my ($src_path, $tpath) = @_;
	print "\tTrack <$tpath.*>\n";

	open(SOX, "sox -v $VOL_ADJUST -t raw -r44100 -c2 -w -s $src_path " .
			'-t raw - |')
		or die "Cannot open SOX pipe: $! -- $^E";
	binmode(SOX) or die "binmode SOX failed: $! -- $^E";

	if ($MP3HI) {
		v('Creating MP3 lame(1) high-quality encoder pipe');
		open(MP3HI, '| lame --quiet -r -x -s 44.1 --bitwidth 16 ' .
				"--vbr-new -V 0 -q 0 - - >> $tpath.hi.mp3")
			or die "Cannot open LAME-high pipe: $! -- $^E";
		binmode(MP3HI) or die "binmode LAME-high failed: $! -- $^E";
	}
	if ($MP3LO) {
		v('Creating MP3 lame(1) low-quality encoder pipe');
		open(MP3LO, '| lame --quiet -r -x -s 44.1 --bitwidth 16 ' .
			"--vbr-new -V 7 -q 0 - - >> $tpath.lo.mp3")	
			or die "Cannot open LAME-low pipe: $! -- $^E";
		binmode(MP3LO) or die "binmode LAME-low failed: $! -- $^E";
	}
	if ($AACHI) {
		v('Creating MP4/AAC faac(1) high-quality encoder pipe');
		open(AACHI, '| faac -XP --mpeg-vers 4 -ws --tns -q 300 ' .
				"$AACTAG -o $tpath.hi.mp4 - >/dev/null 2>&1")
			or die "Cannot open FAAC-high pipe: $! -- $^E";
		binmode(AACHI) or die "binmode FAAC-high failed: $! -- $^E";
	}
	if ($AACLO) {
		v('Creating MP4/AAC faac(1) low-quality encoder pipe');
		open(AACLO, '| faac -XP --mpeg-vers 4 -ws --tns -q 80 ' .
				"$AACTAG -o $tpath.lo.mp4 - >/dev/null 2>&1")
			or die "Cannot open FAAC-low pipe: $! -- $^E";
		binmode(AACLO) or die "binmode FAAC-low failed: $! -- $^E";
	}
	if ($OGGHI) {
		v('Creating Ogg/Vorbis oggenc(1) high-quality encoder pipe');
		open(OGGHI, "| oggenc -Q -r -q 8.5 $OGGTAG -o $tpath.hi.ogg -")
			or die "Cannot open OGGENC-high pipe: $! -- $^E";
		binmode(OGGHI) or die "binmode OGGENC-high failed: $! -- $^E";
	}
	if ($OGGLO) {
		v('Creating Ogg/Vorbis oggenc(1) low-quality encoder pipe');
		open(OGGLO, "| oggenc -Q -r -q 3.8 $OGGTAG -o $tpath.lo.ogg -")
			or die "Cannot open OGGENC-low pipe: $! -- $^E";
		binmode(OGGLO) or die "binmode OGGENC-low failed: $! -- $^E";
	}

	for (my $data;;) {
		$data = undef;
		my $bytes = read(SOX, $data, 8192*15);
		die "Error reading SOX: $! -- $^E" unless defined $bytes;
		last if $bytes == 0;
		print MP3HI $data or die "Error writing LAME-high: $! -- $^E"
			if $MP3HI;
		print MP3LO $data or die "Error writing LAME-low: $! -- $^E"
			if $MP3LO;
		print AACHI $data or die "Error writing FAAC-high: $! -- $^E"
			if $AACHI;
		print AACLO $data or die "Error writing FAAC-low: $! -- $^E"
			if $AACLO;
		print OGGHI $data or die "Error write OGGENC-high: $! -- $^E"
			if $OGGHI;
		print OGGLO $data or die "Error write OGGENC-low: $! -- $^E"
			if $OGGLO;
	}

	close(SOX) or die "Cannot close SOX pipe: $! -- $^E";
	close(MP3HI) or die "Cannot close LAME-high pipe: $! -- $^E"
		if $MP3HI;
	close(MP3LO) or die "Cannot close LAME-low pipe: $! -- $^E"
		if $MP3LO;
	close(AACHI) or die "Cannot close FAAC-high pipe: $! -- $^E"
		if $AACHI;
	close(AACLO) or die "Cannot close FAAC-low pipe: $! -- $^E"
		if $AACLO;
	close(OGGHI) or die "Cannot close OGGENC-high pipe: $! -- $^E"
		if $OGGHI;
	close(OGGLO) or die "Cannot close OGGENC-low pipe: $! -- $^E"
		if $OGGLO;
}

# DBEntry simplifies reading and checking of the database file after the user
# modified it and of course the creation of the %TAG data for the individual
# tracks; because it is not ment for any other purpose it's small minded and
# a dead end street for all the data - but that's really sufficient here,
# because if the database has been falsely edited the user must correct it!
# At least a super-object based approach should have been used though.
# All strings come in as UTF-8 and remain unmodified
{package DBEntry;
	my ($AlbumSet, $Album, $Cast, $Group);
	BEGIN {	$DBEntry::AlbumSet =
		$DBEntry::Album =
		$DBEntry::Cast =
		$DBEntry::Group = undef;
	}

	sub db_help_text {
		sub __help {
			return <<_EOT;		
# S-MusicBox database, CD(DB)ID $TAG{GENRE}/$CDID
# This file is and used to be in UTF-8 encoding (codepage,charset) ONLY!
# Syntax (processing is line based):
# - Leading and trailing whitespace is ignored
# - Empty lines are ignored
# - Lines starting with # are comments and discarded
# - [GROUPNAME] on a line of its own begins a group
# - And there are 'KEY = VALUE' lines - surrounding whitespace is trimmed away
# - Definition ORDER IS IMPORTANT!
_EOT
		}
		return __help() .
			DBEntry::ALBUMSET::db_help_text() .
			DBEntry::ALBUM::db_help_text() .
			DBEntry::CAST::db_help_text() .
			DBEntry::GROUP::db_help_text() .
			DBEntry::TRACK::db_help_text();
	}

	# create_database() finalization hooks
	sub clear_db {
		$DBEntry::AlbumSet =
		$DBEntry::Album =
		$DBEntry::Cast =
		$DBEntry::Group = undef;
		my ($tar, $i) = ($TAG{TITLES});
		for ($i = 0; $i < @$tar; ++$i) {
			my $j = $i + 1;
			delete $TAG{$j};
		}
	}
	sub finalize_db_read {
		return clear_db() if $DBERROR;
		for (my $i = 0; $i < @SRC_FILES; ++$i) {
			my $j = $i + 1;
			next if exists $TAG{$j};
			next unless defined $SRC_FILES[$i];

			::v("DBEntry::finalize_db_read(): new faker for $j");
			my $t = DBEntry::TRACK->new(undef);
			$t->set_tuple('NUMBER', $j);
			$t->set_tuple('TITLE', 'TITLE '.$j);
			_create_track_tag($t);
		}
	}

	# called by TRACK->finalize()
	sub _create_track_tag {
		return if $DBERROR;
		my $track = shift;
		my (%tag, $c, $composers, $i);
		$TAG{$track->{NUMBER}} = \%tag;

		# TPE1/TCOM,--artist,--artist - TCOM MAYBE UNDEF
		$tag{TCOM} = undef;
		$tag{TPE1} =
		$tag{ARTIST} = $TAG{ARTIST};
		$c = $track->{cast};
		$composers = undef;
		if (defined $c) {
			my ($i, $s, $x) = (-1, '', 0);
			foreach (@{$c->{ARTIST}}) {
				$s .= '/' if ++$i > 0;
				$s .= $_;
			}
			$x = ($i >= 0);
			$i = -1;
			foreach (@{$c->{SOLOIST}}) {
				$s .= ', ' if (++$i > 0 || $x);
				$x = 0;
				$s .= $_;
			}
			foreach (@{$c->{CONDUCTOR}}) {
				$s .= ', ' if (++$i > 0 || $x);
				$x = 0;
				$s .= $_;
			}
			$tag{TPE1} =
			$tag{ARTIST} = $s;

			($i, $s, $x) = (-1, '', 0);
			foreach (@{$c->{COMPOSER}}) {
				$s .= ', ' if ++$i > 0;
				$s .= $_;
			}
			$composers = $s if length($s) > 0;
			$x = ($i >= 0);
			$i = -1;
			foreach (@{$c->{SONGWRITER}}) {
				if ($x) {
					$s .= ', ';
					$x = 0;
				}
				$s .= '/' if ++$i > 0;
				$s .= "$_";
			}
			$tag{TCOM} = $s if length($s) > 0;
		}

		# TALB,--album,--album
		$tag{TALB} =
		$tag{ALBUM} = $TAG{ALBUM};
		if (defined $DBEntry::Album) {
			$tag{ALBUM} = (defined $DBEntry::AlbumSet
					? "$DBEntry::AlbumSet->{TITLE} - " : ''
					) . $DBEntry::Album->{TITLE};
		}
		$tag{ALBUM} = "$composers: $tag{ALBUM}" if defined $composers;

		# TIT1/TIT2,--title,--title - TIT1 MAYBE UNDEF
		$tag{TIT1} = (defined $DBEntry::Group
				? $DBEntry::Group->{LABEL} : undef);
		$tag{TIT2} = $track->{TITLE};
		$tag{TITLE} = (defined $tag{TIT1}
				? "$tag{TIT1} - $tag{TIT2}"
				: $tag{TIT2});

		# TRCK,--track: TRCK; --tracknum: TRACKNUM
		$tag{TRCK} =
		$tag{TRACKNUM} = $track->{NUMBER};
		$tag{TRCK} .= (defined $DBEntry::Album
				? "/$DBEntry::Album->{TRACKCOUNT}"
				: '/' . scalar @{$TAG{TITLES}});

		# TPOS,--disc - MAYBE UNDEF
		$tag{TPOS} = undef;
		if (defined $DBEntry::AlbumSet && defined $DBEntry::Album) {
			$tag{TPOS} = $DBEntry::Album->{SETPART} . '/' .
					$DBEntry::AlbumSet->{SETCOUNT};
		}

		# TYER,--year,--date: YEAR - MAYBE UNDEF
		$tag{YEAR} = (defined $track->{YEAR} ? $track->{YEAR}
				: ((defined $DBEntry::Group &&
				    defined $DBEntry::Group->{YEAR})
					? $DBEntry::Group->{YEAR}
				: ((defined $DBEntry::Album &&
				    defined $DBEntry::Album->{YEAR})
					? $DBEntry::Album->{YEAR}
				: ((defined $DBEntry::AlbumSet &&
				    defined $DBEntry::AlbumSet->{YEAR})
					? $DBEntry::AlbumSet->{YEAR}
				: (length($TAG{YEAR}) > 0) ? $TAG{YEAR}
				: undef))));

		# TCON,--genre,--genre
		$tag{GENRE} = (defined $track->{GENRE} ? $track->{GENRE}
				: ((defined $DBEntry::Group &&
				    defined $DBEntry::Group->{GENRE})
					? $DBEntry::Group->{GENRE}
				: ((defined $DBEntry::Album &&
				    defined $DBEntry::Album->{GENRE})
					? $DBEntry::Album->{GENRE}
				: ((defined $DBEntry::AlbumSet &&
				    defined $DBEntry::AlbumSet->{GENRE})
					? $DBEntry::AlbumSet->{GENRE}
				: $TAG{GENRE}))));
		$tag{GENREID} = ::genre_id($tag{GENRE});

		# COMM,--comment,--comment - MAYBE UNDEF
		$tag{COMM} = $track->{COMMENT};
	}

{package DBEntry::ALBUMSET;
	sub db_help_text {
		return <<_EOT;
# [ALBUMSET]: TITLE, SETCOUNT, (YEAR, GENRE, GAPLESS, COMPILATION)
#	If a multi-CD-Set is ripped each CD gets its own database file, say;
#	ALBUMSET and the SETPART field of ALBUM are how to group 'em
#	nevertheless: repeat the same ALBUMSET and adjust the SETPART field.
#	GENRE is one of the widely (un)known ID3 genres.
#	GAPLESS states wether there shall be no silence in between tracks,
#	and COMPILATION wether this is a compilation of various-artists or so.
_EOT
	}
	sub is_key_supported {
		my $k = shift;
		return	($k eq 'TITLE' ||
			$k eq 'SETCOUNT' || $k eq 'YEAR' || $k eq 'GENRE' ||
			$k eq 'GAPLESS' || $k eq 'COMPILATION');
	}

	sub new {
		my ($class, $emsgr) = @_;
		if (defined $DBEntry::AlbumSet) {
			$$emsgr = 'ALBUMSET yet defined';
			return undef;
		}
		::v("DBEntry::ALBUMSET::new()");
		push(@DBCONTENT, '[ALBUMSET]');
		my $self = { objectname => 'ALBUMSET',
			TITLE => undef,
			SETCOUNT => undef, YEAR => undef, GENRE => undef,
			GAPLESS => 0, COMPILATION => 0
		};
		$self = bless($self, $class);
		$DBEntry::AlbumSet = $self;
		return $self;
	}
	sub set_tuple {
		my ($self, $k, $v) = @_;
		$k = uc($k);
		return "$self->{objectname}: $k not supported"
			unless is_key_supported($k);
		::v("DBEntry::ALBUMSET::set_tuple($k=$v)");
		$self->{$k} = $v;
		push(@DBCONTENT, "$k = $v");
		return undef;
	}
	sub finalize {
		my $self = shift;
		my $emsg = undef;
		$emsg .= 'ALBUMSET requires TITLE and SETCOUNT;'
			unless (defined $self->{TITLE} &&
				defined $self->{SETCOUNT});
		return $emsg;
	}
}

{package DBEntry::ALBUM;
	sub db_help_text {
		return <<_EOT;
# [ALBUM]: TITLE, TRACKCOUNT, (SETPART, YEAR, GENRE, GAPLESS, COMPILATION)
#	If the album is part of an ALBUMSET TITLE may only be 'CD 1' - it is
#	required nevertheless even though it could be deduced automatically
#	from the ALBUMSET's TITLE and the ALBUM's SETPART - sorry!
#	I.e. SETPART is required, then, and the two TITLEs are *concatenated*.
#	GENRE is one of the widely (un)known ID3 genres.
#	GAPLESS states wether there shall be no silence in between tracks,
#	and COMPILATION wether this is a compilation of various-artists or so.
_EOT
	}
	sub is_key_supported {
		my $k = shift;
		return	($k eq 'TITLE' ||
			$k eq 'TRACKCOUNT' ||
			$k eq 'SETPART' || $k eq 'YEAR' || $k eq 'GENRE' ||
			$k eq 'GAPLESS' || $k eq 'COMPILATION');
	}

	sub new {
		my ($class, $emsgr) = @_;
		if (defined $DBEntry::Album) {
			$$emsgr = 'ALBUM yet defined';
			return undef;
		}
		::v("DBEntry::ALBUM::new()");
		push(@DBCONTENT, '[ALBUM]');
		my $self = { objectname => 'ALBUM',
			TITLE => undef, TRACKCOUNT => undef,
			SETPART => undef, YEAR => undef, GENRE => undef,
			GAPLESS => 0, COMPILATION => 0
		};
		$self = bless($self, $class);
		$DBEntry::Album = $self;
		return $self;
	}
	sub set_tuple {
		my ($self, $k, $v) = @_;
		$k = uc($k);
		return "$self->{objectname}: $k not supported"
			unless is_key_supported($k);
		return "ALBUM: SETPART given but no ALBUMSET ever defined"
			if ($k eq 'SETPART' && !defined $DBEntry::AlbumSet);
		if ($k eq 'GENRE') {
			my $g = ::genre($v);
			return "ALBUM: $v not a valid GENRE (try --genre-list)"
				unless defined $g;
			$v = $g;
		}
		::v("DBEntry::ALBUM::set_tuple($k=$v)");
		$self->{$k} = $v;
		push(@DBCONTENT, "$k = $v");
		return undef;
	}
	sub finalize {
		my $self = shift;
		my $emsg = undef;
		$emsg .= 'ALBUM requires TITLE;' unless defined $self->{TITLE};
		$emsg .= 'ALBUM requires TRACKCOUNT;'
			unless defined $self->{TRACKCOUNT};
		if (defined $DBEntry::AlbumSet && !defined $self->{SETPART}) {
			$emsg .= 'ALBUM requires SETPART if ALBUMSET defined;';
		}
		return $emsg;
	}
}

{package DBEntry::CAST;
	sub db_help_text {
		return <<_EOT;
# [CAST]: (ARTIST, SOLOIST, CONDUCTOR, COMPOSER/SONGWRITER, SORT)
#	The CAST includes all the humans responsible for an artwork in detail.
#	Cast information not only applies to the ([ALBUMSET] and) [ALBUM],
#	but also to all following tracks; thus, if any [GROUP] or [TRACK] is to
#	be defined which shall not inherit the [CAST] fields, they need to be
#	defined first!
#	SORT fields are special in that they *always* apply globally; whereas
#	the other fields should be real names ("Wolfgang Amadeus Mozart") these
#	specify how sorting is to be applied ("Mozart, Wolfgang Amadeus").
#	For classical music the orchestra should be the ARTIST.
#	SOLOIST should include the instrument in parenthesis (Midori (Violin)).
#	The difference between COMPOSER and SONGWRITER is only noticeable for
#	output file formats which do not support a COMPOSER information frame:
#	whereas the SONGWRITER is simply discarded then, the COMPOSER becomes
#	part of the ALBUM (Vivaldi: Le quattro stagioni - "La Primavera");
#	all of this only applies to in-file information, not to the S-MusicBox
#	interface, which of course uses the complete entry of the database.
_EOT
	}
	sub is_key_supported {
		my $k = shift;
		return	($k eq 'ARTIST' ||
			$k eq 'SOLOIST' || $k eq 'CONDUCTOR' ||
			$k eq 'COMPOSER' || $k eq 'SONGWRITER' ||
			$k eq 'SORT');
	}

	sub new {
		my ($class, $emsgr) = @_;
		my $parent = (@_ > 2) ? $_[2] : undef;
		if (!defined $parent && defined $DBEntry::Cast) {
			$$emsgr = 'CAST yet defined';
			return undef;
		}
		::v("DBEntry::CAST::new(" .
			(defined $parent ? "parent=$parent)" : ')'));
		push(@DBCONTENT, '[CAST]') unless defined $parent;
		my $self = { objectname => 'CAST', parent => $parent,
				ARTIST => [],
				SOLOIST => [], CONDUCTOR => [],
				COMPOSER => [], SONGWRITER => [],
				SORT => []
			};
		$self = bless($self, $class);
		$DBEntry::Cast = $self unless defined $parent;
		return $self;
	}
	sub new_state_clone {
		my $parent = shift;
		my $self = DBEntry::CAST->new(undef, $parent);
		if ($parent eq 'TRACK' && defined $DBEntry::Group) {
			$parent = $DBEntry::Group->{cast};
		} elsif (defined $DBEntry::Cast) {
			$parent = $DBEntry::Cast;
		} else {
			$parent = undef;
		}
		if (defined $parent) {
			foreach (@{$parent->{ARTIST}}) {
				push(@{$self->{ARTIST}}, $_);
				#push(@DBCONTENT, "ARTIST = $_");
			}
			foreach (@{$parent->{SOLOIST}}) {
				push(@{$self->{SOLOIST}}, $_);
				#push(@DBCONTENT, "SOLOIST = $_");
			}
			foreach (@{$parent->{CONDUCTOR}}) {
				push(@{$self->{CONDUCTOR}}, $_);
				#push(@DBCONTENT, "CONDUCTOR = $_");
			}
			foreach (@{$parent->{COMPOSER}}) {
				push(@{$self->{COMPOSER}}, $_);
				#push(@DBCONTENT, "COMPOSER = $_");
			}
			foreach (@{$parent->{SONGWRITER}}) {
				push(@{$self->{SONGWRITER}}, $_);
				#push(@DBCONTENT, "SONGWRITER = $_");
			}
		}
		return $self;
	}
	sub set_tuple {
		my ($self, $k, $v) = @_;
		$k = uc($k);
		return "$self->{objectname}: $k not supported"
			unless is_key_supported($k);
		#return "CAST: SORT always global: should be in [CAST], " .
		#		"not in $self->{parent}"
		#	if (defined $self->{parent} && $k eq 'SORT');
		::v("DBEntry::CAST::set_tuple($k=$v)");
		push(@{$self->{$k}}, $v);
		push(@DBCONTENT, "$k = $v");
		return undef;
	}
	sub finalize {
		my $self = shift;
		my $emsg = undef;
		if (defined $self->{parent} && $self->{parent} eq 'TRACK' &&
		    @{$self->{ARTIST}} == 0) {
			$emsg .= 'TRACK requires at least one ARTIST;';
		}
		return $emsg;
	}
}

{package DBEntry::GROUP;
	sub db_help_text {
		return <<_EOT;
# [GROUP]: LABEL, (YEAR, GENRE, GAPLESS, COMPILATION, [CAST]-fields)
#	Grouping information applies to all following tracks unless the next
#	[GROUP]; TRACKs which do not apply to any GROUP must thus be defined
#	first!
#	GENRE is one of the widely (un)known ID3 genres.
#	GAPLESS states wether there shall be no silence in between tracks,
#	and COMPILATION wether this is a compilation of various-artists or so.
#	CAST-fields may be used to *append* to global [CAST] fields; to specify
#	CAST fields exclusively, place the GROUP before the global [CAST].
_EOT
	}
	sub is_key_supported {
		my $k = shift;
		return	($k eq 'LABEL' || $k eq 'YEAR' || $k eq 'GENRE' ||
			$k eq 'GAPLESS' || $k eq 'COMPILATION' ||
			DBEntry::CAST::is_key_supported($k));
	}

	sub new {
		my ($class, $emsgr) = @_;
		::v("DBEntry::GROUP::new()");
		push(@DBCONTENT, '[GROUP]');
		my $self = { objectname => 'GROUP',
				LABEL => undef, YEAR => undef, GENRE => undef,
				GAPLESS => 0, COMPILATION => 0,
				cast => DBEntry::CAST::new_state_clone('GROUP')
		};
		$self = bless($self, $class);
		$DBEntry::Group = $self;
		return $self;
	}
	sub set_tuple {
		my ($self, $k, $v) = @_;
		$k = uc($k);
		return "$self->{objectname}: $k not supported"
			unless is_key_supported($k);
		if ($k eq 'GENRE') {
			$v = ::genre($v);
			return "GROUP: $v not a valid GENRE (try --genre-list)"
				unless defined $v;
		}
		::v("DBEntry::GROUP::set_tuple($k=$v)");
		if (exists $self->{$k}) {
			$self->{$k} = $v;	
			push(@DBCONTENT, "$k = $v");
		} else {
			$self->{cast}->set_tuple($k, $v);
		}
		return undef;
	}
	sub finalize {
		my $self = shift;
		my $emsg = undef;
		unless (defined $self->{LABEL}) {
			$emsg .= 'GROUP requires LABEL;';
		}
		my $em = $self->{cast}->finalize();
		$emsg .= $em if defined $em;
		return $emsg;
	}
}

{package DBEntry::TRACK;
	sub db_help_text {
		return <<_EOT;
# [TRACK]: NUMBER, TITLE, (YEAR, GENRE, COMMENT, [CAST]-fields)
#	GENRE is one of the widely (un)known ID3 genres.
#	CAST-fields may be used to *append* to global [CAST] (and those of the
#	[GROUP], if any) fields; to specify CAST fields exclusively, place the
#	TRACK before the global [CAST].
#	Note: all TRACKs need an ARTIST in the end, from whatever CAST it is
#	inherited.
_EOT
	}
	sub is_key_supported {
		my $k = shift;
		return	($k eq 'NUMBER' || $k eq 'TITLE' ||
			$k eq 'YEAR' || $k eq 'GENRE' || $k eq 'COMMENT' ||
			DBEntry::CAST::is_key_supported($k));
	}

	sub new {
		my ($class, $emsgr) = @_;
		::v("DBEntry::TRACK::new()");
		push(@DBCONTENT, '[TRACK]');
		my $self = { objectname => 'TRACK',
				NUMBER => undef, TITLE => undef,
				YEAR => undef, GENRE => undef, COMMENT =>undef,
				group => $DBEntry::Group,
				cast => DBEntry::CAST::new_state_clone('TRACK')
		};
		$self = bless($self, $class);
		return $self;
	}
	sub set_tuple {
		my ($self, $k, $v) = @_;
		$k = uc($k);
		return "$self->{objectname}: $k not supported"
			unless is_key_supported($k);
		if ($k eq 'GENRE') {
			$v = ::genre($v);
			return "TRACK: $v not a valid GENRE (try --genre-list)"
				unless defined $v;
		}
		if ($k eq 'NUMBER') {
			return "TRACK: NUMBER $v yet defined"
				if exists $TAG{$v};
			return "TRACK: NUMBER $v does not exist"
				if (int($v) <= 0 || int($v) > @SRC_FILES);
		}
		::v("DBEntry::TRACK::set_tuple($k=$v)");
		if (exists $self->{$k}) {
			$self->{$k} = $v;
			push(@DBCONTENT, "$k = $v");
		} else {
			$self->{cast}->set_tuple($k, $v);
		}
		return undef;
	}
	sub finalize {
		my $self = shift;
		my $emsg = undef;
		unless (defined $self->{NUMBER} && defined $self->{TITLE}) {
			$emsg .= 'TRACK requires NUMBER and TITLE;';
		}
		my $em = $self->{cast}->finalize();
		$emsg .= $em if defined $em;

		DBEntry::_create_track_tag($self) unless defined $emsg;
		return $emsg;
	}
}
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=8 sts=8 sw=8 tw=79:
