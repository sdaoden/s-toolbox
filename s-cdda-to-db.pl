#!/usr/bin/env perl
require 5.008_001; # xxx I have forgotten why, i do not know whether it is true
my $SELF = 's-cdda-to-db';
my $ABSTRACT = 'Read and encode audio CDs, integrated in S-Music DB.';
#@ Web: https://www.sdaoden.eu/code.html
#@ Requirements:
#@ - s-cdda for CD-ROM access (https://ftp.sdaoden.eu/s-cdda-latest.tar.gz).
#@   P.S.: not on MacOS X/Darwin, but not tested there for many years
#@ - unless --no-volume-normalize is used: sox(1) (sox.sourceforge.net)
#@   NOTE: sox(1) changed - see $NEW_SOX below
#@ - if MP3 is used: lame(1) (www.mp3dev.org)
#@ - if MP4/AAC is used: faac(1) (www.audiocoding.com)
#@ - if Ogg/Vorbis is used: oggenc(1) (www.xiph.org)
#@ - if FLAC is used: flac(1) (www.xiph.org)
#@ - if OPUS is used: opusenc (see Vorbis TODO untested!)
#
# Copyright (c) 1998 - 2003, 2010 - 2014, 2016 - 2018,
#               2020 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
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

my $VERSION = '0.6.0';
my $CONTACT = 'Steffen Nurpmeso <steffen@sdaoden.eu>';

# MusicBrainz Web-Service; we use TLS if possible
my $MBRAINZ_URL = '://musicbrainz.org/ws/2';
my $MBRAINZ_AGENT = $SELF.'/'.$VERSION.' (https://www.sdaoden.eu/code.html)';

# New sox(1) (i guess this means post v14) with '-e signed-integer' instead of
# -s, '-b 16' instead of -w and -n (null device) instead of -e (to stop input
# file processing)
my $NEW_SOX = 1;

# Dito: change the undef to '/Desired/Path'
my $MUSIC_DB = defined $ENV{S_MUSIC_DB} ? $ENV{S_MUSIC_DB} : undef;
my $CDROM = defined $ENV{CDROM} ? $ENV{CDROM} : undef;
my $TMPDIR = (defined $ENV{TMPDIR} && -d $ENV{TMPDIR}) ? $ENV{TMPDIR} : '/tmp';
my $ED = defined $ENV{VISUAL} ? $ENV{VISUAL}
      : defined $ENV{EDITOR} ? $ENV{EDITOR} : '/usr/bin/vi';

# Only MacOS X
my $CDROMDEV = (defined $ENV{CDROMDEV} ? $ENV{CDROMDEV} #: undef;
      : defined $CDROM ? $CDROM : undef);

## -- >8 -- 8< -- ##

use diagnostics -verbose; # FIXME not in AlpineLinux
use warnings;
use strict;

use Digest;
use Encode;
use Getopt::Long;

# Genre list, alpha sorted {{{
my @Genres = (
   [ 123, 'A Cappella' ], [ 34, 'Acid' ], [ 74, 'Acid Jazz' ],
   [ 73, 'Acid Punk' ], [ 99, 'Acoustic' ], [ 20, 'Alternative' ],
   [ 40, 'Alt. Rock' ], [ 26, 'Ambient' ], [ 145, 'Anime' ],
   [ 90, 'Avantgarde' ], [ 116, 'Ballad' ], [ 41, 'Bass' ],
   [ 135, 'Beat' ], [ 85, 'Bebob' ], [ 96, 'Big Band' ],
   [ 138, 'Black Metal' ], [ 89, 'Bluegrass' ], [ 0, 'Blues' ],
   [ 107, 'Booty Bass' ], [ 132, 'BritPop' ], [ 65, 'Cabaret' ],
   [ 88, 'Celtic' ], [ 104, 'Chamber Music' ], [ 102, 'Chanson' ],
   [ 97, 'Chorus' ], [ 136, 'Christian Gangsta Rap' ],
   [ 61, 'Christian Rap' ], [ 141, 'Christian Rock' ],
   [ 32, 'Classical' ], [ 1, 'Classic Rock' ], [ 112, 'Club' ],
   [ 128, 'Club-House' ], [ 57, 'Comedy' ],
   [ 140, 'Contemporary Christian' ],
   [ 2, 'Country' ], [ 139, 'Crossover' ], [ 58, 'Cult' ],
   [ 3, 'Dance' ], [ 125, 'Dance Hall' ], [ 50, 'Darkwave' ],
   [ 22, 'Death Metal' ], [ 4, 'Disco' ], [ 55, 'Dream' ],
   [ 127, 'Drum & Bass' ], [ 122, 'Drum Solo' ], [ 120, 'Duet' ],
   [ 98, 'Easy Listening' ], [ 52, 'Electronic' ], [ 48, 'Ethnic' ],
   [ 54, 'Eurodance' ], [ 124, 'Euro-House' ], [ 25, 'Euro-Techno' ],
   [ 84, 'Fast-Fusion' ], [ 80, 'Folk' ], [ 115, 'Folklore' ],
   [ 81, 'Folk/Rock' ], [ 119, 'Freestyle' ], [ 5, 'Funk' ],
   [ 30, 'Fusion' ], [ 36, 'Game' ], [ 59, 'Gangsta Rap' ],
   [ 126, 'Goa' ], [ 38, 'Gospel' ], [ 49, 'Gothic' ],
   [ 91, 'Gothic Rock' ], [ 6, 'Grunge' ], [ 129, 'Hardcore' ],
   [ 79, 'Hard Rock' ], [ 137, 'Heavy Metal' ], [ 7, 'Hip-Hop' ],
   [ 35, 'House' ], [ 100, 'Humour' ], [ 131, 'Indie' ],
   [ 19, 'Industrial' ], [ 33, 'Instrumental' ],
   [ 46, 'Instrumental Pop' ], [ 47, 'Instrumental Rock' ],
   [ 8, 'Jazz' ], [ 29, 'Jazz+Funk' ], [ 146, 'JPop' ],
   [ 63, 'Jungle' ], [ 86, 'Latin' ], [ 71, 'Lo-Fi' ],
   [ 45, 'Meditative' ], [ 142, 'Merengue' ], [ 9, 'Metal' ],
   [ 77, 'Musical' ], [ 82, 'National Folk' ],
   [ 64, 'Native American' ],
   [ 133, 'Negerpunk' ], [ 10, 'New Age' ], [ 66, 'New Wave' ],
   [ 39, 'Noise' ], [ 11, 'Oldies' ], [ 103, 'Opera' ],
   [ 12, 'Other' ], [ 75, 'Polka' ], [ 134, 'Polsk Punk' ],
   [ 13, 'Pop' ], [ 53, 'Pop-Folk' ], [ 62, 'Pop/Funk' ],
   [ 109, 'Porn Groove' ], [ 117, 'Power Ballad' ], [ 23, 'Pranks' ],
   [ 108, 'Primus' ], [ 92, 'Progressive Rock' ],
   [ 67, 'Psychedelic' ], [ 93, 'Psychedelic Rock' ],
   [ 43, 'Punk' ], [ 121, 'Punk Rock' ], [ 15, 'Rap' ],
   [ 68, 'Rave' ], [ 14, 'R&B' ], [ 16, 'Reggae' ],
   [ 76, 'Retro' ], [ 87, 'Revival' ],
   [ 118, 'Rhythmic Soul' ], [ 17, 'Rock' ], [ 78, 'Rock & Roll' ],
   [ 143, 'Salsa' ], [ 114, 'Samba' ], [ 110, 'Satire' ],
   [ 69, 'Showtunes' ], [ 21, 'Ska' ], [ 111, 'Slow Jam' ],
   [ 95, 'Slow Rock' ], [ 105, 'Sonata' ], [ 42, 'Soul' ],
   [ 37, 'Sound Clip' ], [ 24, 'Soundtrack' ],
   [ 56, 'Southern Rock' ], [ 44, 'Space' ], [ 101, 'Speech' ],
   [ 83, 'Swing' ], [ 94, 'Symphonic Rock' ], [ 106, 'Symphony' ],
   [ 147, 'Synthpop' ], [ 113, 'Tango' ], [ 18, 'Techno' ],
   [ 51, 'Techno-Industrial' ], [ 130, 'Terror' ],
   [ 144, 'Thrash Metal' ], [ 60, 'Top 40' ], [ 70, 'Trailer' ],
   [ 31, 'Trance' ], [ 72, 'Tribal' ], [ 27, 'Trip-Hop' ],
   [ 28, 'Vocal' ]
); # }}}

my ($READ_ONLY, $ENC_ONLY, $NO_VOL_NORM, $VERBOSE) = (0, 0, 0, 0);
my ($CLEANUP_OK, $WORK_DIR, $TARGET_DIR) = (0);

sub main_fun{ # {{{
   # Do not check for the 'a' and 'A' subflags of -C, but only I/O related ones
   if(!(${^UNICODE} & 0x5FF) && ${^UTF8LOCALE}){
      print STDERR <<__EOT__;
WARNING WARNING WARNING
  Perl detected an UTF-8 (Unicode) locale, but it does NOT use UTF-8 I/O!
  It is very likely that this does not produce the results you desire!
  You should either invoke perl(1) with the -C command line option, or
  set a PERL5OPT environment variable, e.g., in a POSIX/Bourne/Korn shell:

    EITHER: \$ perl -C $SELF
    OR    : \$ PERL5OPT=-C; export PERL5OPT; $SELF
    (OR   : \$ PERL5OPT=-C $SELF)

  Please read the perlrun(1) manual page for more on this topic.
WARNING WARNING WARNING
__EOT__
   }

   # Also verifies we have valid (DB,TMP..) paths
   command_line();

   $SIG{INT} = sub {print STDERR "\nInterrupted ... bye\n"; exit 1};
   print "$SELF ($VERSION)\nPress ^C (CNTRL-C) at any time to interrupt\n";

   my ($info_ok, $needs_cddb) = (0, 1);
   # Unless we have seen --encode-only=ID
   unless(defined $CDInfo::CDId){
      CDInfo::discover();
      $info_ok = 1
   }

   $WORK_DIR = "$TMPDIR/$SELF.$CDInfo::CDId";
   $TARGET_DIR = "$MUSIC_DB/disc.${CDInfo::CDId}-";
   if(-d "${TARGET_DIR}1"){
      $TARGET_DIR = quick_and_dirty_dir_selector()
   }else{
      $TARGET_DIR .= '1'
   }
   print <<__EOT__;

S_MUSIC_DB target: $TARGET_DIR
WORKing directory: $WORK_DIR
(In worst-case error situations it may be necessary to remove those manually.)

__EOT__
   die 'Non-existent session cannot be resumed via --encode-only'
      if $ENC_ONLY && ! -d $WORK_DIR;
   unless(-d $WORK_DIR){
      die "Cannot create $WORK_DIR: $!" unless mkdir $WORK_DIR
   }
   unless($READ_ONLY || -d $TARGET_DIR){
      die "Cannot create $TARGET_DIR: $!" unless mkdir $TARGET_DIR
   }

   CDInfo::init_paths();
   MBDB::init_paths();

   # Get the info right, and maybe the database
   if(!$info_ok){
      CDInfo::read_data();
      $info_ok = -1
   }
   Title::create_that_many($CDInfo::TrackCount);

   if(-f $MBDB::FinalFile){
      die 'Database corrupted - remove TARGET and re-create entire disc'
         unless MBDB::db_read();
      $needs_cddb = 0
   }elsif($info_ok > 0){
      CDInfo::write_data()
   }

   if(!$READ_ONLY && $needs_cddb){
      CDInfo::InfoSource::query_all();
      MBDB::db_create()
   }

   # Handling files
   if($READ_ONLY || !$ENC_ONLY){
      user_tracks();
      Title::read_all_selected();
      print "\nUse --encode-only=$CDInfo::CDId to resume ...\n" if $READ_ONLY
   }elsif($ENC_ONLY){
      my @rawfl = glob("$WORK_DIR/*." . $CDInfo::ReadFileExt);
      die '--encode-only session on empty file list' if @rawfl == 0;
      foreach(sort @rawfl){
         die '--encode-only session: illegal filenames exist'
            unless /(\d+).${CDInfo::ReadFileExt}$/;
         my $i = int $1;
         die "\
--encode-only session: track $_ is unknown!
It does not seem to belong to this disc, you need to re-create it."
               unless $i > 0 && $i <= $CDInfo::TrackCount;
         my $t = $Title::List[$i - 1];
         $t->{IS_SELECTED} = 1
      }
      #print "\nThe following raw tracks will now be encoded:\n  ";
      #print "$_->{NUMBER} " foreach (@Title::List);
      #print "\n  Is this really ok?   You may interrupt now! ";
      #exit(5) unless user_confirm()
   }

   unless($READ_ONLY){
      Enc::calculate_volume_normalize($NO_VOL_NORM);
      Enc::encode_selected();
      $CLEANUP_OK = 1
   }

   exit 0
} # }}}

END {finalize() if $CLEANUP_OK}

# command_line + support {{{
sub command_line{
   Getopt::Long::Configure('bundling');

   my %opts = (
         'h|help|?' => sub {goto jdocu},
         'g|genre-list' => sub{
               printf("%3d %s\n", $_->[0], $_->[1]) foreach(@Genres);
               exit 0
               },

         'd|device=s' => \$CDROM,
         'e|encode-only=s' => \$ENC_ONLY,
         'f|formats=s' => sub {parse_formats($_[1])},
         'm|music-db=s' => \$MUSIC_DB,
         'r|read-only' => \$READ_ONLY,
         'no-volume-normalize' => \$NO_VOL_NORM,
         'v|verbose' => \$VERBOSE
         );
   if($^O eq 'darwin'){
      $opts{'cdromdev=s'} = \$CDROMDEV
   }

   my ($emsg) = (undef);
   unless(GetOptions(%opts)){
      $emsg = 'Invocation failure';
      goto jdocu
   }

   if($ENC_ONLY){
      if($READ_ONLY){
         $emsg = '--read-only and --encode-only are mutual exclusive';
         goto jdocu
      }
      if($ENC_ONLY !~ /[[:alnum:]]+/){
         $emsg = "$ENC_ONLY is not a valid CD(DB)ID";
         goto jdocu
      }
      $CDInfo::CDId = lc $ENC_ONLY;
      $ENC_ONLY = 1
   }

   unless($READ_ONLY){
      $MUSIC_DB = glob $MUSIC_DB if defined $MUSIC_DB;
      unless(defined $MUSIC_DB && -d $MUSIC_DB && -w _){
         $emsg = '-m / $S_MUSIC_DB directory not accessible';
         goto jdocu
      }

      if(!Enc::format_has_any() && defined(my $v = $ENV{S_MUSIC_FORMATS})){
         parse_formats($v)
      }
      unless(Enc::format_has_any()){
         $emsg = 'No audio formats given via -f or $S_MUSIC_FORMATS';
         goto jdocu
      }
   }

   $TMPDIR = glob $TMPDIR if defined $TMPDIR;
   unless(defined $TMPDIR && -d $TMPDIR && -w _){
      $emsg = "The given TMPDIR is somehow not accessible";
      goto jdocu
   }

   return;

jdocu:
   my $FH = defined $emsg ? *STDERR : *STDOUT;

   my $flr = Enc::format_list();
   $flr = join ',', @$flr;
   print $FH <<__EOT__;
$SELF ($VERSION): $ABSTRACT

 $SELF -h|--help  |  -g|--genre-list

 $SELF [-v] [-d DEV] [-f|--formats ..] [-m|--music-db PATH]
      [--no-volume-normalize]
   Do all the entire processing in one run
 $SELF [-v] [-d DEV] -r|--read-only
   Only read audio tracks from CD-ROM to temporary work directory
 $SELF [-v] [-f|--formats ..] [-m|--music-db PATH]
      [--no-volume-normalize] -e|--encode-only CDID
   Only resume a --read-only session

-d|--device DEV       Use CD-ROM DEVice; else \$CDROM; else s-cdda(1) fallback
-e|--encode-only CDID Resume --read-only session; it echoed the CDID to use
-f|--formats LIST     Comma-separated audio format list; else \$S_MUSIC_FORMATS
                      ($flr)
-m|--music-db PATH    S-Music DB directory; else \$S_MUSIC_DB
-r|--read-only        Only read data, then exit; resume with --encode-only
--no-volume-normalize Do not apply volume normalization
-v|--verbose          Be more verbose; does not delete temporary files!

. Honours \$TMPDIR, \$VISUAL (or \$EDITOR; environment variables).
. Bugs/Contact via $CONTACT
__EOT__

   if($^O eq 'darwin'){
      print $FH <<__EOT__;
MacOS only:  WARNING - Mac OS not tried after (s-cdda(1) based) rewrite!
--cdromdev SPEC
   Maybe needed in addition to \$CDROM; here SPEC is a simple drive number,
   for example 1.  Whereas --cdrom= is used for -drive option of drutil(1),
   --cdromdev= is for raw </dev/disk?> access.  Beware that these may not
   match, and also depend on usage order of USB devices.  The default settings
   come from the \$CDROMDEV environment variable
__EOT__
   }

   print $FH "\n! $emsg\n" if defined $emsg;
   exit defined $emsg ? 1 : 0
}

sub parse_formats{
   my ($v) = @_;

   while($v =~ /^,?\s*(\w+)\s*(,.*)?$/){
      $v = defined $2 ? $2 : '';
      die "Unknown audio encoding format: $1" unless Enc::format_add($1)
   }
}
# }}}

# v, genre, genre_id, finalize, user_confirm {{{
sub v{
   return unless $VERBOSE > 0;
   print STDOUT '-V  ', shift, "\n";
   while(@_ != 0) {print STDOUT '-V  ++ ', shift, "\n"};
   1
}

sub genre{
   my $g = shift;
   if($g =~ /^(\d+)$/){
      $g = $1;
      foreach my $tr (@Genres){
         return $tr->[1] if $tr->[0] == $g
      }
   }else{
      $g = lc $g;
      foreach my $tr (@Genres){
         return $tr->[1] if lc($tr->[1]) eq $g
      }
   }
   undef
}

sub genre_id{
   my $g = shift;
   foreach my $tr (@Genres){
      return $tr->[0] if $tr->[1] eq $g
   }
   # (Used only for valid genre-names)
}

# (Called by END{} only if $CLEANUP_OK)
sub finalize{
   if($VERBOSE){
      v("--verbose mode: NOT removing $WORK_DIR");
      return
   }
   print "\nRemoving temporary $WORK_DIR\n";
   unlink $CDInfo::DatFile, $MBDB::EditFile; # XXX
   foreach(@Title::List){
      next unless -f $_->{RAW_FILE};
      die "Cannot unlink $_->{RAW_FILE}: $!" unless unlink $_->{RAW_FILE}
   }
   die "rmdir $WORK_DIR failed: $!" unless rmdir $WORK_DIR
}

sub user_confirm{
   my $save = $|;
   $| = 1;
   print ' [^[Nn]* (or else)] ';
   my $u = <STDIN>;
   $| = $save;
   chomp $u;
   ($u =~ /^n/i) ? 0 : 1
}
# }}}

sub quick_and_dirty_dir_selector{ # {{{
   my @dlist = glob "${TARGET_DIR}*/music.db";
   return "${TARGET_DIR}1" if @dlist == 0;
   print <<__EOT__;

CD(DB)ID clash detected!
Either (1) the disc is not unique
or (2) you are trying to extend/replace some files of a yet existent disc.
(Note that the temporary WORKing directory will clash no matter what you do!)
Here is a list of yet existent albums which match that CDID:
__EOT__

   my ($i, $usr);
   for($i = 1; $i <= @dlist; ++$i){
      my $d = "${TARGET_DIR}$i";
      my $f = "$d/music.db";
      unless(open F, '<:encoding(UTF-8)', $f){
         print "  [] Skipping due to failed open: $f\n";
         next
      }
      my ($ast, $at, $tr) = (undef, undef, undef);
      while(<F>){
         if(/^\s*\[ALBUMSET\]\s*$/) {$tr = \$ast}
         elsif(/^\s*\[ALBUM\]\s*$/) {$tr = \$at}
         elsif(/^\s*\[CDDB\]\s*$/) {next}
         elsif(/^\s*\[\w+\]\s*$/) {last}
         elsif(defined $tr && /^\s*TITLE\s*=\s*(.+?)\s*$/) {$$tr = $1}
      }
      die "Cannot close $f: $!" unless close F;
      unless(defined $at){
         print "  [] No TITLE entry in $f!\n  ",
            "Disc data seems corrupted and must be re-created!\n";
         next
      }
      $at = "$ast - $at" if defined $ast;
      print "  [$i] $at\n"
   }
   print "  [0] None of these - the disc should create a new entry!\n";

jREDO:
   print "  Choose the number to use: ";
   $usr = <STDIN>;
   chomp $usr;
   unless($usr =~ /^\d+$/ && ($usr = int $usr) >= 0 && $usr <= @dlist){
      print "!  I am expecting one of the [numbers] ... !\n";
      goto jREDO
   }
   if($usr == 0){
      print "  .. forced to create a new disc entry\n";
      return "${TARGET_DIR}$i"
   }else{
      print "  .. forced to resume an existent album\n";
      return "${TARGET_DIR}$usr"
   }
} # }}}

sub user_tracks{ # {{{
   print "Disc $CDInfo::CDId contains $CDInfo::TrackCount songs - ",
         'shall all be read?';
   if(user_confirm()){
      print "  Whee - all songs will be read!\n";
      $_->{IS_SELECTED} = 1 foreach (@Title::List);
      return
   }

   my ($line, @dt);
jREDO:
   print '  Please enter a space separated list of the desired track numbers',
         "\n  ";
   $line = <STDIN>;
   chomp $line;
   @dt = split /\s+/, $line;
   print "  Is this list correct <", join(' ', @dt), '>';
   goto jREDO unless user_confirm();
   unless(@dt){
      print "? So why are you using an audio CD reader, then?\n";
      exit 42
   }
   foreach(@dt){
      if($_ == 0 || $_ > $CDInfo::TrackCount){
         print "! Invalid track number: $_!\n\n";
         goto jREDO
      }
   }

   $Title::List[$_ - 1]->{IS_SELECTED} = 1 foreach(@dt)
} # }}}

{package CDInfo; # {{{
   our ($RawIsWAVE, $ReadFileExt) = (0, 'raw');
   # Id field may also be set from command_line()
   # Mostly set by _calc_id() or parse() only
   our ($CDId, $MBrainzDiscId, $MCN,
      $TrackCount, $TrackFirst, $TrackLast,
      $FileReader, $DatFile);
   our @TracksLBA = ();
   our @TracksISRC = ();
   our @CDText = ();
   my $DevId;
   my $Leadout = 0xAA;

   sub init_paths{
      $DatFile = "$WORK_DIR/cdinfo.dat"
   }

   sub discover{
      no strict 'refs';
      die "! System $^O not supported" unless defined *{"CDInfo::_os_$^O"};
      print "\nCDInfo: assuming an Audio-CD is in the drive ...\n";

      my $i = &{"CDInfo::_os_$^O"}();
      if(defined $i){
         print $i,
            "! Unable to collect CD Table-Of-Contents\n",
            "! This may mean the Audio-CD was not yet fully loaded\n",
            "! It can also happen for copy-protection .. or whatever\n";
         exit 1
      }

      print "  CD(DB) ID: $CDId  |  MusicBrainz Disc ID: ",
         $MBrainzDiscId, "\n  ",
         'Track L(ogical)B(lock)A(ddressing)s: ' . join(' ', @TracksLBA),
         "\n  Track: count $TrackCount, first $TrackFirst, ",
         "last $TrackLast\n"
   }

   sub _os_darwin{ # {{{
      my $drive = defined $CDROM ? $CDROM : 1;
      $DevId = defined $CDROMDEV ? $CDROMDEV : $drive;
      print "  Darwin/Mac OS X: drive $drive and /dev/disk$DevId\n",
         "  !! WARNING: Darwin/MAC OS X not tested for a long time!\n";

      $FileReader = sub{
         my $title = shift;
         my ($inf, $outf, $byteno, $blckno, $buf, $err) =
               (undef, undef, undef, 0, 0, undef, undef);
         $inf = '/dev/disk' . $DevId . 's' . $title->{NUMBER};
         $outf = $title->{RAW_FILE};

         return "! Cannot open for reading: $inf: $!\n"
            unless open INFH, '<', $inf;
         # (Yet-exists case handled by caller)
         unless(open OUTFH, '>', $outf){
            $err = $!;
            close INFH;
            return "! Cannot open for writing: $outf: $err\n"
         }
         unless(binmode(INFH) && binmode(OUTFH)){
            close OUTFH;
            close INFH;
            return "! Failed to set binary mode for $inf and/or $outf\n"
         }

         while(1){
            my $r = sysread INFH, $buf, 2352 * 20;
            unless(defined $r){
               $err = "! I/O read failed: $!\n";
               last
            }
            last if $r == 0;
            $byteno += $r;
            $blckno += $r / 2352;

            for(my $o = 0;  $r > 0; ){
               my $w = syswrite OUTFH, $buf, $r, $o;
               unless(defined $w){
                  $err = "! I/O write failed: $!\n";
                  goto jdarwin_read_stop
               }
               $o += $w;
               $r -= $w
            }
         }

jdarwin_read_stop:
         close OUTFH; # XXX errors?
         close INFH; # XXX errors?
         return $err if defined $err;
         print "    .. stored $blckno blocks ($byteno bytes)\n";
         return undef
      };

      # Problem: this non-UNIX thing succeeds even without media...
      ::v("Invoking drutil(1) -drive $drive toc");
      sleep 1;
      my $l = `drutil -drive $drive toc`;
      return "! Drive $drive: failed reading TOC: $!\n" if $?;
      my @res = split "\n", $l;

      my (@cdtoc, $leadout, $leadout_lba);
      ($TrackFirst, $TrackLast) = (0xFF, 0x00);
      for(;;){
         $l = shift @res;
         return "! Drive $drive: no lead-out information found\n"
            unless defined $l;
         if($l =~ /^\s*Lead-out:\s+(\d+):(\d+)\.(\d+)/){
            $leadout_lba = ((($1 * 60 + $2) * 75) + $3) - 150;
            $leadout = "$Leadout $1 $2 $3";
            last
         }
      }
      for(my $li = 0;; ++$li){
         $l = shift @res;
         last unless defined $l;
         last unless $l =~ /^\s*Session\s+\d+,\s+Track\s+(\d+):
               \s+(\d+):(\d+)\.(\d+)
               .*/x;
         return "! Drive $drive: corrupted TOC: $1 follows $li\n"
            unless $1 == $li + 1;
         $TrackFirst = $1 if $1 < $TrackFirst;
         $TrackLast= $1 if $1 > $TrackLast;
         push @cdtoc, "$1 $2 $3 $4";
         push @TracksLBA, ((($2 * 60 + $3) * 75) + $4) - 150
      }
      return "! Drive $drive: no track information found\n" unless @cdtoc > 0;
      push @cdtoc, $leadout;
      push @TracksLBA, $leadout_lba;

      my $emsg = _check_cddb_state('');
      return $emsg if length $emsg;

      _calc_cdid(\@cdtoc);
      return undef
   } # }}}

   # OSs for s-cdda {{{
   sub _os_dragonfly {return _os_via_scdda('DragonFly BSD')}
   sub _os_freebsd {return _os_via_scdda('FreeBSD')}
   sub _os_linux {return _os_via_scdda('Linux')}
   sub _os_netbsd {return _os_via_scdda('NetBSD')}
   sub _os_openbsd {return _os_via_scdda('OpenBSD')}

   sub _os_via_scdda{
      ($RawIsWAVE, $ReadFileExt) = (1, 'wav');

      my ($dev, $l, @res, @cdtoc);

      print '  ', shift, ': ';
      if(defined $CDROM){
         $dev = "-d $CDROM";
         print "device $CDROM"
      }else{
         $dev = '';
         print 'using S-cdda(1) default device'
      }
      print "\n";

      $FileReader = sub{
         my $title = shift;
         return undef if 0 == system("s-cdda $dev " . ($VERBOSE ? '-v ' : '') .
            '-r ' .  $title->{NUMBER} . ' > ' .  $title->{RAW_FILE});
         return "! Device $dev: cannot read track $title->{NUMBER}: $?\n"
      };

      $l = 's-cdda ' . $dev . ($VERBOSE ? ' -v' : '');
      ::v("Invoking $l");

      $l = `$l`;
      $dev .= length $dev ? ': f' : 'F';
      return "! ${dev}ailed reading TOC: $?/$!\n" if $?;
      @res = split "\n", $l;

      my ($emsg, $had_leadout) = ('', 0);
      for(;;){
         $l = shift @res;
         last unless defined $l;
         if($l =~ /^t=(\d+)\s+
               t\d+_msf=(\d+):(\d+).(\d+)\s+
               t\d+_lba=(\d+)\s+
               .*$/x){
            my ($tno, $mm, $ms, $mf, $lba) = ($1, $2, $3, $4, $5);

            $emsg .= "! Corrupted: lead-out not last entry\n" if $had_leadout;
            if($tno < 1){
               $emsg .= "! Corrupted: invalid track number: $tno\n";
               next
            }
            $cdtoc[$tno - 1] = "$tno $mm $ms $mf";
            $TracksLBA[$tno - 1] = $lba
         }elsif($l =~ /^t=0\s+t0_msf=(\d+):(\d+).(\d+)\s+t0_lba=(\d+)$/){
            my ($mm, $ms, $mf, $lba) = ($1, $2, $3, $4);

            $had_leadout = 1;
            push @cdtoc, "$Leadout $mm $ms $mf";
            push @TracksLBA, $lba
         }elsif($l =~ /^t0_count=(\d+)\s+
               t0_track_first=(\d+)\s+
               t0_track_last=(\d+)/x){
            ($TrackCount, $TrackFirst, $TrackLast) = ($1, $2, $3)
         }elsif($l =~ /^t0_mcn=(\w+)\s*$/){ # (just take the content!)
            $MCN = $1
         }elsif($l =~ /^t(\d+)_isrc=(\w+)\s*$/){ # (just take the content!)
            $TracksISRC[$1 - 1] = $2
         }
         # We ignore the ^x ones, we only look for audio "t"rack data
         elsif($l =~ /^x=(\d+)\s+.*$/){
         }elsif($l =~ /^x0_count=(\d+)\s+
               x0_track_first=(\d+)\s+
               x0_track_last=(\d+)
               .*$/x){
         }elsif($l =~ /^#/){
            push @CDText, $l
         }else{
            #$emsg .= "! Invalid line: $l\n"
         }
      }
      $emsg .= "! No Lead-out information encountered\n" unless $had_leadout;
      $emsg = _check_cddb_state($emsg);
      return $emsg if length $emsg;

      _calc_cdid(\@cdtoc);
      _calc_mb_discid();
      return undef
   } # }}}

   # Calculated CD(DB)-Id and *set*CDInfo*fields*, ditto MusicBrainz Disc ID
   sub _calc_cdid{ # {{{
      # This is a stripped down version of CDDB.pm::calculate_id()
      my $cdtocr = shift;
      my ($sec_first, $sum, $totalsecs);
      foreach(@$cdtocr){
         # MSF - minute, second, 1/75 second=frame (RedBook standard)
         # CDDB/FreeDB calculation actually uses "wrong" numbers in that it
         # adds the 2 seconds offset (see SCSI MMC-3 standard, Table 333 - LBA
         # to MSF translation)
         my ($no, $min, $sec, $frame) = split /\s+/, $_, 4;
         my $frame_off = (($min * 60 + $sec) * 75) + $frame;
         my $sec_begin = int($frame_off / 75);
         $sec_first = $sec_begin unless defined $sec_first;
         if($no == $Leadout){
            $totalsecs = $sec_begin;
            last
         }
         map {$sum += $_} split //, $sec_begin;
      }
      $CDId = sprintf("%02x%04x%02x",
            $sum % 255, $totalsecs - $sec_first, $TrackCount)
   }

   sub _calc_mb_discid{
      my $d = Digest->new("SHA-1");
      $d->add(sprintf '%02X', $TrackFirst);
      $d->add(sprintf '%02X', $TrackLast);

      my $i = @TracksLBA;
      $d->add(sprintf '%08X', $TracksLBA[--$i] + 150);
      for(my $j = 0; $j < $i; ++$j){
         $d->add(sprintf '%08X', $TracksLBA[$j] + 150)
      }
      for(++$i; $i < 100; ++$i){
         $d->add('00000000')
      }
      $d = $d->b64digest();
      $d =~ tr[/+=][_.-];
      $MBrainzDiscId = $d . '-'
   } # }}}

   # write_data, read_data ($DatFile handling) {{{
   sub write_data{
      my $f = $DatFile;
      ::v("CDInfo::write_data($f)");
      die "Cannot open $f: $!" unless open DAT, '>:encoding(UTF-8)', $f;
      die "Error writing $f: $!"
         unless print DAT "# $SELF CDDB info for project $CDId\n",
         "# Do not modify!   Or project needs to be re-created!!\n",
         "CDID = $CDId\n",
         "MBRAINZ_DISC_ID = $MBrainzDiscId\n",
         'TRACKS_LBA = ', join(' ', @TracksLBA), "\n",
         "TRACK_FIRST = $TrackFirst\n",
         "TRACK_LAST = $TrackLast\n",
         "RAW_IS_WAVE = 1\n";
      if(@CDText > 0){
         die "Error writing $f: $!"
            unless print DAT "# CDTEXT-START\n", join("\n", @CDText)
      }
      die "Cannot close $f: $!" unless close DAT
   }

   sub read_data{
      my $f = $DatFile;
      ::v("CDInfo::read_data($f)");
      die "Cannot open $f: $!.\n" .
            "I cannot continue - remove $WORK_DIR and re-create!"
         unless open DAT, '<:encoding(UTF-8)', $f;
      my @lines = <DAT>;
      die "Cannot close $f: $!" unless close DAT;

      # It may happen that this is called even though discover()
      # already queried the disc in the drive - nevertheless: resume!
      my ($old_id, $laref) = ($CDId, shift);
      $RawIsWAVE = $ReadFileExt = $CDId = $MBrainzDiscId =
            $TrackCount = $TrackFirst = $TrackLast = undef;
      @TracksLBA = @TracksISRC = @CDText = ();

      my ($emsg, $cdtext) = ('', 0);
      foreach(@lines){
         chomp;

         if(/^\s*#/){
            if(!$cdtext){
               $cdtext = 1 if /CDTEXT-START/;
            }else{
               push @CDText, $_
            }
            next
         }

         next if /^\s*$/;

         unless(/^\s*(.+?)\s*=\s*(.+?)\s*$/){
            $emsg .= "! Invalid line $_\n";
            next
         }
         my ($k, $v) = ($1, $2);

         if($k eq 'CDID'){
            if(defined $old_id && $v ne $old_id){
               $emsg .= "! Parsed CDID ($v) does not match\n";
               next
            }
            $emsg .= "! Invalid CDID: $v\n" unless $v =~ /^([[:xdigit:]]+)$/;
            $CDId = $v
         }elsif($k eq 'MBRAINZ_DISC_ID'){
            $emsg .= "! Invalid MBRAINZ_DISC_ID: $v\n"
                  unless $v =~ /^([[:alnum:]_.-]+)$/;
            $MBrainzDiscId = $v
         }elsif($k eq 'TRACKS_LBA'){
            my @x = split(/\s+/, $v);
            @TracksLBA = map {return () unless /^(\d+)$/; $_} @x;
            $emsg .= "! Invalid TRACKS_LBA entries: $v\n" if @x != @TracksLBA;
            $TrackCount = @TracksLBA - 1
         }elsif($k eq 'TRACK_FIRST'){
            $emsg .= "! Invalid TRACK_FIRST: $v\n" unless $v =~ /^(\d+)$/;
            $TrackFirst = $1
         }elsif($k eq 'TRACK_LAST'){
            $emsg .= "! Invalid TRACK_LAST: $v\n" unless $v =~ /^(\d+)$/;
            $TrackLast = $1
         }elsif($k eq 'RAW_IS_WAVE'){
            $emsg .= "! Invalid RAW_IS_WAVE: $v\n" unless $v =~ /^(\d)$/;
            $ReadFileExt = ($RawIsWAVE = $1) ? 'wav' : 'raw'
         }else{
            $emsg .= "! Invalid line: $_\n"
         }
      }
      $emsg .= "! Corrupted: no CDID seen\n" unless defined $CDId;
      $emsg .= "! Corrupted: no MBRAINZ_DISC_ID seen\n"
            unless defined $MBrainzDiscId;
      $emsg = _check_cddb_state($emsg);
      die "CDInfo: $emsg" if length $emsg;

      print "  CD(DB) ID: $CDId  |  MusicBrainz Disc ID: ",
         $MBrainzDiscId, "\n  ",
         'Track L(ogical)B(lock)A(ddressing)s: ' . join(' ', @TracksLBA),
         "\n  Track: count $TrackCount, first $TrackFirst, last $TrackLast\n"
   }

   sub _check_cddb_state{
      my ($emsg) = @_;
      $emsg .= "! Corrupted: no TRACK_COUNT seen\n" unless defined $TrackCount;
      $emsg .= "! Corrupted: no TRACK_FIRST seen\n" unless defined $TrackFirst;
      $emsg .= "! Corrupted: no TRACK_LAST seen\n" unless defined $TrackLast;
      $emsg .= "! Corrupted: no TRACKS_LBA seen\n" unless $TrackCount > 0;
      $emsg .= "! Corrupted: no RAW_IS_WAVE seen\n" unless defined $RawIsWAVE;
      if(@Title::List > 0){
         $emsg .= "! Corrupted: TRACKS_LBA invalid\n"
            if $TrackCount != @Title::List
      }
      return $emsg
   }
   # }}}

{package CDInfo::InfoSource; # {{{
   sub query_all{
      CDInfo::InfoSource::Dummy::new()->create_db();
      if(@CDInfo::CDText > 0){
         CDInfo::InfoSource::CDText::new()->create_db()
      }
      if(defined $CDInfo::MBrainzDiscId){
         CDInfo::InfoSource::MusicBrainz::new()->create_db()
      }
   }

   # Super funs # {{{
   sub new{
      my ($name) = @_;
      my $self = scalar caller;
      $self = {name => $name};
      bless $self
   }
   # }}}

{package CDInfo::InfoSource::Dummy; # {{{
   our @ISA = 'CDInfo::InfoSource';

   sub new{
      my $self = CDInfo::InfoSource::new('Dummy');
      $self = bless $self;
      #$self
   }

   sub create_db{
      my $self = $_[0];
      my @data = split "\n", <<__EOT__;
[CDDB]
CDID = $CDInfo::CDId
MBRAINZ_DISC_ID = $CDInfo::MBrainzDiscId
TRACKS_LBA = @CDInfo::TracksLBA
TRACK_FIRST = $CDInfo::TrackFirst
TRACK_LAST = $CDInfo::TrackLast
[ALBUM]
TITLE = UNTITLED
TRACK_COUNT = $CDInfo::TrackCount
GENRE = Humour
[CAST]
ARTIST = UNKNOWN
__EOT__

      foreach my $t (@Title::List){
         push @data, $_ foreach(split "\n", <<__EOT__);
[TRACK]
NUMBER = $t->{NUMBER}
TITLE = UNTITLED
__EOT__
      }

      MBDB::db_slurp('Dummy', \@data)
   }
} # }}} CDInfo::InfoSource::Dummy

{package CDInfo::InfoSource::CDText; # {{{
   our @ISA = 'CDInfo::InfoSource';

   sub new{
      my $self = CDInfo::InfoSource::new('CDText');
      $self = bless $self;
      #$self
   }

   sub create_db{
      my $self = $_[0];
      my @data;
      foreach(@CDInfo::CDText){
         push @data, substr($_, 1)
      }
      MBDB::db_slurp('CDText', \@data)
   }
} # }}} CDInfo::InfoSource::CDText

{package CDInfo::InfoSource::MusicBrainz; # {{{
   our @ISA = 'CDInfo::InfoSource';

   sub new{
      my $self = CDInfo::InfoSource::new('MusicBrainz');
      $self = bless $self;
      #$self
   }

   sub create_db{ # {{{
      my $self = $_[0];

      eval{
         require HTTP::Tiny;
         require XML::Parser
      };
      if($@){
         print
            "! Failed loading HTTP::Tiny and/or XML::Parser perl module(s).\n",
            "!   We could use the MusicBrainz CD information Web-Service.\n",
            "!   Are they installed?  (Install them via CPAN?)\n",
            '!   Confirm to again try to use them, otherwise we skip this: ';
         return unless user_confirm();
         return $self->create_db()
      }

      print
         "\nShall i try to contact the MusicBrainz Web-Service in order to\n",
         '  collect more data of the audio CD? ';
      return unless ::user_confirm();

      $self->{_protocol} = ($self->{_use_ssl} = HTTP::Tiny::can_ssl())
            ? 'https' : 'http';
      $self->{_headers} = {
            'Accept' => 'application/xml',
            'Content-Type' => 'application/xml'
         };

      my $res = $self->_http_request('/discid/' . $CDInfo::MBrainzDiscId .
            '?inc=artist-credits+recordings');
      unless(defined $res &&
            CDInfo::InfoSource::MusicBrainz::XEN::slurp_xml(\$res) > 0 &&
            defined($res = $self->_xml_vaporise())){
         print '! Continue without MusicBrainz data? ';
         exit 5 unless ::user_confirm();
         return
      }

      # Turn it into something our DB can swallow
      $res = $$res;
      my @data;

      push @data, '[ALBUM]';
      push @data, 'TITLE = ' . $res->{_title};
      push @data, 'TRACK_COUNT = ' . $CDInfo::TrackCount;
      push @data, 'MBRAINZ_ID = ' . $res->{_id};
      push @data, 'YEAR = ' . $res->{_date} if defined $res->{_date};

      if(@{$res->{_cast}} > 0){
         push @data, '[CAST]';
         foreach my $ar (@{$res->{_cast}}){
            push @data, $ar->[0] . ' = ' . $ar->[1]
         }
      }

      foreach my $ar (@{$res->{_tracks}}){
         push @data, '[TRACK]';
         push @data, 'NUMBER = ' . $ar->{_number};
         push @data, 'TITLE = ' . $ar->{_title};
         push @data, 'YEAR = ' . $ar->{_date} if defined $ar->{_date};
         push @data, 'MBRAINZ_ID = ' . $ar->{_id} if defined $ar->{_id};
         foreach my $ar2 (@{$ar->{_cast}}){
            push @data, $ar2->[0] . ' = ' . $ar2->[1]
         }
         push @data, 'COMMENT = ' . $ar->{_comment} if defined $ar->{_comment}
      }

      MBDB::db_slurp('MusicBrainz', \@data)
   } # }}}

   sub _http_request{ # {{{
      my ($self, $req) = @_;

      my $httpt = HTTP::Tiny->new(
            agent => $MBRAINZ_AGENT,
            default_headers => $self->{_headers},
            verify_SSL => $self->{_use_ssl}
            );

      my $url = $self->{_protocol} . $MBRAINZ_URL . $req;
      my $response = $httpt->get($url);

      unless($response->{success}){
         print "! MusicBrainz query not successful:\n",
            "!  Status $response->{status}, reason $response->{reason}\n";
         return undef
      }
      unless(length $response->{content}){
         print "! MusicBrainz query returned empty result\n";
         return undef
      }
      return $response->{content}
   } # }}}

   sub _xml_vaporise{ # {{{
      my $self = $_[0];
      my (@resa, $sectors);

      # XEN has vaporised the result to only Id-matching discs, there still
      # could be duplicates however, so apply more tests
      # xxx Validity tests seem strange though
      $sectors = $CDInfo::TracksLBA[$CDInfo::TrackCount] + 150;

jOUT: foreach my $d (@CDInfo::InfoSource::MusicBrainz::XEN::POI){
         foreach my $c (@{$d->{children}}){
            if($c->{name} eq 'sectors'){
               # <sectors> -> leadout
               next jOUT if $c->{data} + 0 != $sectors
            }elsif($c->{name} eq 'offset-list'){
               # List of track numbers and bent LBA offsets
               next jOUT unless exists $c->{attrs}{count} &&
                  $c->{attrs}{count} + 0 == $CDInfo::TrackCount;

               foreach my $cc (@{$c->{children}}){
                  next jOUT unless defined $cc->{data};
                  next jOUT unless exists $cc->{attrs}{position};
                  my $i = $cc->{attrs}{position} + 0;
                  next jOUT unless $i > 0 && $i <= $CDInfo::TrackCount;
                  --$i;
                  next jOUT unless $cc->{data} - 150 == $CDInfo::TracksLBA[$i];
               }
            }
         }

         # Then check whether we have all the data to use this entry, for that
         # go up first to find a <track-list>, then to its actual <release>..
         my ($p, $tl) = ($d->{parent}, undef);
         die 'IMPLERR' unless $p->{name} eq 'disc-list';
         for(;; $p = $p->{parent}){
            next jOUT unless defined $p;
            if($p->{name} eq 'medium'){
               foreach my $c (@{$p->{children}}){
                  if($c->{name} eq 'track-list'){
                     next jOUT unless exists $c->{attrs}{count} &&
                        $c->{attrs}{count} + 0 == $CDInfo::TrackCount;
                     $tl = $c;
                     last
                  }
               }
            }elsif($p->{name} eq 'release'){
               last
            }
         }
         next jOUT unless exists $p->{attrs}{id};
         next jOUT unless defined $tl;

         # ..and find the data we are interested in.  Now that s...s
         $d->{_id} = $p->{attrs}{id};
         $d->{_barcode} = $d->{_country} = $d->{_date} = $d->{_title} = undef;
         $d->{_cast} = [];
         $d->{_tracks} = [];
         @{$d->{_tracks}}[$CDInfo::TrackCount - 1] = undef;

         foreach my $c (@{$p->{children}}){
            if($c->{name} eq 'artist-credit'){
               $self->__xml_artist_credit(undef, \$d, $c)
            #}elsif($c->{name} eq 'asin'){
            #   $d->{_asin} $c->{data} if defined $c->{data}
            }elsif($c->{name} eq 'barcode'){
               $d->{_barcode} = $c->{data} if defined $c->{data}
            }elsif($c->{name} eq 'country'){
               $d->{_country} = $c->{data} if defined $c->{data}
            }elsif($c->{name} eq 'date'){
               $d->{_date} = $1 if defined $c->{data} &&
                     $c->{data} =~ /^\s*(\d{4})(?:-.+)?$/
            }elsif($c->{name} eq 'title'){
               $d->{_title} = $c->{data} if defined $c->{data}
            }
         }
         next jOUT unless $self->__xml_track_list(\$d, $tl) != 0;

         push @resa, $d
      }

      return undef if @resa == 0;
      return undef if @resa > 1 && $self->__xml_choose(\@resa) == 0;
      \$resa[0]
   } # }}}

   sub __xml_artist_credit{ # {{{
      my ($self, $outerdr, $dr, $c) = @_;

      foreach my $cc (@{$c->{children}}){
         next unless $cc->{name} eq 'name-credit';
         foreach my $ccc (@{$cc->{children}}){
            if($ccc->{name} eq 'artist'){
               next unless $ccc->{attrs}{type};

               my $i = lc $ccc->{attrs}{type};
               my ($t, $pn, $n, $s, $w) =
                     ('ARTIST', undef, undef, undef, undef);

               foreach my $cccc (@{$ccc->{children}}){
                  next unless defined $cccc->{data} &&
                     length $cccc->{data} > 0;

                  if($cccc->{name} eq 'name'){
                     $pn = $n = $cccc->{data}
                  }elsif($cccc->{name} eq 'sort-name'){
                     $s = $cccc->{data}
                  }elsif($cccc->{name} eq 'disambiguation'){
                     my $j = $cccc->{data};
                     next unless defined $j;
                     $j = lc $j;
                     if($j eq 'conductor'){
                        $t = 'CONDUCTOR'
                     }elsif($j =~ 'composer'){
                        $t = 'COMPOSER'
                     }elsif($i eq 'person' && $j =~ /^\s*\w+\s*$/){
                        $w = $cccc->{data};
                        $t = 'SOLOIST'
                     }elsif($$dr->{name} eq 'track'){
                        $$dr->{_comment} = "Artist: $cccc->{data}"
                     }
                  }
               }
               next unless defined $n;
               $t = 'ARTIST' if $i eq 'orchestra';

               # But do not duplicate data (TODO should be DB thing)
               $n = "$n ($w)" if defined $w;
               if(defined $outerdr){
                  foreach(@{$$outerdr->{_cast}}){
                     if($_->[0] eq $t && $_->[1] eq $n){
                        $n = undef;
                        last
                     }
                  }
               }
               push @{$$dr->{_cast}}, [$t, $n] if defined $n;

               if(defined $s){
                  if(defined $outerdr){
                     foreach(@{$$outerdr->{_cast}}){
                        if($_->[0] eq 'SORT' && $_->[1] eq $s){
                           $s = undef;
                           last
                        }
                     }
                  }
                  push @{$$dr->{_cast}}, ['SORT', "$s ($pn)"]
                     if defined $s && defined $pn && $pn ne $s
               }
            }
         }
      }
   } # }}}

   sub __xml_track_list{ # {{{
      my ($self, $dr, $tl) = @_;

      foreach my $t (@{$tl->{children}}){
         my $have_rec = 0;
         foreach my $c (@{$t->{children}}){
            # TODO MusicBrainz per-track DATE (year)?
            if($c->{name} eq 'position'){
               my $i = $c->{data};
               return 0 unless defined $i &&
                  $i > 0 && $i <= $CDInfo::TrackCount;
               $t->{_number} = $i;
               $$dr->{_tracks}->[--$i] = $t
            }elsif($c->{name} eq 'recording'){
               $have_rec = 1;
               # Use <recording> as <track> ID, what we want
               return 0 unless exists $c->{attrs}{id};
               $t->{_id} = $c->{attrs}{id};

               foreach my $cc (@{$c->{children}}){
                  if($cc->{name} eq 'title'){
                     $have_rec = 2;
                     $t->{_title} = $cc->{data} if defined $cc->{data}
                  }elsif($cc->{name} eq 'artist-credit'){
                     $self->__xml_artist_credit($dr, \$t, $cc)
                 }
               }
            }
         }
         return 0 unless $have_rec == 2;
      }
      1
   } # }}}

   sub __xml_choose{ # {{{
      # We have multiple <release> entries which match exactly.
      my ($self, $resar) = @_;

      print "\nMusicBrainz returned multiple possible matches.\n";
      print "  (NOTE: terminal may not be able to display charset!)\n";

      my $usr = 1;
      foreach(@$resar){
         my ($i, $j);

         $i = $_->{_title};
         $i = 'Title=?' unless defined $i;
         $j = ' (';
         foreach(@{$_->{_cast}}){
            next if $_->[0] eq 'SORT';
            $i .= $j . $_->[1];
            $j = ', '
         }
         if(defined $_->{_country}){
            $i .= $j . 'Country=' . $_->{_country};
            $j = ', '
         }
         if(defined $_->{_date}){
            $i .= $j . 'Year=' . $_->{_date};
            $j = ', '
         }
         if(defined $_->{_barcode}){
            $i .= $j . 'Barcode=' . $_->{_barcode};
            $j = ', '
         }
         $i .= $j . 'MusicBrainz-ID=' . $_->{_id};
         $i .= ')';

         print "  [$usr] $i\n";
         ++$usr
      }
      print "  [0] None of those\n";

jREDO:
      print "  Please choose the number to use: ";
      $usr = <STDIN>;
      chomp $usr;
      unless($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @$resar){
         print "!   Invalid input\n";
         goto jREDO
      }

      return 0 if $usr == 0;
      $usr = $resar->[$usr - 1];
      @$resar = ($usr);
      1
   } # }}}

{package CDInfo::InfoSource::MusicBrainz::XEN; # {{{
   # XML Element Node
   our ($Root, $Curr, @POI);

   sub slurp_xml{
      my ($dr) = @_;

      sub __start{
         shift @_;
         my $n = shift @_;
         CDInfo::InfoSource::MusicBrainz::XEN->new($n, \@_)
      }
      sub __char{
         return unless defined $Curr; # always..
         my $s = $1 if $_[1] =~ /^\s*(.*)\s*$/;
         $Curr->{data} .= $s if length $s
      }
      sub __end{
         $Curr->closed() if defined $Curr
      }

      $Root = $Curr = undef;
      @POI = ();

      my $p = XML::Parser->new(Handlers => {Start=>\&__start, Char=>\&__char,
            End=>\&__end});
      eval {$p->parse($$dr)};
      if($@){
         $p = $1 if $@ =~ /^\s*(.*)\s*$/g;
         print "! MusicBrainz data XML content error:\n!  $p\n";
         return 0
      }
      return 1
   }

   sub new{
      my ($self, $name, $atts) = ($_[0], lc $_[1], $_[2]);
      $self = {
            name => $name,
            parent => $Curr,
            children => [],
            attrs => {},
            data => undef
            };
      $self = bless $self;

      $Root = $self unless defined $Root;
      $self->{parent} = $Curr;
      push @{$Curr->{children}}, $self if defined $Curr;
      $Curr = $self;

      if(defined $atts){
         while(@$atts >= 2){
            $self->{attrs}{$atts->[0]} = $atts->[1];
            shift @$atts;
            shift @$atts
         }
      }

      push @POI, $self if
         $name eq 'disc' &&
         defined $atts && defined $self->{parent} &&
         $self->{parent}->{name} eq 'disc-list' &&
         $self->{attrs}->{id} eq $CDInfo::MBrainzDiscId;

      $self
   }

   sub closed{
      my $self = $_[0];
      $Curr = $self->{parent};
      $self
   }

   #sub dump_root{
   #   sub __dive{
   #      my ($n,$pre) = @_;
   #      print "${pre}$n->{name}:\n";
   #      my @ka = keys %{$n->{attrs}};
   #      if(@ka > 0){
   #         foreach my $k (@ka){
   #            print "${pre}  <$k> => <$n->{attrs}{$k}>\n";
   #         }
   #      }
   #      print "${pre}* <$n->{data}>\n" if defined $n->{data};
   #      __dive($_, $pre.'  ') foreach @{$n->{children}};
   #   }
   #   __dive($Root, '');
   #}
} # }}} CDInfo::InfoSource::MusicBrainz::XEN
} # }}} CDInfo::InfoSource::MusicBrainz
} # }}} CDInfo::InfoSource
} # }}} CDInfo

{package Title; # {{{ A single track to read / encode
   # Title::vars,funs {{{
   our @List;

   sub create_that_many{
      die 'Title::create_that_many: impl error' if @List != 0;
      my $no = shift;
      for(my $i = 1; $i <= $no; ++$i){
         Title->new($i)
      }
   }

   sub read_all_selected{
      print "\nReading selected tracks:\n";
      foreach my $t (@List){
         next unless $t->{IS_SELECTED};
         if(-f $t->{RAW_FILE}){
            print "  Read raw track $t->{NUMBER} exists - re-read? ";
            next unless ::user_confirm()
         }

         print "  Reading track $t->{NUMBER} -> $t->{RAW_FILE}\n";
         my $emsg = &$CDInfo::FileReader($t);
         if(defined $emsg){
            print $emsg, "!  Shall i deselect the track (else quit)?";
            exit 5 unless ::user_confirm();
            $t->{IS_SELECTED} = 0;
            unlink $t->{RAW_FILE} if -f $t->{RAW_FILE}
         }
      }
   }

   sub new{
      my ($class, $no) = @_;
      ::v("Title::new(number=$no)");
      my $nos = sprintf '%03d', $no;
      my $self = {
            NUMBER => $no,
            INDEX => $no - 1,
            NUMBER_STRING => $nos,
            RAW_FILE => "$WORK_DIR/$nos." . $CDInfo::ReadFileExt,
            TARGET_PLAIN => "$TARGET_DIR/$nos",
            IS_SELECTED => 0,
            TAG_INFO => Title::TagInfo->new()
            };
      $self = bless $self, $class;
      $List[$no - 1] = $self;
      return $self
   }
   # }}}

{package Title::TagInfo; # {{{
   # ID3v2.3 aka supported oggenc(1)/faac(1) tag stuff is bundled in here,
   # i.e., MBDB:: broken down to something that can truly be stored in the tag
   # info of an encoded file.  Maybe it should instead have been Enc::TagInfo.
   # Fields are set to something useful by MBDB::Track::create_tag_info()

   sub new{
      my ($class) = @_;
      ::v("Title::TagInfo::new()");
      my $self = {};
      $self = bless $self, $class;
      return $self->reset()
   }

   sub reset{
      my $self = $_[0];
      $self->{IS_SET} = 0;
      # TPE1/TCOM,--artist,--artist - TCOM MAYBE UNDEF
      $self->{TCOM} =
      $self->{TPE1} =
      $self->{ARTIST} =
      # TALB,--album,--album
      $self->{TALB} =
      $self->{ALBUM} =
      # TIT1/TIT2,--title,--title - TIT1 MAYBE UNDEF
      $self->{TIT1} =
      $self->{TIT2} =
      $self->{TITLE} =
      # TRCK,--track: TRCK; --tracknum: TRACKNUM
      $self->{TRCK} =
      $self->{TRACKNUM} =
      # TPOS,--disc - MAYBE UNDEF
      $self->{TPOS} =
      # TYER,--year,--date: YEAR - MAYBE UNDEF
      $self->{YEAR} =
      # TCON,--genre,--genre
      $self->{GENRE} =
      $self->{GENREID} =
      # COMM,--comment,--comment - MAYBE UNDEF
      $self->{COMM} = undef;
      # TSRC,(comment for others) - ISRC code, MAYBE UNDEF
      $self->{TSRC} = undef;
      return $self
   }
} # }}} Title::TagInfo
} # }}} Title

{package MBDB; # {{{ MusicBox database handling
   # At least a super-object based approach should have been used.
   # All strings come in as UTF-8 and remain unmodified.
   # RECORDINGS is an alternative to CDDB/ALBUMSET/ALBUM, it is not tracked
   # here since we care about CD-ROMs; it is otherwise identical.

   our ($EditFile, $FinalFile, $DB);

   # MBDB::"functions" # {{{

   # db_dump() flags passed via argument hash
   sub DB_DUMP_NONE {0}
   sub DB_DUMP_FINAL {1<<0} # Final DB version, as compact as possible
   sub DB_DUMP_DOC {1<<1} # Dump documentation (only set with !FINAL)
   # Dumping in non-FINAL mode is a bit complicated, especially if multiple
   # DataSource's exist
   sub DB_DUMP_HAVE_ALBUMSET {1<<8}
   sub DB_DUMP_HAVE_ALBUM {1<<9}
   sub DB_DUMP_HAVE_CAST {1<<10}
   sub DB_DUMP_HAVE_GROUP {1<<11}
   sub DB_DUMP_HAVE_TRACK {1<<12}

   #
   sub DB_SLURP_NONE {0}
   sub DB_SLURP_IS_FINAL {1<<0}
   sub DB_SLURP_REMOVE_ON_ERROR {1<<1}

   sub init_paths{
      $EditFile = "$WORK_DIR/template.dat";
      $FinalFile = "$TARGET_DIR/music.db"
   }

   sub db_slurp{
      my ($name, $dr) = @_;

      _db_slurp($name, DB_SLURP_REMOVE_ON_ERROR, $dr)
   }

   sub db_read{
      die "Disc database is corrupted!\n" .
            "Remove $TARGET_DIR (!) and re-read disc!"
         unless _db_read($FinalFile, 1);
      1
   }

   sub db_create{
      print "Creating audio disc database description\n";

      my ($iterno, $orig_db) = (0, $DB);
jREDO:
      print "\n" if $iterno++ > 0;
      {
      my $df = $EditFile;
      ::v("Writing editable database file as $df");
      die "Cannot open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
      {
         my %flagh = (flags => MBDB::DB_DUMP_DOC, db => $DB, fh => *DF,
               prefix => '');
         $DB->db_dump(\%flagh)
      }

      die "Error writing $df: $!"
         unless print DF "# vim:set fenc=utf-8 syntax=cfg tw=4221 et:\n";

      die "Cannot close $df: $!" unless close DF
      }

      print "  Template: $EditFile\n",
         "  Please verify and edit this file as necessary\n",
         "  Shall i invoke \$VISUAL/\$EDITOR $ED? ";
      if(::user_confirm()){
         my @args = ($ED, $EditFile);
         system(@args)
      }else{
         print "  Ok, waiting: hit <RETURN> to continue ...";
         my $i = <STDIN>
      }

      # Throw away user edit
      if($DB != $orig_db){
         $DB->gut()# while defined $DB
      }

      if(!_db_read($EditFile, 0)){
         print "! Errors detected - please edit again!\n";
         goto jREDO
      }

      print "\n  ..but, once again - please verify the content\n",
         "  (Terminal may not be able to display all characters):\n";
      {
         my %flagh = (flags => MBDB::DB_DUMP_FINAL, db => $DB, fh => *STDOUT,
               prefix => '  ');
         my $xdb = $DB->{_last_db};
         $DB->{_last_db} = undef;
         $DB->db_dump(\%flagh);
         $DB->{_last_db} = $xdb
      }
      print "\n  Is this data *really* OK? ";
      goto jREDO unless ::user_confirm();
      print "\n";

      my $df = $FinalFile;
      ::v("Creating final S-Music database file as $df");
      die "Cannot open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
      {
         my %flagh = (flags => MBDB::DB_DUMP_FINAL, db => $DB, fh => *DF,
               prefix => '');
         $DB->{_last_db} = undef;
         $DB->db_dump(\%flagh)
      }
      die "Cannot close $df: $!" unless close DF;

      # TODO Ugly, but we need to reread the DB now, in order to read it with
      # TODO DB_SLURP_IS_FINAL set; shortcoming of 2020 rewrite
      die "Cannot reread $df: $!" unless _db_read($df, 1)
   }

   sub _db_read{
      my ($df, $is_final) = @_;

      die "Cannot open $df: $!" unless open DF, '<:encoding(UTF-8)', $df;
      my @dat = <DF>;
      die "Cannot close $df: $!" unless close DF;

      $DB = undef if $is_final;
      _db_slurp('USER', ($is_final ? (DB_SLURP_IS_FINAL |
            DB_SLURP_REMOVE_ON_ERROR) : DB_SLURP_NONE), \@dat)
   }

   sub _db_slurp{
      my ($df, $flags, $dr) = @_;

      MBDB::new();
      $DB->{source} = $df;

      my ($emsg, $entry) = (undef, undef);
      foreach(@$dr){
         chomp;
         s/^\s*(.*?)\s*$/$1/;
         next if length() == 0 || /^#/;
         my $line = $_;

         if($line =~ /^\[(.*?)\]$/){
            my $c = $1;
            if(defined $entry){
               $emsg = $entry->finalize();
               $entry = undef;
               if(defined $emsg){
                  $DB->{Error} = 1;
                  print "! ERROR: $emsg\n";
                  $emsg = undef
               }
            }elsif(($flags & DB_SLURP_IS_FINAL) && $c ne 'CDDB'){
               $emsg = 'Database corrupted - it does not start with a ' .
                  '(internal) [CDDB] group';
               goto jERROR
            }

            no strict 'refs';
            my $class = "MBDB::${c}";
            my $sym = "${class}::new";
            unless(%{"${class}::"}){
               $emsg = "Illegal command: [$c]"
            }else{
               $entry = &$sym($class, \$emsg)
            }
         }elsif($line =~ /^(.*?)\s*=\s*(.*)\s*$/){
            my ($k, $v) = ($1, $2);
            unless(defined $entry){
               $emsg = "KEY=VALUE line without group: <$k=$v>"
            }else{
               $emsg = $entry->set_tuple($k, $v)
            }
         }else{
            $emsg = "Line invalid: $_"
         }

jERROR:  if(defined $emsg){
            $DB->{Error} = 1;
            print "! ERROR: $emsg\n";
            $emsg = undef
         }
      }
      if(defined $entry && defined($emsg = $entry->finalize())){
         $DB->{Error} = 1;
         print "! ERROR: $emsg\n"
      }

      for(my $i = 1; $i <= $CDInfo::TrackCount; ++$i){
         if(defined($DB->{Tracks}->[$i - 1])){
            $DB->{Tracks}->[$i - 1]->create_tag_info()
               if ($flags & DB_SLURP_IS_FINAL)
         }else{
            $DB->{Error} = 1;
            print "! ERROR: no entry for track number $i found\n"
         }
      }

      return $DB if ($DB->{Error} == 0);
      return undef if !($flags & DB_SLURP_REMOVE_ON_ERROR);
      print "! ERROR: Removing database due to errors!\n\n";
      $DB->gut();
      return undef
   }
   # }}}

   # MBDB::"methods" # {{{
   sub new{
      ::v("MBDB::new()");
      my $self = {
         _last_db => $DB,
         objectname => 'MBDB',
         source => 'IMPLERR',
         Error => 0,
         # [] objects of global interest
         AlbumSet => undef,
         Album => undef,
         # .. and these are references to objects in outermost/first DB
         CDDB => undef,
         Sort => undef, # SORT fields (always global)
         # Not so
         Cast => undef, # Global Cast
         Group => undef, # Currently active [group], inherited by Track::s
         Tracks => [],
         # Used for the final (user) DBonly: the order of CAST, GROUP(s) and
         # TRACK(s) matter
         CGTAllocList => []
      };
      $self->{Tracks}->[$CDInfo::TrackCount - 1] = undef;
      $DB = $self = bless $self;

      if(defined $self->{_last_db}){
         $self->{CDDB} = $self->{_last_db}->{CDDB};
         $self->{Sort} = $self->{_last_db}->{Sort}
      }else{
         $self->{Sort} = []
      }

      $self
   }

   sub gut{
      my ($self) = @_;
      if($self == $DB){
         $DB = $self->{_last_db}
      }else{
         for(my $i = $DB;; $i = $i->{_last_db}){
            if($i->{_last_db} == $self){
               $i->{_last_db} = $self->{_last_db};
               last
            }
         }
      }
   }

   sub db_dump{
      # %$hr: flags=>X, db=>database, fh=>I/O, prefix=[(empty) string]
      # In here we handle comment, the comment prefix
      # db_dump()s will die() on any error
      my ($self, $hr) = @_;
      my ($pre, $xs, $o, $i);

      $pre = $hr->{prefix};
      $pre = '' if $pre =~ /^\s+$/;
      $hr->{comment} = '#';

      if($hr->{flags} & DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# This file is and used to be in UTF-8 encoding (codepage,charset) ONLY!
# Syntax (processing is line based):
# - Leading and trailing whitespace is ignored
# - Empty lines are ignored
# - Lines starting with # are comments and discarded
# - [XY] on a line of its own switches to a configuration group XY
# - And there are 'KEY = VALUE' lines - surrounding whitespace is removed
# - Definition ORDER IS IMPORTANT!

__EOT__
      }

      $xs = $self;

      MBDB::CDDB::db_dump_doc($hr);
      $xs->{CDDB}->db_dump($hr);
      die 'I/O error'
         unless ($hr->{flags} & DB_DUMP_FINAL) || print {$hr->{fh}} "${pre}\n";
      #$xs = $self;

      MBDB::ALBUMSET::db_dump_doc($hr);
      for(; defined $xs; $xs = $xs->{_last_db}){
         $hr->{comment} = "# $xs->{source}: "
               if ($hr->{flags} & DB_DUMP_HAVE_ALBUMSET);
         $o = $xs->{AlbumSet};
         $o->db_dump($hr) if defined $o
      }
      die 'I/O error'
         unless ($hr->{flags} & DB_DUMP_FINAL) ||
            !($hr->{flags} & DB_DUMP_HAVE_ALBUMSET) ||
            print {$hr->{fh}} "${pre}\n";
      $hr->{comment} = '#';
      $xs = $self;

      MBDB::ALBUM::db_dump_doc($hr);
      for(; defined $xs; $xs = $xs->{_last_db}){
         $hr->{comment} = "# $xs->{source}: "
               if ($hr->{flags} & DB_DUMP_HAVE_ALBUM);
         $o = $xs->{Album};
         $o->db_dump($hr) if defined $o
      }
      die 'I/O error'
         unless ($hr->{flags} & DB_DUMP_FINAL) ||
            !($hr->{flags} & DB_DUMP_HAVE_ALBUM) ||
            print {$hr->{fh}} "${pre}\n";
      $hr->{comment} = '#';
      $xs = $self;

      # In final mode we simply walk the alloc list now

      if($hr->{flags} & DB_DUMP_FINAL){
         # And if we do not need to take care for definition order: put sort
         MBDB::CAST::db_dump_sort($hr) unless defined $self->{Cast};
         $_->db_dump($hr) foreach @{$self->{CGTAllocList}}
      }else{
         # Otherwise we need to dance over the alloc list and then dump what
         # the user did not include in the edit thereafter
         my ($have_cast, $have_group, $have_track, @tracks) = (0, 0);
         $tracks[$CDInfo::TrackCount - 1] = undef;

         sub __cast{
            my ($hr, $pre, $xs, $have_castr) = @_;
            MBDB::CAST::db_dump_doc($hr) if !$$have_castr; # always..
            $$have_castr = 1;

            for(; defined $xs; $xs = $xs->{_last_db}){
               $hr->{comment} = "# $xs->{source}: "
                     if ($hr->{flags} & DB_DUMP_HAVE_CAST);
               my $o = $xs->{Cast};
               $o->db_dump($hr) if defined $o
            }
            $hr->{comment} = '#';
            die 'I/O error'
               unless ($hr->{flags} & DB_DUMP_FINAL) ||
                  !($hr->{flags} & DB_DUMP_HAVE_CAST) ||
                  print {$hr->{fh}} "${pre}\n"
         }

         sub __group{
            my ($hr, $pre, $xs, $have_groupr, $ent) = @_;
            MBDB::GROUP::db_dump_doc($hr) if !$$have_groupr;
            $$have_groupr = 1;

            $ent->db_dump($hr);
            die 'I/O error' unless print {$hr->{fh}} "${pre}\n"
         }

         sub __track{
            my ($hr, $pre, $xs, $have_trackr, $trackno) = @_;
            MBDB::TRACK::db_dump_doc($hr) if !$$have_trackr;
            $$have_trackr = 1;

            for(; defined $xs; $xs = $xs->{_last_db}){
               if(defined(my $o = $xs->{Tracks}->[$trackno])){
                  $hr->{comment} = "# $xs->{source}: "
                        if ($hr->{flags} & DB_DUMP_HAVE_TRACK);
                  $o->db_dump($hr)
               }
            }
            $hr->{comment} = '#';
            die 'I/O error'
               unless !($hr->{flags} & DB_DUMP_HAVE_TRACK) ||
                  print {$hr->{fh}} "${pre}\n";
            $hr->{flags} &= ~DB_DUMP_HAVE_TRACK
         }

         # If there is no CAST at all, dump doc and sort first
         for(;; $xs = $xs->{_last_db}){
            last if defined $xs->{Cast};
            unless(defined $xs->{_last_db}){
               MBDB::CAST::db_dump_doc($hr);
               MBDB::CAST::db_dump_sort($hr);
               last
            }
         }
         $xs = $self;

         # Ditto, GROUP
         for(;; $xs = $xs->{_last_db}){
            last if defined $xs->{Group};
            unless(defined $xs->{_last_db}){
               MBDB::GROUP::db_dump_doc($hr);
               last
            }
         }
         $xs = $self;

         foreach my $ent (@{$self->{CGTAllocList}}){
            if($ent->{objectname} eq 'CAST'){
               __cast($hr, $pre, $xs, \$have_cast)
            }elsif($ent->{objectname} eq 'GROUP'){
               __group($hr, $pre, $xs, \$have_group, $ent)
            }else{#if($ent->{objectname} eq 'TRACK')
               $tracks[$ent->{NUMBER} - 1] = $ent;
               __track($hr, $pre, $xs, \$have_track, $ent->{NUMBER} - 1)
            }
         }

         for($i = 0; $i < @tracks; ++$i){
            __track($hr, $xs, \$have_track, $i) unless defined $tracks[$i]
         }
      }
   }
   # }}}

{package MBDB::CDDB; # {{{
   sub is_key_supported{
      my $k = $_[0];
      ($k eq 'CDID' || $k eq 'MBRAINZ_DISC_ID' ||
         $k eq 'TRACK_FIRST' || $k eq 'TRACK_LAST' || $k eq 'TRACKS_LBA')
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# The [CDDB] group is "internal" and should not be modified

__EOT__
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::DB->{CDDB}){
         #$$emsgr = 'There may only be one (internal!) [CDDB] section';
         return $MBDB::DB->{CDDB}
      }
      ::v("MBDB::CDDB::new()");
      my $self = {
            objectname => 'CDDB',
            CDID => undef, MBRAINZ_DISC_ID => undef,
            TRACK_FIRST => undef, TRACK_LAST => undef, TRACKS_LBA => undef
            };
      $self = bless $self, $class;
      $MBDB::DB->{CDDB} = $self
      #$self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      return "[CDDB] entries cannot be set" if defined $MBDB::DB->{_last_db};
      $self->{$k} = $v;
      undef
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      return 'CDDB requires CDID, MBRAINZ_DISC_ID, ' .
            'TRACKS_LBA, TRACK_FIRST and TRACK_LAST;'
         unless(defined $self->{CDID} && defined $self->{MBRAINZ_DISC_ID} &&
            defined $self->{TRACK_FIRST} && defined $self->{TRACK_LAST} &&
            defined $self->{TRACKS_LBA});
      undef
   }

   sub db_dump{
      my ($self, $hr) = @_;

      sub __dump{
         my ($self, $hr) = @_;
         my $pre = $hr->{prefix};
         #$pre = $hr->{comment} . $pre
         #     if ($hr->{flags} & MBDB::DB_DUMP_HAVE_CDDB);
         $pre = $hr->{comment} . $pre
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);

         # This "cannot become corrupted by user edits", so just dump
         return <<__EOT__
${pre}[CDDB]
${pre}CDID = $self->{CDID}
${pre}MBRAINZ_DISC_ID = $self->{MBRAINZ_DISC_ID}
${pre}TRACK_FIRST = $self->{TRACK_FIRST}
${pre}TRACK_LAST = $self->{TRACK_LAST}
${pre}TRACKS_LBA = $self->{TRACKS_LBA}
__EOT__
      }

      die 'I/O error' unless print {$hr->{fh}} $self->__dump($hr);
      #$hr->{flags} |= MBDB::DB_DUMP_HAVE_CDDB
      #      unless $hr->{flags} & DB_DUMP_FINAL;
      $self
   }
} # }}} MBDB::CDDB

{package MBDB::ALBUMSET; # {{{
   sub is_key_supported{
      my $k = $_[0];
      ($k eq 'TITLE' || $k eq 'SET_COUNT')
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# [ALBUMSET]: TITLE, SET_COUNT
#  If a multi-CD-Set is read each CD gets its own database file,
#  ALBUMSET and the SET_PART field of ALBUM can be used to indicate that.
#  Repeat the same ALBUMSET and adjust the SET_PART field.
#  (No GENRE etc.: all that is in ALBUM only ... as can be seen)

__EOT__
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::DB->{AlbumSet}){
         $$emsgr = 'ALBUMSET yet defined';
         return undef
      }
      ::v("MBDB::ALBUMSET::new()");
      my $self = {
            objectname => 'ALBUMSET',
            TITLE => undef, SET_COUNT => undef
            };
      $self = bless $self, $class;
      $MBDB::DB->{AlbumSet} = $self
      #$self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      $self->{$k} = $v;
      undef
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      my $emsg = undef;
      $emsg .= 'ALBUMSET requires TITLE and SET_COUNT;'
            unless defined $self->{TITLE} && defined $self->{SET_COUNT};
      $emsg
   }

   sub db_dump{
      my ($self, $hr) = @_;

      sub __dump{
         my ($self, $hr) = @_;
         my ($pre, $rv) = ($hr->{prefix}, '');

         if($hr->{flags} & MBDB::DB_DUMP_HAVE_ALBUMSET){
            $pre = $hr->{comment} . $pre
         }else{
            $rv .= "${pre}[ALBUMSET]\n"
         }

         $rv .= "${pre}TITLE = " . $self->{TITLE} . "\n"
               if defined $self->{TITLE};
         $rv .= "${pre}SET_COUNT = " . $self->{SET_COUNT} . "\n"
               if defined $self->{SET_COUNT};
         $rv
      }

      die 'I/O error' unless print {$hr->{fh}} $self->__dump($hr);
      $hr->{flags} |= MBDB::DB_DUMP_HAVE_ALBUMSET
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);
      $self
   }
} # }}} MBDB::ALBUMSET

{package MBDB::ALBUM; # {{{
   sub is_key_supported{
      my $k = $_[0];
      ($k eq 'TITLE' ||
         $k eq 'TRACK_COUNT' ||
         $k eq 'SET_PART' || $k eq 'YEAR' || $k eq 'GENRE' ||
         $k eq 'GAPLESS' || $k eq 'COMPILATION' ||
         $k eq 'MCN' || $k eq 'UPC_EAN' || $k eq 'MBRAINZ_ID')
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# [ALBUM]: TITLE, TRACK_COUNT, (SET_PART, YEAR, GENRE, GAPLESS, COMPILATION,
#  MCN, UPC_EAN, MBRAINZ_ID)
#  If the album is part of an ALBUMSET TITLE may only be 'CD 1' -- it is
#  required nevertheless even though it could be deduced automatically
#  from the ALBUMSET's TITLE and the ALBUM's SET_PART: sorry for that!
#  I.e., SET_PART is required, then, and the two TITLEs of the ALBUMSET and
#  the ALBUM together form the actual album title used in encoded files.
#  GENRE is one of the ID3 genres ($SELF --genre-list to see them).
#  GAPLESS (if 1) states wether there is no silence in between tracks, and
#  COMPILATION (if 1) wether this is a compilation of various-artists etc.
#  MCN is the Media Catalog Number, and UPC_EAN is the Universal Product
#  Number alias European Article Number (bar code).  MBRAINZ_ID is the
#  MusicBrainz "MBID" of the medium.

__EOT__
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::DB->{Album}){
         $$emsgr = 'ALBUM yet defined';
         return undef
      }
      ::v("MBDB::ALBUM::new()");
      my $self = {
            objectname => 'ALBUM',
            TITLE => undef, TRACK_COUNT => undef,
            SET_PART => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0,
            MCN => undef, UPC_EAN => undef, MBRAINZ_ID => undef
            };
      $self = bless $self, $class;
      $MBDB::DB->{Album} = $self
      #$self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      if($k eq 'SET_PART'){
         return 'ALBUM: SET_PART without ALBUMSET'
            unless defined $MBDB::DB->{AlbumSet};
         return "ALBUM: SET_PART $v not a number" unless $v =~ /^\d+$/;
         return 'ALBUM: SET_PART value larger than SET_COUNT'
            if int $v > int $MBDB::DB->{AlbumSet}->{SET_COUNT}
      }elsif($k eq 'GENRE'){
         my $g = ::genre($v);
         return "ALBUM: $v not a valid GENRE (try --genre-list)"
            unless defined $g;
         $v = $g
      }elsif($k eq 'TRACK_COUNT'){
         return "ALBUM: TRACK_COUNT $v not a number" unless $v =~ /^\d+$/
      }elsif($k eq 'GAPLESS' || $k eq 'COMPILATION'){
         return 'ALBUM: GAPLESS and COMPILATION can only be 0 or 1'
            unless $v =~ /^[01]$/
      }elsif($k eq 'MCN'){
         return "ALBUM: invalid MCN: $v" unless length($v) == 13
      }elsif($k eq 'UPC_EAN'){
         my $i = length $v;
         return "ALBUM: invalid UPC_EAN: $v" unless $i >= 8 && $i <= 13 &&
            $v =~ /^[[:digit:]]+$/
      }
      $self->{$k} = $v;
      undef
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      my $emsg = undef;
      $emsg .= 'ALBUM requires TITLE;' unless defined $self->{TITLE};
      $emsg .= 'ALBUM requires TRACK_COUNT;'
            unless defined $self->{TRACK_COUNT};
      $emsg .= 'ALBUM requires SET_PART if ALBUMSET defined;'
            if defined $MBDB::DB->{AlbumSet} && !defined $self->{SET_PART};
      $emsg
   }

   sub db_dump{
      my ($self, $hr) = @_;

      sub __dump{
         my ($self, $hr) = @_;
         my ($pre, $rv) = ($hr->{prefix}, '');

         if($hr->{flags} & MBDB::DB_DUMP_HAVE_ALBUM){
            $pre = $hr->{comment} . $pre
         }else{
            $rv .= "${pre}[ALBUM]\n"
         }

         $rv .= "${pre}TITLE = " . $self->{TITLE} . "\n"
               if defined $self->{TITLE};
         $rv .= "${pre}TRACK_COUNT = " . $self->{TRACK_COUNT} . "\n"
               if defined $self->{TRACK_COUNT};
         $rv .= "${pre}SET_PART = " . $self->{SET_PART} . "\n"
               if defined $self->{SET_PART};
         $rv .= "${pre}YEAR = " . $self->{YEAR} . "\n"
               if defined $self->{YEAR};
         $rv .= "${pre}GENRE = " . $self->{GENRE} . "\n"
               if defined $self->{GENRE};
         $rv .= "${pre}GAPLESS = " . $self->{GAPLESS} . "\n"
               if $self->{GAPLESS} != 0;
         $rv .= "${pre}COMPILATION = " . $self->{COMPILATION} . "\n"
               if $self->{COMPILATION} != 0;
         $rv .= "${pre}MCN = " . $self->{MCN} . "\n"
               if defined $self->{MCN};
         $rv .= "${pre}UPC_EAN = " . $self->{UPC_EAN} . "\n"
               if defined $self->{UPC_EAN};
         $rv .= "${pre}MBRAINZ_ID = " . $self->{MBRAINZ_ID} . "\n"
               if defined $self->{MBRAINZ_ID};
         $rv
      }

      die 'I/O error' unless print {$hr->{fh}} $self->__dump($hr);
      $hr->{flags} |= MBDB::DB_DUMP_HAVE_ALBUM
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);
      $self
   }
} # }}} MBDB::ALBUM

{package MBDB::CAST; # {{{
   # CAST is special since it is used to represent the global [CAST] group, if
   # any, as well as the cast fields of those "parent" groups which offer them

   sub is_key_supported{
      my $k = $_[0];
      ($k eq 'ARTIST' ||
         $k eq 'SOLOIST' || $k eq 'CONDUCTOR' ||
         $k eq 'COMPOSER' || $k eq 'SONGWRITER' ||
         $k eq 'SORT')
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# [CAST]: (ARTIST, SOLOIST, CONDUCTOR, COMPOSER/SONGWRITER, SORT)
#  The CAST includes all the humans responsible for an artwork in detail.
#  Cast information not only applies to the ([ALBUMSET] and) [ALBUM],
#  but also to all following tracks; thus, if any [GROUP] or [TRACK] is to
#  be defined which shall not inherit the [CAST] fields, they need to be
#  defined before it!
#
#  SORT fields are "special" in that they will always be dumped as part of
#  the/a global [CAST].  And whereas the other fields should be real names
#  ("Wolfgang Amadeus Mozart") these specify how sorting is to be applied
#  ("Mozart, Wolfgang Amadeus"), followed by the normal real name in
#  parenthesis, for example:
#     SORT = Hope, Daniel (Daniel Hope)
#
#  For classical music the orchestra should be the ARTIST.
#  SOLOIST should include the instrument in parenthesis (Midori (violin)).
#  The difference between COMPOSER and SONGWRITER is only noticeable for
#  output file formats which do not support a COMPOSER information frame:
#  whereas the SONGWRITER is simply discarded then, the COMPOSER becomes
#  part of the ALBUM TITLE (Vivaldi: Le quattro stagioni - "La Primavera")
#  if there were any COMPOSER(s) in the global [CAST], or part of the
#  TRACK TITLE (The Killing Joke: Pssyche) otherwise ([GROUP]/[TRACK]).

__EOT__
      }
   }

   # There is no global $Cast object, but there may be (global) SORT entries:
   # dump them, now!
   sub db_dump_sort{
      my $hr = $_[0];

      if(@{$hr->{db}->{Sort}} > 0){
         die 'I/O error' unless print {$hr->{fh}} "[CAST]\n";
         foreach(@{$hr->{db}->{Sort}}){
            die 'I/O error'
               unless print {$hr->{fh}} $hr->{prefix} . "SORT = " . $_ . "\n"
         }
         $hr->{flags} |= MBDB::DB_DUMP_HAVE_CAST
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      my $parent = (@_ > 2) ? $_[2] : undef;
      if(!defined $parent && defined $MBDB::DB->{Cast}){
         $$emsgr = 'CAST yet defined';
         return undef
      }

      ::v("MBDB::CAST::new(" .  (defined $parent ? "parent=$parent)" : ')'));
      my $self = {
            objectname => 'CAST', parent => $parent,
            ARTIST => [],
            SOLOIST => [], CONDUCTOR => [],
            COMPOSER => [], SONGWRITER => [],
            # With the 2020 rewrite i kept the old "simply copy it all over" to
            # keep TRACK::create_tag_info() unchanged, but since we now are
            # responsible to actually dump the database ourselves, we need to
            # be able to differentiate in what CAST really belongs to us
            _parent_artists => 0,
            _parent_soloists => 0, _parent_conductors => 0,
            _parent_composers => 0, _parent_songwriters => 0,
            _imag_SORT => [],
            # Even without CDDB we may see things like "A feat. B", and when
            # dumping the editable variant we want to present users at least
            # commented out versions, see set_imag_artists_from_track_title()
            _imag_ARTIST => []
            };
      $self = bless $self, $class;

      unless(defined $parent){
         push @{$MBDB::DB->{CGTAllocList}}, $self;
         $MBDB::DB->{Cast} = $self
      }
      $self
   }

   sub new_state_clone{
      my $parent = shift;
      my $self = MBDB::CAST->new(undef, $parent);

      if($parent eq 'TRACK' && defined $MBDB::DB->{Group}){
         $parent = $MBDB::DB->{Group}->{cast}
      }elsif(defined $MBDB::DB->{Cast}){
         $parent = $MBDB::DB->{Cast}
      }else{
         $parent = undef
      }

      if(defined $parent){
         push @{$self->{ARTIST}}, $_ foreach (@{$parent->{ARTIST}});
         push @{$self->{SOLOIST}}, $_ foreach (@{$parent->{SOLOIST}});
         push @{$self->{CONDUCTOR}}, $_ foreach (@{$parent->{CONDUCTOR}});
         push @{$self->{COMPOSER}}, $_ foreach (@{$parent->{COMPOSER}});
         push @{$self->{SONGWRITER}}, $_ foreach (@{$parent->{SONGWRITER}})
      }

      $self->{_parent_artists} = scalar @{$self->{ARTIST}};
      $self->{_parent_soloists} = scalar @{$self->{SOLOIST}};
      $self->{_parent_conductors} = scalar @{$self->{CONDUCTOR}};
      $self->{_parent_composers} = scalar @{$self->{COMPOSER}};
      $self->{_parent_songwriters} = scalar @{$self->{SONGWRITER}};

      $self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");

      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      if($k ne 'SORT'){
         push @{$self->{$k}}, $v;
         $v = $1 if ($k eq 'SOLOIST' && $v =~ /^\s*(.*?)\s*\(.*\)$/);
         $self->_add_imag_sort($v)
      }else{
         push @{$MBDB::DB->{Sort}}, $v
      }
      undef
   }

   sub set_imag_artists_from_track_title{
      my ($self, $t) = @_;

      sub __try_split{
         my ($self, $art) = @_;

         my $any = 0;
         while($art =~ /(.+?)(?:feat(?:uring|\.)?|and|&)(.+)/i){
            $any = 1;
            $art = $2;
            my $e = $1;
            $e =~ s/^\s*//;
            $e =~ s/\s*$//;
            push @{$self->{_imag_ARTIST}}, $e;
            $self->_add_imag_sort($e)
         }
         if($any){
            $art =~ s/^\s*//;
            push @{$self->{_imag_ARTIST}}, $art;
            $self->_add_imag_sort($art)
         }
      }

      if($t =~ /^\s*(.+)\s*\/\s*(.+)\s*$/){
         $t = $2;
         my $a = $1;
         $a =~ s/\s*$//;
         # First the plain versions
         push @{$self->{_imag_ARTIST}}, $a;
         $self->_add_imag_sort($a);
         # But try to take advantage of things like "feat." etc..
         $self->__try_split($a)
      }

      $t
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");

      my $emsg = undef;
      if(defined $self->{parent} && $self->{parent} eq 'TRACK' &&
            @{$self->{ARTIST}} == 0){
         $emsg .= 'TRACK requires at least one ARTIST;'
      }
      $emsg
   }

   sub parent_artists {$_[0]->{_parent_artists}}
   sub parent_soloists {$_[0]->{_parent_soloists}}
   sub parent_conductors {$_[0]->{_parent_conductors}}
   sub parent_composers {$_[0]->{_parent_composers}}
   sub parent_songwriters {$_[0]->{_parent_songwriters}}

   sub db_dump_core{
      my ($self, $hr, $pre) = @_;
      my ($rv, $ised, $i) = ('', !($hr->{flags} & MBDB::DB_DUMP_FINAL));

      unless(defined $self->{parent}){
         if($hr->{flags} & MBDB::DB_DUMP_HAVE_CAST){
            $pre = $hr->{comment} . $pre
         }else{
            $rv .= "${pre}[CAST]\n"
         }
      }

      for($i = $self->{_parent_artists}; $i < @{$self->{ARTIST}}; ++$i){
         $rv .= "${pre}ARTIST = " . $self->{ARTIST}->[$i] . "\n"
      }
      if($ised){
         $rv .= " # SUGGESTION:\n #${pre} ARTIST = " . $_ . "\n"
               foreach (@{$self->{_imag_ARTIST}})
      }

      for($i = $self->{_parent_soloists}; $i < @{$self->{SOLOIST}}; ++$i){
         $rv .= "${pre}SOLOIST = " . $self->{SOLOIST}->[$i] . "\n"
      }
      for($i = $self->{_parent_conductors}; $i < @{$self->{CONDUCTOR}};
            ++$i){
         $rv .= "${pre}CONDUCTOR = " . $self->{CONDUCTOR}->[$i] . "\n"
      }
      for($i = $self->{_parent_composers}; $i < @{$self->{COMPOSER}}; ++$i){
         $rv .= "${pre}COMPOSER = " . $self->{COMPOSER}->[$i] . "\n"
      }
      for($i = $self->{_parent_songwriters}; $i < @{$self->{SONGWRITER}};
            ++$i){
         $rv .= "${pre}SONGWRITER = " . $self->{SONGWRITER}->[$i] . "\n"
      }

      unless(defined $self->{parent}){
         foreach(@{$hr->{db}->{Sort}}){
            $rv .= "${pre}SORT = " . $_ . "\n"
         }
      }

      if($ised){
         $rv .= " # SUGGESTION:\n #${pre} SORT = " . $_ . "\n"
               foreach (@{$self->{_imag_SORT}})
      }

      $rv
   }

   sub db_dump{
      my ($self, $hr) = @_;

      unless(defined $self->{parent}){
         die 'I/O error'
            unless print {$hr->{fh}} $self->db_dump_core($hr, $hr->{prefix});
         $hr->{flags} |= MBDB::DB_DUMP_HAVE_CAST
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);
         $self
      }else{
         $self->db_dump_core($hr, $hr->{prefix})
      }
   }

   sub _add_imag_sort{
      my ($self, $sort) = @_;
      if($sort =~ /^The\s+/i && $sort !~ /^the the$/i){ # The The, The
         $sort =~ /^the\s+(.+)\s*$/i;
         $sort = "$1, The (The $1)"
      }elsif($sort =~ /^((?:dj|dr)\.?)\s+/i){
         $sort =~ /^((?:dj|dr)\.?)\s+(.+)\s*$/i;
         $sort = "$2, $1 ($1 $2)"
      }elsif($sort =~ /^\s*(\S+)\s+(.+)\s*$/){
         $sort = "$2, $1 ($1 $2)"
      }else{
         $sort = "$sort ($sort)"
      }
      push @{$self->{_imag_SORT}}, $sort
   }
} # }}} MBDB::CAST

{package MBDB::GROUP; # {{{
   sub is_key_supported{
      my $k = $_[0];
      ($k eq 'LABEL' || $k eq 'YEAR' || $k eq 'GENRE' ||
         $k eq 'GAPLESS' || $k eq 'COMPILATION' ||
         MBDB::CAST::is_key_supported($k))
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# [GROUP]: LABEL, (YEAR, GENRE, GAPLESS, COMPILATION, and all [CAST]-fields)
#  Grouping information can optionally be used, and applies to all the
#  following tracks until the next [GROUP] is seen; TRACKs which do not apply
#  to any GROUP must thus be defined before any [GROUP].
#  LABEL is not optional but can be empty; it is used to subdivide classical
#  music, for example: LABEL = Water Music Suite No. 1 in F major.
#  GENRE is one of the ID3 genres ($SELF --genre-list to see them).
#  GAPLESS states wether there shall be no silence in between tracks,
#  and COMPILATION wether this is a compilation of various-artists, or so.
#  CAST-fields may be used to *append* to global [CAST] fields -- to specify
#  CAST fields exclusively, place the GROUP before the global [CAST]!

__EOT__
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      ::v("MBDB::GROUP::new()");

      unless(defined $MBDB::DB->{Album}){
         $$emsgr = 'GROUP requires ALBUM';
         return undef
      }

      my $self = {
            objectname => 'GROUP',
            LABEL => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0,
            cast => MBDB::CAST::new_state_clone('GROUP')
            };
      $self = bless $self, $class;

      $MBDB::DB->{Group} = $self;
      push @{$MBDB::DB->{CGTAllocList}}, $self;
      $self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");

      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      if($k eq 'GENRE'){
         $v = ::genre($v);
         return "GROUP: $v not a valid GENRE (try --genre-list)"
            unless defined $v
      }

      if(exists $self->{$k}){
         $self->{$k} = $v
      }else{
         $self->{cast}->set_tuple($k, $v)
      }
      undef
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");

      my $emsg = undef;
      $emsg .= 'GROUP requires LABEL;' unless defined $self->{LABEL};
      my $em = $self->{cast}->finalize();
      $emsg .= $em if defined $em;
      $emsg
   }

   sub db_dump{
      my ($self, $hr) = @_;

      sub __dump{
         my ($self, $hr) = @_;
         my ($rv, $pre) = ('', $hr->{prefix});

         if($hr->{flags} & MBDB::DB_DUMP_HAVE_GROUP){
            $pre = $hr->{comment} . $pre
         }else{
            $rv .= "${pre}[GROUP]\n"
         }

         $rv .= "${pre}LABEL = $self->{LABEL}\n"
               if defined $self->{LABEL};
         $rv .= "${pre}YEAR = " . $self->{YEAR} . "\n"
               if defined $self->{YEAR};
         $rv .= "${pre}GENRE = " . $self->{GENRE} . "\n"
               if defined $self->{GENRE};
         $rv .= "${pre}GAPLESS = " . $self->{GAPLESS} . "\n"
               if $self->{GAPLESS} != 0;
         $rv .= "${pre}COMPILATION = " . $self->{COMPILATION} . "\n"
               if $self->{COMPILATION} != 0;
         $rv .= $self->{cast}->db_dump_core($hr, $pre);
         $rv
      }

      die 'I/O error' unless print {$hr->{fh}} $self->__dump($hr);
      $hr->{flags} |= MBDB::DB_DUMP_HAVE_GROUP
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);
      $self
   }
} # }}} MBDB::GROUP

{package MBDB::TRACK; # {{{
   sub is_key_supported{
      my $k = shift;
      ($k eq 'NUMBER' || $k eq 'TITLE' ||
         $k eq 'YEAR' || $k eq 'GENRE' || $k eq 'COMMENT' ||
         $k eq 'ISRC' || $k eq 'MBRAINZ_ID' ||
         MBDB::CAST::is_key_supported($k))
   }

   sub db_dump_doc{
      my $hr = $_[0];

      if($hr->{flags} & MBDB::DB_DUMP_DOC){
         die 'I/O error' unless print {$hr->{fh}} <<__EOT__
# [TRACK]: NUMBER, TITLE, (YEAR, GENRE, COMMENT, ISRC, MBRAINZ_ID, and
#  all [CAST]-fields)
#  GENRE is one of the ID3 genres ($SELF --genre-list to see them).
#  ISRC is the International Standard Recording Code.
#  MBRAINZ_ID is the MusicBrainz "MBID" of the track.
#  CAST-fields may be used to *append* to global [CAST] (and those of an
#  active [GROUP], if there is one) fields; to specify CAST fields exclusively,
#  place the TRACK before the global [CAST] as well as any [GROUP].
#  Note: all TRACKs need an ARTIST in the end, from whatever CAST it is
#  inherited.

__EOT__
      }
   }

   sub new{
      my ($class, $emsgr) = @_;
      unless(defined $MBDB::DB->{Album}){
         $$emsgr = 'TRACK requires ALBUM';
         return undef
      }
      ::v("MBDB::TRACK::new()");
      push @{$MBDB::DB->{Data}}, '[TRACK]';
      my $self = {
            objectname => 'TRACK',
            NUMBER => undef, TITLE => undef,
            YEAR => undef, GENRE => undef, COMMENT => undef, ISRC => undef,
            MBRAINZ_ID => undef,
            group => $MBDB::DB->{Group},
            cast => MBDB::CAST::new_state_clone('TRACK'),
            _imag_TITLE => undef
            };
      bless $self, $class;
      push @{$MBDB::DB->{CGTAllocList}}, $self;
      $self
   }

   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
         unless is_key_supported($k);
      if($k eq 'GENRE'){
         $v = ::genre($v);
         return "TRACK: $v not a valid GENRE (try --genre-list)"
            unless defined $v
      }
      my $emsg = undef;
      if($k eq 'NUMBER'){
         return "TRACK: NUMBER $v does not exist"
            if int($v) <= 0 || int($v) > $CDInfo::TrackCount;
         $emsg = "TRACK: NUMBER $v was yet defined"
               if defined $MBDB::DB->{Tracks}->[$v - 1];
         $MBDB::DB->{Tracks}->[$v - 1] = $self
      }elsif($k eq 'ISRC'){
         return "TRACK: invalid ISRC: $v"
            unless length($v) == 12 && $v =~ /^[[:upper:]]{2}
                  [[:alnum:]]{3}
                  [[:digit:]]{2}
                  [[:digit:]]{5}$/x
      }
      if(exists $self->{$k}){
         $self->{$k} = $v;
         push @{$MBDB::DB->{Data}}, "$k = $v"
      }else{
         $self->{cast}->set_tuple($k, $v)
      }
      $emsg
   }

   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      my $emsg = undef;
      unless(defined $self->{NUMBER} && defined $self->{TITLE}){
         $emsg .= 'TRACK requires NUMBER and TITLE;'
      }

      unless(defined $emsg){
         my $t = $self->{cast}->set_imag_artists_from_track_title(
               $self->{TITLE});
         $self->{_imag_TITLE} = $t if $t ne $self->{TITLE}
      }

      my $em = $self->{cast}->finalize();
      $emsg .= $em if defined $em;
      unless(defined $emsg || $MBDB::DB->{Error}){
         $MBDB::DB->{Tracks}->[$self->{NUMBER} - 1] = $self
      }
      $emsg
   }

   sub db_dump{
      my ($self, $hr) = @_;

      sub __dump{
         my ($self, $hr) = @_;
         my ($rv, $pre) = ('', $hr->{prefix});

         if($hr->{flags} & MBDB::DB_DUMP_HAVE_TRACK){
            $pre = $hr->{comment} . $pre
         }else{
            $rv .= "${pre}[TRACK]\n"
         }

         $rv .= "${pre}NUMBER = $self->{NUMBER}\n"
               if defined $self->{NUMBER};
         $rv .= "${pre}TITLE = $self->{TITLE}\n"
               if defined $self->{TITLE};
         $rv .= " # SUGGESTION:\n #${pre}TITLE = $self->{_imag_TITLE}\n"
               if defined $self->{_imag_TITLE};

         $rv .= "${pre}YEAR = " . $self->{YEAR} . "\n"
               if defined $self->{YEAR};
         $rv .= "${pre}GENRE = " . $self->{GENRE} . "\n"
               if defined $self->{GENRE};
         $rv .= $self->{cast}->db_dump_core($hr, $pre);
         $rv .= "${pre}COMMENT = " . $self->{COMMENT} . "\n"
               if defined $self->{COMMENT};
         $rv .= "${pre}ISRC = " . $self->{ISRC} . "\n"
               if defined $self->{ISRC};
         $rv .= "${pre}MBRAINZ_ID = " . $self->{MBRAINZ_ID} . "\n"
               if defined $self->{MBRAINZ_ID};
         $rv
      }

      die 'I/O error' unless print {$hr->{fh}} $self->__dump($hr);
      $hr->{flags} |= MBDB::DB_DUMP_HAVE_TRACK
            unless ($hr->{flags} & MBDB::DB_DUMP_FINAL);
      $self
   }

   sub create_tag_info{ # {{{
      # Reach into ::Title::TagInfo and set MP3ID++ compatible flags from our
      # database fields.  Logically it belongs there, but one has to pay and
      # reach into internals of the other, anyway; since TagInfo stuff is also
      # "known" by encoders, keep the DB contents internal to the DB at least
      my $self = $_[0];
      my ($c, $composers, $i, $s, $x, $various);
      my $tir = $Title::List[$self->{NUMBER} - 1]->{TAG_INFO};
      $tir->{IS_SET} = 1;

      # TPE1/TCOM,--artist,--artist - TCOM MAYBE UNDEF
      $c = $self->{cast};
      ($composers, $i, $s, $x, $various) = (undef, -1, '', 0, undef);
      foreach(@{$c->{ARTIST}}){
         if($_ =~ /^\s*(various\s+artists|diverse)\s*$/){
            $various = $_;
            next;
         }
         $s .= '/' if ++$i > 0;
         $s .= $_
      }
      $x = ($i >= 0);
      if(!$x && defined $various){
         $s = $various;
         $x = 1;
      }

      $i = -1;
      foreach(@{$c->{SOLOIST}}){
         $s .= ', ' if ++$i > 0 || $x;
         $x = 0;
         $s .= $_
      }
      foreach(@{$c->{CONDUCTOR}}){
         $s .= ', ' if ++$i > 0 || $x;
         $x = 0;
         $s .= $_
      }

      $tir->{TPE1} =
      $tir->{ARTIST} = $s;

      ($i, $s, $x) = (-1, '', 0);
      foreach(@{$c->{COMPOSER}}){
         $s .= ', ' if ++$i > 0;
         $s .= $_
      }
      $composers = $s if length $s > 0;
      $x = ($i >= 0);
      $i = -1;
      foreach(@{$c->{SONGWRITER}}){
         if($x){
            $s .= ', ';
            $x = 0;
         }
         $s .= '/' if ++$i > 0;
         $s .= "$_"
      }
      $tir->{TCOM} = $s if length $s > 0;

      # TALB,--album,--album
      $tir->{TALB} =
      $tir->{ALBUM} = (defined $MBDB::DB->{AlbumSet}
               ? "$MBDB::DB->{AlbumSet}->{TITLE} - " : '') .
            $MBDB::DB->{Album}->{TITLE};
      $tir->{ALBUM} = "$composers: $tir->{ALBUM}"
            if $c->parent_composers() > 0;

      # TIT1/TIT2,--title,--title - TIT1 MAYBE UNDEF
      $tir->{TIT1} = ((defined $MBDB::DB->{Group} &&
               length($MBDB::DB->{Group}->{LABEL}) > 0)
            ? $MBDB::DB->{Group}->{LABEL} : undef);
      $tir->{TIT2} = $self->{TITLE};
      $tir->{TITLE} = (defined $tir->{TIT1}
            ? "$tir->{TIT1} - $tir->{TIT2}" : $tir->{TIT2});
      $tir->{TITLE} = "$composers: $tir->{TITLE}"
            if $c->parent_composers() == 0 && defined $composers;

      # TRCK,--track: TRCK; --tracknum: TRACKNUM
      $tir->{TRCK} =
      $tir->{TRACKNUM} = $self->{NUMBER};
      $tir->{TRCK} .= "/$MBDB::DB->{Album}->{TRACK_COUNT}";

      # TPOS,--disc - MAYBE UNDEF
      $tir->{TPOS} = (defined $MBDB::DB->{AlbumSet}
            ? ($MBDB::DB->{Album}->{SET_PART} . '/' .
               $MBDB::DB->{AlbumSet}->{SET_COUNT})
            : undef);

      # TYER,--year,--date: YEAR - MAYBE UNDEF
      $tir->{YEAR} = (defined $self->{YEAR}
            ? $self->{YEAR}
            : ((defined $MBDB::DB->{Group} &&
                  defined $MBDB::DB->{Group}->{YEAR})
               ? $MBDB::DB->{Group}->{YEAR}
               : (defined $MBDB::DB->{Album}->{YEAR}
                  ? $MBDB::DB->{Album}->{YEAR} : undef)));

      # TCON,--genre,--genre
      $tir->{GENRE} = (defined $self->{GENRE}
            ? $self->{GENRE}
            : ((defined $MBDB::DB->{Group} &&
                  defined $MBDB::DB->{Group}->{GENRE})
               ? $MBDB::DB->{Group}->{GENRE}
               : (defined $MBDB::DB->{Album}->{GENRE}
                  ? $MBDB::DB->{Album}->{GENRE} : ::genre('Humour'))));
      $tir->{GENREID} = ::genre_id($tir->{GENRE});

      # COMM,--comment,--comment - MAYBE UNDEF; place MCN, UPC/EAN, ISRC here
      $i = '';
      if(defined $self->{ISRC}){
         $tir->{TSRC} = $self->{ISRC};
         $i .= "ISRC=$self->{ISRC}"
      }
      if(defined $MBDB::DB->{Album}->{MCN}){
         $i .= '; ' if length $i > 0;
         $i .= "MCN=$MBDB::DB->{Album}->{MCN}"
      }
      if(defined $MBDB::DB->{Album}->{UPC_EAN}){
         $i .= '; ' if length $i > 0;
         $i .= "UPC/EAN=$MBDB::DB->{Album}->{UPC_EAN}"
      }
      if(defined $self->{MBRAINZ_ID}){
         $i .= '; ' if length $i > 0;
         $i .= "MBRAINZ_ID=$self->{MBRAINZ_ID}"
      }
      if(defined $self->{COMMENT}){
         $i .= '; ' if length $i > 0;
         $i .= $self->{COMMENT}
      }
      $tir->{COMM} = $i if length $i > 0
   } # }}}
} # }}} MBDB::TRACK
} # }}} MBDB

{package Enc; # {{{
   # vars,funs # {{{
   my (@FormatList, %UserFormats, $VolNorm);

   sub format_has_any{
      scalar keys %UserFormats
   }

   sub format_list{
      no strict 'refs';
      if(@FormatList == 0){
         foreach(keys %{*{"Enc::Coder::"}}){
            if(exists &{"Enc::Coder::${_}new"}){
               push @FormatList, $1 if /^(\w+)/
            }
         }
      }
      \@FormatList
   }

   sub format_add{
      my ($f) = @_;
      $f = uc $f;
      foreach(@{format_list()}){
         if($f eq $_){
            $UserFormats{$f} = 1;
            return 1
         }
      }
      return 0
   }

   sub calculate_volume_normalize{ # {{{
      $VolNorm = undef;
      my $nope = shift;

      if($nope){
         print "Volume normalization has been turned off\n";
         return
      }

      print "Calculating average volume normalization over all tracks:\n  ";
      foreach my $t (@Title::List){
         next unless $t->{IS_SELECTED};

         my $f = $t->{RAW_FILE};
         my $cmd = 'sox ' . ($CDInfo::RawIsWAVE ? '-t wav'
                  : '-t raw -r 44100 -c 2 ' .
                     ($NEW_SOX ? "-b 16 -e signed-integer" : "-w -s")) .
               " $f -n stat -v 2>&1 |";
         die "Cannot open SOX stat for $f: $cmd: $!" unless open SOX, $cmd;
         my $avg = <SOX>;
         die "Cannot close SOX stat for $f: $cmd: $!" unless close SOX;
         chomp $avg;

         if($t->{INDEX} != 0 && $t->{INDEX} % 7 == 0){
            print "\n  $t->{NUMBER}: $avg, "
         }else{
            print "$t->{NUMBER}: $avg, "
         }
         $VolNorm = $avg unless defined $VolNorm;
         $VolNorm = $avg if $avg < $VolNorm
      }

      if(!defined $VolNorm || ($VolNorm >= 0.98 && $VolNorm <= 1.05)){
         print "\n  Volume normalization fuzzy/redundant, turned off\n\n";
         $VolNorm = undef
      }else{
         print "\n  Volume amplitude will be changed by: $VolNorm\n\n";
         $VolNorm = "-v $VolNorm" # (For sox(1))
      }
   } # }}}

   sub encode_selected{
      print "Encoding selected tracks:\n";
      foreach my $t (@Title::List){
         unless($t->{IS_SELECTED}){
            ::v("  Skipping $t->{NUMBER}: not selected");
            next
         }
         print "  Track $t->{NUMBER} -> $t->{TARGET_PLAIN}.*\n";
         _encode_file($t)
      }
   }

   sub _encode_file{
      my $title = shift;
      my $tpath = $title->{TARGET_PLAIN};
      my @Coders;

      if(defined $VolNorm){
         my $cmd = "sox $VolNorm " .
               ($CDInfo::RawIsWAVE ? '-t wav'
                : '-t raw -r 44100 -c 2 ' .
                  ($NEW_SOX ? '-b 16 -e signed-integer' : '-w -s')) .
               ' ' . $title->{RAW_FILE} .
               ($CDInfo::RawIsWAVE ? ' -t wav ' : ' -t raw ') . '- |';
         die "Cannot open RAW input sox(1) pipe: $cmd: $!"
            unless open RAW, $cmd
      }else{
         die "Cannot open input file: $title->{RAW_FILE}: $!"
            unless open RAW, '<', $title->{RAW_FILE}
      }
      die "binmode $title->{RAW_FILE} failed: $!" unless binmode RAW;

      foreach(keys %UserFormats){
         no strict 'refs';
         push @Coders, &{"Enc::Coder::${_}::new"}($title)
      }

      for(my $data;;){
         my $bytes = sysread RAW, $data, 1024 * 1000;
         die "Error reading RAW input: $!" unless defined $bytes;
         last if $bytes == 0;
         $_->write($data) foreach @Coders
      }

      die "Cannot close RAW input: $!" unless close RAW;
      $_->del() foreach @Coders
   }
   # }}}

{package Enc::Helper; # {{{
   # We have to solve problems with strings.
   # We use :encoding to ensure our I/O layer is UTF-8, but that does not help
   # for the command line of the audio encode applications we start, since our
   # carefully prepared UTF-8 strings will then be converted according to the
   # Perl I/O layer for STDOUT!  Thus we need to enwrap the open() calls that
   # start the audio encoders in utf8_echomode_on() and utf8_echomode_off()
   # calls!  I have forgotten who gave this working solution on a perl IRC
   # channel which i entered via browser on 2013-05-06, i apologise: thank you!
   sub utf8_echomode_on {binmode STDOUT, ':encoding(utf8)'}
   sub utf8_echomode_off {binmode STDOUT, ':pop'}

{package Enc::Helper::MP3; # {{{
   sub create_fd{
      my ($title, $path, $myid, $quali) = @_;

      _tag_file($path, $title);

      ::v("Creating MP3 lame(1) $myid-quality encoder");
      Enc::Helper::utf8_echomode_on();
      my $cmd = '| lame --quiet ' .
            ($CDInfo::RawIsWAVE ? '' : '-r -s 44.1 --bitwidth 16 ') .
            "--vbr-new $quali -q 0 - - >> $path";
      die "Cannot open MP3 $myid: $cmd: $!" unless open(my $fd, $cmd);
      Enc::Helper::utf8_echomode_off();
      die "binmode error MP3$myid: $!" unless binmode $fd;
      $fd
   }

   sub _tag_file{
      # Stuff in (parens) refers ID3 tag version 2.3.0, www.id3.org.
      my ($path, $title) = @_;
      my $ti = $title->{TAG_INFO};
      ::v("Creating MP3 tag file headers");

      my $tag;
      $tag .= _mp3_frame('TPE1', $ti->{TPE1});
      $tag .= _mp3_frame('TCOM', $ti->{TCOM}) if defined $ti->{TCOM};
      $tag .= _mp3_frame('TALB', $ti->{TALB});
      $tag .= _mp3_frame('TIT1', $ti->{TIT1}) if defined $ti->{TIT1};
      $tag .= _mp3_frame('TIT2', $ti->{TIT2});
      $tag .= _mp3_frame('TRCK', $ti->{TRCK});
      $tag .= _mp3_frame('TPOS', $ti->{TPOS}) if defined $ti->{TPOS};
      $tag .= _mp3_frame('TCON', '(' . $ti->{GENREID} . ')' . $ti->{GENRE});
      $tag .= _mp3_frame('TYER', $ti->{YEAR}) if defined $ti->{YEAR};
      $tag .= _mp3_frame('TSRC', $ti->{TSRC});
      $ti = $ti->{COMM};
      if(defined $ti){
         $ti = "engS-MUSIC:COMM\x00$ti";
         $tag .= _mp3_frame('COMM', $ti)
      }

      # (5.) Apply unsynchronization to all frames
      my $has_unsynced = int($tag =~ s/\xFF/\xFF\x00/gs);

      # (3.1.) Prepare the header
      # ID3v2, version 2
      my $header = 'ID3' . "\x03\00";
      # Flags 1 byte: bit 7 (first bit MSB) =$has_unsynced
      $header .= pack('C', ($has_unsynced > 0) ? 0x80 : 0x00);
      # Tag size: 4 bytes as 4*7 bits
      {  my $l = length $tag;
         my $r;
         # Do not use my own carry-flag beatin' version, but the
         # MP3-Info.pm one ...
         #$r = $l     & 0x0000007F;
         #$r |= ($l << 1) & 0x00007F00;
         #$r |= ($l << 2) & 0x007F0000;
         #$r |= ($l << 3) & 0x7F000000;
         $r = ($l & 0x0000007F);
         $r |= ($l & 0x00003F80) << 1;
         $r |= ($l & 0x001FC000) << 2;
         $r |= ($l & 0x0FE00000) << 3;
         $header .= pack('N', $r)
      }

      die "Cannot open $path: $!" unless open F, '>', $path;
      die "binmode $path failed: $!" unless binmode F;
      die "Error writing $path: $!" unless print F $header, $tag;
      die "Cannot close $path: $!" unless close F
   }

   sub _mp3_frame{
      my ($fid, $ftxt) = @_;
      ::v("  MP3 frame: $fid: $ftxt") unless $fid eq 'COMM';
      my ($len, $txtenc);
      $txtenc = _mp3_string(\$ftxt, \$len);
      # (3.3) Frame header
      # [ID=4 chars;] Size=4 bytes=size - header (10); Flags=2 bytes
      $fid .= pack('CCCCCC',
            ($len & 0xFF000000) >> 24,
            ($len & 0x00FF0000) >> 16,
            ($len & 0x0000FF00) >>  8,
            ($len & 0x000000FF),
            0, 0);
      # (4.2) Text information
      $fid .= $txtenc;
      $fid .= $ftxt;
      $fid
   }

   sub _mp3_string{
      my ($txtr, $lenr) = @_;
      my $i = $$txtr;
      my $isascii;
      eval {$isascii = Encode::decode('ascii', $i, 1)};
      if($@ || !defined $isascii){
         $$txtr = Encode::encode('utf-16', $$txtr);
         $$lenr = bytes::length($$txtr) +2;
         return "\x01"
      }else{
         Encode::from_to($$txtr, 'utf-8', 'ascii');
         $$lenr = length($$txtr) +1;
         return "\x00"
      }
   }
} # }}} Enc::Helper::MP3

{package Enc::Helper::AAC; # {{{
   sub create_fd{
      my ($title, $path, $myid, $quali) = @_;

      my $comm = _create_comment($title);

      ::v("Creating AAC faac(1) $myid-quality encoder");
      Enc::Helper::utf8_echomode_on();
      my $cmd = '| faac ' . ($CDInfo::RawIsWAVE ? '' : '-XP ') .
            '--mpeg-vers 4 -w --tns ' .
            "$quali $comm -o $path - >/dev/null 2>&1";
      die "Cannot open AAC $myid: $cmd: $!" unless open(my $fd, $cmd);
      Enc::Helper::utf8_echomode_off();
      die "binmode error AAC$myid: $!" unless binmode $fd;
      $fd
   }

   sub _create_comment{
      my ($title) = @_;
      my ($ti, $res, $i) = ($title->{TAG_INFO}, '', undef);
      $i = $ti->{ARTIST};
         $i =~ s/"/\\"/g;
         $res .= "--artist \"$i\" ";
      $i = $ti->{ALBUM};
         $i =~ s/"/\\"/g;
         $res .= "--album \"$i\" ";
      $i = $ti->{TITLE};
         $i =~ s/"/\\"/g;
         $res .= "--title \"$i\" ";
      $res .= "--track \"$ti->{TRCK}\" "
            . (defined $ti->{TPOS} ? "--disc \"$ti->{TPOS}\" " :'')
            . "--genre '$ti->{GENRE}' "
            . (defined $ti->{YEAR} ? "--year \"$ti->{YEAR}\"" :'');
      $i = $ti->{COMM};
      if(defined $i){
         $i =~ s/"/\\"/g;
         $res .=" --comment \"S-MUSIC:COMM=$i\""
      }
      ::v("AACTag: $res");
      $res
   }
} # }}} Enc::Helper::AAC

{package Enc::Helper::OGG; # {{{
   sub create_fd{
      my ($title, $path, $myid, $quali) = @_;

      my $comm = _create_comment($title);

      ::v("Creating OGG ogg123(1) $myid-quality encoder");
      Enc::Helper::utf8_echomode_on();
      my $cmd = '| oggenc ' . ($CDInfo::RawIsWAVE ? '' : '-r ') .
            "-Q $quali $comm -o $path -";
      die "Cannot open OGG $myid: $cmd: $!" unless open(my $fd, $cmd);
      Enc::Helper::utf8_echomode_off();
      die "binmode error OGG$myid: $!" unless binmode $fd;
      $fd
   }

   sub _create_comment{
      my ($title) = @_;
      my ($ti, $res, $i) = ($title->{TAG_INFO}, '', undef);
      $i = $ti->{ARTIST};
         $i =~ s/"/\\"/g;
         $res .= "--artist \"$i\" ";
      $i = $ti->{ALBUM};
         $i =~ s/"/\\"/g;
         $res .= "--album \"$i\" ";
      $i = $ti->{TITLE};
         $i =~ s/"/\\"/g;
         $res .= "--title \"$i\" ";
      $res .= "--tracknum \"$ti->{TRACKNUM}\" "
            . (defined $ti->{TPOS}
               ? "--comment=\"TPOS=$ti->{TPOS}\" " : '')
            . "--comment=\"TRCK=$ti->{TRCK}\" "
            . "--genre \"$ti->{GENRE}\" "
            . (defined $ti->{YEAR} ? "--date \"$ti->{YEAR}\"" :'');
      $i = $ti->{COMM};
      if(defined $i){
         $i =~ s/"/\\"/g;
         $res .=" --comment \"S-MUSIC:COMM=$i\""
      }
      ::v("OGGTag: $res");
      $res
   }
} # }}} Enc::Helper::OGG

{package Enc::Helper::OPUS; # {{{
   sub create_fd{
      my ($title, $path, $myid, $quali) = @_;

      my $comm = _create_comment($title);

      ::v("Creating OPUS opusenc(1) $myid-quality encoder");
      Enc::Helper::utf8_echomode_on();
      my $cmd = '| opusenc ' . ($CDInfo::RawIsWAVE ? ''
            : '--raw --raw-rate=44100 ') .
            "--bitrate $quali $comm -o $path -";
      die "Cannot open OPUS $myid: $cmd: $!" unless open(my $fd, $cmd);
      Enc::Helper::utf8_echomode_off();
      die "binmode error OPUS$myid: $!" unless binmode $fd;
      $fd
   }

   sub _create_comment{
      my ($title) = @_;
      my ($ti, $res, $i) = ($title->{TAG_INFO}, '', undef);
      $i = $ti->{ARTIST};
         $i =~ s/"/\\"/g;
         $res .= "--artist \"$i\" ";
      $i = $ti->{ALBUM};
         $i =~ s/"/\\"/g;
         $res .= "--album \"$i\" ";
      $i = $ti->{TITLE};
         $i =~ s/"/\\"/g;
         $res .= "--title \"$i\" ";
      $res .= "--tracknumber \"$ti->{TRACKNUM}\" "
            . (defined $ti->{TPOS}
               ? "--comment=\"TPOS=$ti->{TPOS}\" " : '')
            . "--comment=\"TRCK=$ti->{TRCK}\" "
            . "--genre \"$ti->{GENRE}\" "
            . (defined $ti->{YEAR} ? "--date \"$ti->{YEAR}\"" :'');
      $i = $ti->{COMM};
      if(defined $i){
         $i =~ s/"/\\"/g;
         $res .=" --comment \"S-MUSIC:COMM=$i\""
      }
      ::v("OPUSTag: $res");
      $res
   }
} # }}} Enc::Helper::OPUS

{package Enc::Helper::FLAC; # {{{
   sub create_fd{
      my ($title, $path) = @_;

      my $comm = _create_comment($title);

      ::v("Creating FLAC flac(1) encoder");
      Enc::Helper::utf8_echomode_on();
      my $cmd = '| flac ' .
            ($CDInfo::RawIsWAVE ? ''
             : '--endian=little --sign=signed --channels=2 ' .
                  '--bps=16 --sample-rate=44100 ') .
            "--silent -8 -e -M -p $comm -o $path -";
      die "Cannot open FLACC $cmd: $!" unless open(my $fd, $cmd);
      Enc::Helper::utf8_echomode_off();
      die "binmode error FLAC: $!" unless binmode $fd;
      $fd
   }

   sub _create_comment{
      my ($title) = @_;
      my ($ti, $res, $i) = ($title->{TAG_INFO}, '', undef);
      $i = $ti->{ARTIST};
         $i =~ s/"/\\"/g;
         $res .= "-T artist=\"$i\" ";
      $i = $ti->{ALBUM};
         $i =~ s/"/\\"/g;
         $res .= "-T album=\"$i\" ";
      $i = $ti->{TITLE};
         $i =~ s/"/\\"/g;
         $res .= "-T title=\"$i\" ";
      $res .= "-T tracknumber=\"$ti->{TRACKNUM}\" "
            . (defined $ti->{TPOS} ? "-T TPOS=$ti->{TPOS} " : '')
            . "-T TRCK=$ti->{TRCK} "
            . "-T genre=\"$ti->{GENRE}\" "
            . (defined $ti->{YEAR} ? "-T date=\"$ti->{YEAR}\"" : '');
      $i = $ti->{COMM};
      if(defined $i){
         $i =~ s/"/\\"/g;
         $res .=" -T \"S-MUSIC:COMM=$i\""
      }
      ::v("FLACTag: $res");
      $res
   }
} # }}} Enc::Helper::FLAC
} # }}} Enc::Helper

{package Enc::Coder; # {{{
   our @ISA = 'Enc';

   # Super funs # {{{
   sub new{
      my ($title, $name, $ext) = @_;
      my $self = scalar caller;
      $self = {name => $name, fd => undef,
            path => $title->{TARGET_PLAIN} . '.' . $ext};
      bless $self
   }

   sub write{
      my ($self, $data) = @_;
      if($self->{fd}){
         die "Write error $self->{name}: $!" unless print {$self->{fd}} $data
      }
      $self
   }

   sub del{
      my ($self) = @_;
      if($self->{fd}){
         die "Close error $self->{name}: $!" unless close $self->{fd}
      }
      $self
   }
   # }}}

# MP3 {{{
{package Enc::Coder::MP3;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'MP3', 'mp3');
      $self = bless $self;
      $self->{fd} = Enc::Helper::MP3::create_fd($title, $self->{path},
            'high', '-V 0');
      $self
   }
}

{package Enc::Coder::MP3LO;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'MP3LO', 'lo.mp3');
      $self = bless $self;
      $self->{fd} = Enc::Helper::MP3::create_fd($title, $self->{path},
            'low', '-V 7');
      $self
   }
}
# }}}

# AAC {{{
{package Enc::Coder::AAC;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'AAC', 'mp4');
      $self = bless $self;
      $self->{fd} = Enc::Helper::AAC::create_fd($title, $self->{path},
            'high', '-q 300');
      $self
   }
}

{package Enc::Coder::AACLO;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'AACLO', 'lo.mp4');
      $self = bless $self;
      $self->{fd} = Enc::Helper::AAC::create_fd($title, $self->{path},
            'low', '-q 80');
      $self
   }
}
# }}}

# {{{ OGG
{package Enc::Coder::OGG;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'OGG', 'ogg');
      $self = bless $self;
      $self->{fd} = Enc::Helper::OGG::create_fd($title, $self->{path},
            'high', '-q 8.5');
      $self
   }
}

{package Enc::Coder::OGGLO;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'OGGLO', 'lo.ogg');
      $self = bless $self;
      $self->{fd} = Enc::Helper::OGG::create_fd($title, $self->{path},
            'low', '-q 3.8');
      $self
   }
}
# }}}

# {{{ OPUS
{package Enc::Coder::OPUS;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'OPUS', 'opus');
      $self = bless $self;
      $self->{fd} = Enc::Helper::OPUS::create_fd($title, $self->{path},
            'high', '96');
      $self
   }
}

{package Enc::Coder::OPUSLO;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'OPUSLO', 'lo.opus');
      $self = bless $self;
      $self->{fd} = Enc::Helper::OPUS::create_fd($title, $self->{path},
            'low', '24');
      $self
   }
}
# }}}

# FLAC {{{
{package Enc::Coder::FLAC;
   our @ISA = 'Enc::Coder';

   sub new{
      my ($title) = @_;
      my $self = Enc::Coder::new($title, 'FLAC', 'flac');
      $self = bless $self;
      $self->{fd} = Enc::Helper::FLAC::create_fd($title, $self->{path});
      $self
   }
} # }}}
} # }}} Enc::Coder
} # }}} Enc

{package main; exit main_fun()}

# s-it-mode
