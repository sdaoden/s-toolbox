#!/usr/bin/env perl
my $SELF = 's-disc-ripper.pl'; #@ part of S-Music; handles CD ripping.
my $VERSION = '0.5.2';
my $CONTACT = 'Steffen Nurpmeso <steffen@sdaoden.eu>';
#@ Requirements:
#@ - s-cdda for CD-ROM access (https://ftp.sdaoden.eu/s-cdda-latest.tar.gz).
#@   P.S.: not on MacOS X/Darwin, but not tested there for many years
#@ - unless --no-volume-normalize is used: sox(1) (sox.sourceforge.net)
#@   NOTE: sox(1) changed - see $NEW_SOX below
#@ - if MP3 is used: lame(1) (www.mp3dev.org)
#@ - if MP4/AAC is used: faac(1) (www.audiocoding.com)
#@ - if Ogg/Vorbis is used: oggenc(1) (www.xiph.org)
#@ - if FLAC is used: flac(1) (www.xiph.org)
#@ - OPTIONAL: CDDB.pm (www.CPAN.org)
#@
#@ Copyright (c) 1998 - 2003, 2010 - 2014, 2016 - 2018,
#@               2020 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>
#@ SPDX-License-Identifier: ISC
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

# New sox(1) (i guess this means post v14) with '-e signed-integer' instead of
# -s, '-b 16' instead of -w and -n (null device) instead of -e (to stop input
# file processing)
my $NEW_SOX = 1;

# Dito: change the undef to '/Desired/Path'
my $MUSIC_DB = defined $ENV{S_MUSIC_DB} ? $ENV{S_MUSIC_DB} : undef;
my $CDROM = defined $ENV{CDROM} ? $ENV{CDROM} : undef;
my $TMPDIR = (defined $ENV{TMPDIR} && -d $ENV{TMPDIR}) ? $ENV{TMPDIR} : '/tmp';

# Only MacOS X
my $CDROMDEV = (defined $ENV{CDROMDEV} ? $ENV{CDROMDEV} #: undef;
      : defined $CDROM ? $CDROM : undef);

## -- >8 -- 8< -- ##

require 5.008_001;
use diagnostics -verbose;
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

my $INTRO = "$SELF (v$VERSION): integrate audio disc (tracks) into S-Music DB";

my ($RIP_ONLY, $ENC_ONLY, $NO_VOL_NORM, $VERBOSE) = (0, 0, 0, 0);
my ($CLEANUP_OK, $WORK_DIR, $TARGET_DIR, %CDDB) = (0);

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
    OR    : \$ PERL5OPT=-C; export PERL5OPT
    (OR   : \$ PERL5OPT=-C $SELF)

  Please read the perlrun(1) manual page for more on this topic.
WARNING WARNING WARNING
__EOT__
   }

   # Also verifies we have valid (DB,TMP..) paths
   command_line();

   $SIG{INT} = sub {print STDERR "\nInterrupted ... bye\n"; exit 1};
   print $INTRO, "\nPress <CNTRL-C> at any time to interrupt\n";

   my ($info_ok, $needs_cddb) = (0, 1);
   # Unless we have seen --encode-only=ID
   unless(defined $CDInfo::CDId){
      CDInfo::discover();
      $info_ok = 1
   }

   $WORK_DIR = "$TMPDIR/s-disc-ripper.$CDInfo::CDId";
   $TARGET_DIR = "$MUSIC_DB/disc.${CDInfo::CDId}-";
   if(-d "${TARGET_DIR}1"){
      $TARGET_DIR = quick_and_dirty_dir_selector()
   }else{
      $TARGET_DIR .= '1'
   }
   print <<__EOT__;

TARGET directory : $TARGET_DIR
WORKing directory: $WORK_DIR
(In worst-case error situations it may be necessary to remove those manually.)
__EOT__
   die 'Non-existent session cannot be resumed via --encode-only'
      if $ENC_ONLY && ! -d $WORK_DIR;
   unless(-d $WORK_DIR){
      die "Cannot create $WORK_DIR: $!" unless mkdir $WORK_DIR
   }
   unless($RIP_ONLY || -d $TARGET_DIR){
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
      die 'Database corrupted - remove TARGET and re-rip entire disc'
            unless MBDB::read_data();
      $needs_cddb = 0
   }elsif($info_ok > 0){
      CDInfo::write_data()
   }

   if(!$RIP_ONLY && $needs_cddb){
      cddb_query();
      MBDB::create_data()
   }

   # Handling files
   if($RIP_ONLY || !$ENC_ONLY){
      user_tracks();
      Title::rip_all_selected();
      print "\nUse --encode-only=$CDInfo::CDId to resume ...\n" if $RIP_ONLY
   }elsif($ENC_ONLY){
      # XXX In this case we are responsible to detect whether we ripped WAVE
      # XXX or RAW files, a.k.a. set $CDInfo::RawIsWAVE!  Yes, this is a hack
      my @rawfl = glob("$WORK_DIR/*." . ($CDInfo::RawIsWAVE ? 'wav' : 'raw'));
      die '--encode-only session on empty file list' if @rawfl == 0;
      foreach(sort @rawfl){
         die '--encode-only session: illegal filenames exist'
               unless /(\d+).(raw|wav)$/;
         my $i = int $1;
         die "\
--encode-only session: track $_ is unknown!
It does not seem to belong to this disc, you need to re-rip it."
               unless $i > 0 && $i <= $CDInfo::TrackCount;
         my $t = $Title::List[$i - 1];
         $t->{IS_SELECTED} = 1
      }
      #print "\nThe following raw tracks will now be encoded:\n  ";
      #print "$_->{NUMBER} " foreach (@Title::List);
      #print "\n  Is this really ok?   You may interrupt now! ";
      #exit(5) unless user_confirm()
   }

   unless($RIP_ONLY){
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
         'r|rip-only' => \$RIP_ONLY,
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
      if($RIP_ONLY){
         $emsg = '--rip-only and --encode-only are mutual exclusive';
         goto jdocu
      }
      if($ENC_ONLY !~ /[[:alnum:]]+/){
         $emsg = "$ENC_ONLY is not a valid CD(DB)ID";
         goto jdocu
      }
      $CDInfo::CDId = lc $ENC_ONLY;
      $ENC_ONLY = 1
   }

   unless($RIP_ONLY){
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
${INTRO}

 $SELF -h|--help  |  -g|--genre-list

 $SELF [-v] [-d DEV] -r|--rip-only
   Only rip audio tracks from CD-ROM
 $SELF [-v] [-m|--music-db PATH] [-f|--formats ..]
      [--no-volume-normalize] -e|--encode-only CDID
   Only encode a --rip-only session

 $SELF [-v] [-d DEV] [-m|--music-db PATH] [-f|--formats ..]
      [--no-volume-normalize]
   Do the entire processing

-d|--device DEV       Use CD-ROM DEVice; else \$CDROM; else s-cdda(1) fallback
-e|--encode-only CDID Resume a --rip-only session, which echoed the CDID to use
-f|--formats LIST     Comma-separated list of audio target formats, else
                      \$S_MUSIC_FORMATS ($flr)
-m|--music-db PATH    S-Music DB directory; else \$S_MUSIC_DB
-r|--rip-only         Only rip data, then exit; resume with --encode-only
--no-volume-normalize Do not apply volume normalization
-v|--verbose         Be more verbose; does not delete temporary files!

Honours \$TMPDIR.  Bugs/Contact via $CONTACT
__EOT__

   if($^O eq 'darwin'){
      print $FH <<__EOT__;
MacOS only:
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
   print ' [Nn (or else)] ';
   my $u = <STDIN>;
   $| = $save;
   chomp $u;
   ($u =~ /n/i) ? 0 : 1
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
         if(/^\s*\[ALBUMSET\]/) {$tr = \$ast}
         elsif(/^\s*\[ALBUM\]/) {$tr = \$at}
         elsif(/^\s*\[CDDB\]/) {next}
         elsif(/^\s*\[\w+\]/) {last}
         elsif(defined $tr && /^\s*TITLE\s*=\s*(.+?)\s*$/) {$$tr = $1}
      }
      die "Cannot close $f: $!" unless close F;
      unless(defined $at){
         print "  [] No TITLE entry in $f!\n  ",
              "Disc is corrupted and must be re-ripped!\n";
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
   unless($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @dlist){
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

sub cddb_query{ # {{{
   sub _utf8ify{
      # String comes from CDDB, may be latin1 or utf-8
      my ($ins) = @_;
      my ($ous, $isutf8);
      $ous = $ins;
      eval {$isutf8 = Encode::decode('utf-8', $ins, 1)};
      if($@ || !defined $isutf8){
         Encode::from_to($ous, 'latin1', 'utf-8')
      }else{
         #Encode::from_to($ous, 'utf-8', 'utf-8')
      }
      Encode::_utf8_on($ous);
      $ous
   }

   sub _fake{
      %CDDB = ();
      $CDDB{GENRE} = genre('Humour');
      $CDDB{ARTIST} = 'Unknown';
      $CDDB{ALBUM} = 'Unknown';
      $CDDB{YEAR} = '';
      my @titles;
      $CDDB{TITLES} = \@titles;
      for(my $i = 1; $i <= $CDInfo::TrackCount; ++$i){
         my $s = 'TITLE ' . $i;
         push @titles, $s
      }
      return
   }

   print "\n";
   eval 'require CDDB';
   if($@){
      print "Failed to load the perl(1) CDDB.pm module!\n",
         '  Is it installed?  Please search the internet, ',
            "install via \"\$ cpan CDDB\".\n",
         '  Confirm to use CDDB.pm, an empty template is used otherwise:'
   }else{
      print 'Query CDDB online, an empty template is used otherwise:'
   }
   unless(user_confirm()){
      print "  Creating empty template ...\n";
      return _fake();
   }

   print "  Starting CDDB query for $CDInfo::CDId\n";
   my $cddb = new CDDB;
   die "Cannot create CDDB object: $!" unless defined $cddb;
   my @toc = map {$_ + 150} @CDInfo::TracksLBA;
   pop @toc;
   my @discs = $cddb->get_discs($CDInfo::CDId, \@toc, $CDInfo::TotalSeconds);

   if(@discs == 0){
      print "! CDDB did not match, i will create entry fakes!\n",
         '! Maybe there is no network connection? Shall i continue? ';
      exit 10 unless user_confirm();
      return _fake();
   }

   my ($usr, $dinf);
jAREDO:
   print "  (NOTE: terminal may not be able to display charset!)\n";

   $usr = 1;
   foreach(@discs){
      my ($genre, undef, $title) = @$_; # (cddb_id)
      print "  [$usr] Genre:$genre, Title:$title\n";
      ++$usr
   }
   print "  [0] None of those (creates a local entry fakes)\n";

jREDO:
   print "  Choose the number to use: ";
   $usr = <STDIN>;
   chomp $usr;
   unless($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @discs){
      print "! I am expecting one of the [numbers] ... !\n";
      goto jREDO
   }
   if($usr == 0){
      print "  creating entry fakes ...\n";
      return _fake();
   }
   $usr = $discs[--$usr];

   print "\nStarting CDDB detail read for $usr->[0]/$CDInfo::CDId\n";
   $dinf = $cddb->get_disc_details($usr->[0], $CDInfo::CDId);
   die 'CDDB failed to return disc details' unless defined $dinf;

   # Prepare TAG as UTF-8 (CDDB entries may be ISO-8859-1 or UTF-8)
   %CDDB = ();
   $CDDB{GENRE} = genre($usr->[0]);
   unless(defined $CDDB{GENRE}){
      $CDDB{GENRE} = genre('Humour');
      print "! CDDB entry has illegal GENRE - using $CDDB{GENRE}\n"
   }
   {  my $aa = $usr->[2];
      my ($art, $alb, $i);
      $i = index $aa, '/';
      if($i < 0){
         $art = $alb = $aa
      }else{
         $art = substr $aa, 0, $i;
         $alb = substr $aa, ++$i
      }
      $art =~ s/^\s*(.*?)\s*$/$1/;
      $CDDB{ARTIST} = _utf8ify($art);
      $alb =~ s/^\s*(.*?)\s*$/$1/;
      $CDDB{ALBUM} = _utf8ify($alb)
   }
   $CDDB{YEAR} = defined $dinf->{dyear} ? $dinf->{dyear} : '';
   $CDDB{TITLES} = $dinf->{ttitles};
   foreach(@{$dinf->{ttitles}}){
      s/^\s*(.*?)\s*$/$1/;
      _utf8ify(\$_)
   }

   print "  CDDB disc info for CD(DB)ID=$CDInfo::CDId\n",
      "  (Again: terminal may not be able to display charset):\n",
      "    Genre=$CDDB{GENRE}, Year=$CDDB{YEAR}\n",
      "    Artist=$CDDB{ARTIST}\n",
      "    Album=$CDDB{ALBUM}\n",
      "    Titles in order:\n     ",
      join("\n     ", @{$CDDB{TITLES}}),
      "\n  Is this *really* the desired CD? ";
   goto jAREDO unless user_confirm()
} # }}}

sub user_tracks{ # {{{
   print "\nDisc $CDInfo::CDId contains $CDInfo::TrackCount songs - ",
      'shall all be ripped?';
   if(user_confirm()){
      print "  Whee - all songs will be ripped!\n";
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
      print "? So why are you using a disc ripper, then?\n";
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
   our $RawIsWAVE = 0;
   # Id field may also be set from command_line()
   # Mostly set by _calc_id() or parse() only (except Ripper)
   our ($CDId, $MBrainzDiscId, $TotalSeconds,
      $TrackCount, $TrackFirst, $TrackLast,
      $FileRipper, $DatFile);
   our @TracksLBA = ();
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
         "\n  Track: count $TrackCount, first $TrackFirst, last $TrackLast\n"
   }

   sub _os_darwin{ # {{{
      my $drive = defined $CDROM ? $CDROM : 1;
      $DevId = defined $CDROMDEV ? $CDROMDEV : $drive;
      print "  Darwin/Mac OS X: drive $drive and /dev/disk$DevId\n";
      print "  !! WARNING: Darwin/MAC OS X not tested for a long time!\n";

      $FileRipper = sub{
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
                  goto jdarwin_rip_stop
               }
               $o += $w;
               $r -= $w
            }
         }

jdarwin_rip_stop:
         close OUTFH; # XXX
         close INFH; # XXX
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
      $RawIsWAVE = 1;

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

      $FileRipper = sub{
         my $title = shift;
         return undef if 0 == system("s-cdda $dev " . ($VERBOSE ? '-v ' : '') .
            '-r ' .  $title->{NUMBER} . ' > ' .  $title->{RAW_FILE});
         return "! Device $dev: cannot rip track $title->{NUMBER}: $?\n"
      };

      $l = 's-cdda ' . $dev . ($VERBOSE ? ' -v' : '');
      ::v("Invoking $l");
      $l = `$l`;
      return "$dev: failed reading TOC: $!" if $?;
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
         }elsif($l =~ /^x=(\d+)\s+.*$/){
         }elsif($l =~ /^x0_count=(\d+)\s+
               x0_track_first=(\d+)\s+
               x0_track_last=(\d+)
               .*$/x){
         }else{
            #$emsg .= "! Invalid line: $l\n"
         }
      }
      $emsg .= "! No Lead-out information encountered\n" unless $had_leadout;
      $emsg = _check_cddb_state($emsg);
      return $emsg if length $emsg;

      _calc_cdid(\@cdtoc);
      _calc_mb_discid(\@cdtoc);
      return undef
   } # }}}

   # Calculated CD(DB)-Id and *set*CDInfo*fields*, ditto MusicBrainz Disc ID
   sub _calc_cdid{ # {{{
      # This is a stripped down version of CDDB.pm::calculate_id()
      my $cdtocr = shift;
      my ($sec_first, $sum);
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
            $TotalSeconds = $sec_begin;
            last
         }
         map {$sum += $_} split //, $sec_begin;
      }
      $CDId = sprintf("%02x%04x%02x",
            $sum % 255, $TotalSeconds - $sec_first, $TrackCount)
   }

   sub _calc_mb_discid{
      my $cdtocr = shift;

      my $d = Digest->new("SHA-1");
      $d->add(sprintf '%02X', $TrackFirst);
      $d->add(sprintf '%02X', $TrackLast);

      my $i = @$cdtocr;
      $d->add(sprintf '%08X', @$cdtocr[--$i] + 150);
      for(my $j = 0; $j < $i; ++$j){
         $d->add(sprintf '%08X', @$cdtocr[$j] + 150)
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
      print DAT "# $SELF CDDB info for project $CDId\n",
         "# Do not modify!   Or project needs to be re-ripped!!\n",
         "CDID = $CDId\n",
         "MBRAINZ_DISC_ID = $MBrainzDiscId\n",
         'TRACKS_LBA = ', join(' ', @TracksLBA), "\n",
         "TRACK_FIRST = $TrackFirst\n",
         "TRACK_LAST = $TrackLast\n",
         "TOTAL_SECONDS = $TotalSeconds\n",
         "RAW_IS_WAVE = 1\n";
      die "Cannot close $f: $!" unless close DAT
   }

   sub read_data{
      my $f = $DatFile;
      ::v("CDInfo::read_data($f)");
      die "Cannot open $f: $!.\nCannot continue - remove $WORK_DIR and re-rip!"
         unless open DAT, '<:encoding(UTF-8)', $f;
      my @lines = <DAT>;
      die "Cannot close $f: $!" unless close DAT;

      # It may happen that this is called even though discover()
      # already queried the disc in the drive - nevertheless: resume!
      my ($old_id, $laref) = ($CDId, shift);
      $RawIsWAVE = $TotalSeconds = $CDId = $MBrainzDiscId =
         $TrackCount = $TrackFirst = $TrackLast = undef;
      @TracksLBA = ();

      my $emsg = '';
      foreach(@lines){
         chomp;
         next if /^\s*#/;
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
         }elsif($k eq 'TOTAL_SECONDS'){
            $emsg .= "! Invalid TOTAL_SECONDS: $v\n" unless $v =~ /^(\d+)$/;
            $TotalSeconds = $1
         }elsif($k eq 'TRACK_FIRST'){
            $emsg .= "! Invalid TRACK_FIRST: $v\n" unless $v =~ /^(\d+)$/;
            $TrackFirst = $1
         }elsif($k eq 'TRACK_LAST'){
            $emsg .= "! Invalid TRACK_LAST: $v\n" unless $v =~ /^(\d+)$/;
            $TrackLast = $1
         }elsif($k eq 'RAW_IS_WAVE'){
            $emsg .= "! Invalid RAW_IS_WAVE: $v\n" unless $v =~ /^(\d)$/;
            $RawIsWAVE = $1
         }else{
            $emsg .= "! Invalid line: $_\n"
         }
      }
      $emsg .= "! Corrupted: no CDID seen\n" unless defined $CDId;
      $emsg .= "! Corrupted: no MBRAINZ_DISC_ID seen\n"
            unless defined $MBrainzDiscId;
      $emsg .= "! Corrupted: no TOTAL_SECONDS seen\n"
            unless defined $TotalSeconds;
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
} # }}}

# Title represents - a track
{package Title; # {{{
   # Title::vars,funs {{{
   our @List;

   sub create_that_many{
      die 'Title::create_that_many: impl error' if @List != 0;
      my $no = shift;
      for(my $i = 1; $i <= $no; ++$i){
         Title->new($i)
      }
   }

   sub rip_all_selected{
      print "\nRipping selected tracks:\n";
      foreach my $t (@List){
         next unless $t->{IS_SELECTED};
         if(-f $t->{RAW_FILE}){
            print "  Raw ripped track $t->{NUMBER} exists - re-rip? ";
            next unless ::user_confirm()
         }

         print "  Rip track $t->{NUMBER} -> $t->{RAW_FILE}\n";
         my $emsg = &$CDInfo::FileRipper($t);
         if(defined $emsg){
            print $emsg,
               "!  Shall i deselect the track (else quit)?";
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
         RAW_FILE => "$WORK_DIR/$nos" . ($CDInfo::RawIsWAVE ? '.wav' : '.raw'),
         TARGET_PLAIN => "$TARGET_DIR/$nos",
         IS_SELECTED => 0,
         TAG_INFO => Title::TagInfo->new()
      };
      $self = bless $self, $class;
      $List[$no - 1] = $self;
      return $self
   }
   # }}}

# ID3v2.3 a.k.a. supported oggenc(1)/faac(1) tag stuff is bundled in here;
# fields are set to something useful by MBDB:: below
{package Title::TagInfo; # {{{
   sub new{
      my ($class) = @_;
      ::v("Title::TagInfo::new()");
      my $self = {};
      $self = bless $self, $class;
      return $self->reset()
   }

   sub reset{
      my $self = shift;
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
      return $self
   }
} # }}}
} # }}}

# MBDB - MusicBox (per-disc) database handling.
# This is small minded and a dead end street for all the data - but that is
# really sufficient here,
# because if the database has been falsely edited the user must correct it!
# At least a super-object based approach should have been used though.
# All strings come in as UTF-8 and remain unmodified
{package MBDB; # {{{
   # MBDB::vars,funs # {{{
   our ($EditFile, $FinalFile,
      $CDDB, $AlbumSet, $Album, $Cast, $Group, # [GROUP] objects
      $Error, @Data, # I/O & content
      @SongAddons, $SortAddons # First-Round addons
   );

   sub init_paths{
      $EditFile = "$WORK_DIR/template.dat";
      $FinalFile = "$TARGET_DIR/music.db"
   }

   sub _reset_data{
      $AlbumSet = $Album = $Cast = $Group = undef;
      $_->{TAG_INFO}->reset() foreach (@Title::List);
      $Error = 0; @Data = ()
   }

   sub read_data {return _read_data($FinalFile)}

   sub create_data{
      my $ed = defined $ENV{VISUAL} ? $ENV{VISUAL} : '/usr/bin/vi';
      print "\nCreating S-Music per-disc database\n";
      @SongAddons = (); $SortAddons = '';
      _create_addons();

      my @old_data;
jREDO:
      @old_data = @Data;
      _reset_data();
      _write_editable(\@old_data);
      print "  Template: $EditFile\n",
         "  Please verify and edit this file as necessary\n",
         "  Shall i invoke EDITOR $ed? ";
      if(::user_confirm()){
         my @args = ($ed, $EditFile);
         system(@args)
      }else{
         print "  Ok, waiting: hit <RETURN> to continue ...";
         $ed = <STDIN>
      }
      if(!_read_data($EditFile)){
         print "! Errors detected - edit once again!\n";
         goto jREDO
      }
      @SongAddons = (); $SortAddons = '';

      print "  Once again - please verify the content:\n",
         "  (Again: terminal may not be able to display charset):\n";
      print "    $_\n" foreach (@Data);
      print "  Is this data *really* OK? ";
      goto jREDO unless ::user_confirm();

      _write_final()
   }

   sub _create_addons{
      my $cddbt = $CDDB{TITLES};
      foreach my $title (@Title::List){
         my $i = $title->{INDEX};
         my $t = $cddbt->[$i];
         if($t =~ /^\s*(.+)\/\s*(.+)\s*$/){
            my ($a, $t) = ($1, $2);
            $a =~ s/\s*$//;
            # First the plain versions
            $SortAddons .= "\n #" . _create_sort($a);
            $SongAddons[$i] = "\n #TITLE = $t\n #ARTIST = $a";
            # But try to take advantage of things like "feat." etc..
            my @as = _try_split_artist($a);
            foreach $a (@as){
               $SortAddons .= "\n   #" . _create_sort($a);
               $SongAddons[$i] .= "\n  #ARTIST = $a"
            }
         }
      }
   }

   sub _create_sort{
      my $sort = shift;
      if($sort =~ /^The/i && $sort !~ /^the the$/i){ # The The, The
         $sort =~ /^the\s+(.+)\s*$/i;
         $sort = "SORT = $1, The (The $1)"
      }elsif($sort =~ /^\s*(\S+)\s+(.+)\s*$/){
         $sort = "SORT = $2, $1 ($1 $2)"
      }else{
         $sort = "SORT = $sort ($sort)"
      }
      return $sort
   }

   sub _try_split_artist{
      my ($art, $any, @r) = (shift, 0);
      while($art =~ /(.+?)(?:feat(?:uring|\.)?|and|&)(.+)/i){
         $any = 1;
         $art = $2;
         my $e = $1;
         $e =~ s/^\s*//;
         $e =~ s/\s*$//;
         push @r, $e
      }
      if($any){
         $art =~ s/^\s*//;
         push @r, $art
      }
      return @r
   }

   sub _write_editable{
      my $dataref = shift;
      my $df = $EditFile;
      ::v("Writing editable S-Music database file as $df");
      die "Cannot open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
      if(@$dataref > 0){
         die "Error writing $df: $!"
               unless print DF "\n# CONTENT OF LAST EDIT AT END OF FILE!\n\n"
      }
      my $cddbt = $CDDB{TITLES};
      my $sort = _create_sort($CDDB{ARTIST});

      die "Error writing $df: $!"
            unless print DF _help_text(), "\n",
               MBDB::ALBUMSET::help_text(),
               "#[ALBUMSET]\n#TITLE = \n#SETCOUNT = 2\n",
               "\n",
               MBDB::ALBUM::help_text(),
               "[ALBUM]\n#SETPART = 1\n",
               "TITLE = $CDDB{ALBUM}\n",
               "TRACKCOUNT = ", scalar @$cddbt, "\n",
               ((length($CDDB{YEAR}) > 0) ? "YEAR = $CDDB{YEAR}" : '#YEAR = '),
               "\nGENRE = $CDDB{GENRE}\n",
               "#GAPLESS = 0\n#COMPILATION = 0\n",
               "\n",
               MBDB::CAST::help_text(),
               "[CAST]\n",
               "ARTIST = $CDDB{ARTIST}\n",
               "# Please CHECK the SORT entry!\n",
               "$sort$SortAddons\n\n",
               MBDB::GROUP::help_text(),
               "#[GROUP]\n#LABEL = \n#GAPLESS = 0\n",
               "\n",
               MBDB::TRACK::help_text();

      foreach my $title (@Title::List){
         my $n = $title->{NUMBER};
         my $i = $title->{INDEX};
         my $a = (@SongAddons && defined $SongAddons[$i])?$SongAddons[$i]:'';
         die "Error writing $df: $!"
               unless print DF "[TRACK]\nNUMBER = $n\n",
                  "TITLE = $cddbt->[$i]$a\n\n"
      }

      if(@$dataref > 0){
         die "Error writing $df: $!"
               unless print DF "\n# CONTENT OF FORMER USER EDIT:\n";
         foreach(@$dataref){
            die "Error writing $df: $!" unless print DF "#$_\n"
         }
      }
      die "Error writing $df: $!"
            unless print DF "# vim:set fenc=utf-8 syntax=cfg tw=4221 et:\n";
      die "Cannot close $df: $!" unless close DF
   }

   sub _help_text{
      return <<__EOT__
# S-Music database, CDDB info: $CDDB{GENRE}/$CDInfo::CDId
# This file is and used to be in UTF-8 encoding (codepage,charset) ONLY!
# Syntax (processing is line based):
# - Leading and trailing whitespace is ignored
# - Empty lines are ignored
# - Lines starting with # are comments and discarded
# - [GROUPNAME] on a line of its own begins a group
# - And there are 'KEY = VALUE' lines - surrounding whitespace is trimmed away
# - Definition ORDER IS IMPORTANT!
__EOT__
   }

   sub _write_final{
      my $df = $FinalFile;
      ::v("Creating final S-Music database file as $df");
      die "Cannot open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
      die "Error writing $df: $!"
            unless print DF "[CDDB]\n",
                "CDID = $CDInfo::CDId\n",
                "MBRAINZ_DISC_ID = $CDInfo::MBrainzDiscId\n",
                "TRACKS_LBA = ", join(' ', @CDInfo::TracksLBA), "\n",
                "TRACK_FIRST = $CDInfo::TrackFirst\n",
                "TRACK_LAST = $CDInfo::TrackLast\n";
      foreach(@Data){
         die "Error writing $df: $!" unless print DF $_, "\n"
      }
      die "Cannot close $df: $!" unless close DF
   }

   sub _read_data{
      my $df = shift;
      my $is_final = ($df eq $FinalFile);
      _reset_data();

      die "Cannot open $df: $!" unless open DF, '<:encoding(UTF-8)', $df;
      my ($emsg, $entry) = (undef, undef);
      while(<DF>){
         s/^\s*(.*?)\s*$/$1/;
         next if length() == 0 || /^#/;
         my $line = $_;

         if($line =~ /^\[(.*?)\]$/){
            my $c = $1;
            if(defined $entry){
               $emsg = $entry->finalize();
               $entry = undef;
               if(defined $emsg){
                  $Error = 1;
                  print "! ERROR: $emsg\n";
                  $emsg = undef
               }
            }elsif($is_final && $c ne 'CDDB'){
               $emsg = 'Database corrupted - it does not start with a ' .
                     '(internal) [CDDB] group';
               goto jERROR
            }

            no strict 'refs';
            my $class = "MBDB::${c}";
            my $sym = "${class}::new";
            unless(%{"${class}::"}){
               $emsg = "Illegal command: [$c]";
               goto jERROR
            }
            $entry = &$sym($class, \$emsg);
         }elsif($line =~ /^(.*?)\s*=\s*(.*)$/){
            my ($k, $v) = ($1, $2);
            unless(defined $entry){
               $emsg = "KEY=VALUE line without group: <$k=$v>";
               goto jERROR
            }
            $emsg = $entry->set_tuple($k, $v)
         }else{
            $emsg = "Line invalid: $_"
         }

         if(defined $emsg){
jERROR:     $Error = 1;
            print "! ERROR: $emsg\n";
            die "Disc database is corrupted!\n" .
               "Remove $TARGET_DIR (!) and re-rip disc!"
                  if $is_final;
            $emsg = undef
         }
      }
      if(defined $entry && defined($emsg = $entry->finalize())){
         $Error = 1;
         print "! ERROR: $emsg\n"
      }
      die "Cannot close $df: $!" unless close DF;

      for(my $i = 1; $i <= $CDInfo::TrackCount; ++$i){
         next if $Title::List[$i - 1]->{TAG_INFO}->{IS_SET};
         $Error = 1;
         print "! ERROR: no entry for track number $i found\n"
      }
      $Error == 0
   }
   # }}}

{package MBDB::CDDB; # {{{
   sub is_key_supported{
      $_[0] eq 'CDID' || $_[0] eq 'MBRAINZ_DISC_ID' ||
         $_[0] eq 'TRACKS_LBA' ||
         $_[0] eq 'TRACK_FIRST' || $_[0] eq 'TRACK_LAST'
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::CDDB){
         $$emsgr = 'There may only be one (internal!) [CDDB] section';
         return undef
      }
      ::v("MBDB::CDDB::new()");
      push @MBDB::Data, '[CDDB]';
      my @dat;
      my $self = {
         objectname => 'CDDB',
         CDID => undef, MBRAINZ_DISC_ID => undef,
         TRACKS_LBA => undef,
         TRACK_FIRST => undef, TRACK_LAST => undef,
         _data => \@dat
      };
      $self = bless $self, $class;
      $MBDB::CDDB = $self
   }
   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
      return "$self->{objectname}: $k already set" if defined $self->{$k};
      $self->{$k} = $v;
      push @{$self->{_data}}, "$k = $v";
      push @MBDB::Data, "$k = $v";
      undef
   }
   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      return 'CDDB requires CDID, MBRAINZ_DISC_ID, ' .
               'TRACKS_LBA, TRACK_FIRST and TRACK_LAST;'
            unless(defined $self->{CDID} && defined $self->{MBRAINZ_DISC_ID} &&
               defined $self->{TRACKS_LBA} &&
               defined $self->{TRACK_FIRST} && defined $self->{TRACK_LAST});
      undef
   }
} # }}}

{package MBDB::ALBUMSET; # {{{
   sub help_text{
      return <<__EOT__
# [ALBUMSET]: TITLE, SETCOUNT
#  If a multi-CD-Set is ripped each CD gets its own database file, say;
#  ALBUMSET and the SETPART field of ALBUM are how to group 'em
#  nevertheless: repeat the same ALBUMSET and adjust the SETPART field.
#  (No GENRE etc.: all that is in ALBUM only ... as you can see)
__EOT__
   }
   sub is_key_supported{
      $_[0] eq 'TITLE' || $_[0] eq 'SETCOUNT'
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::AlbumSet){
         $$emsgr = 'ALBUMSET yet defined';
         return undef
      }
      ::v("MBDB::ALBUMSET::new()");
      push(@MBDB::Data, '[ALBUMSET]');
      my $self = {
         objectname => 'ALBUMSET',
         TITLE => undef, SETCOUNT => undef
      };
      $self = bless $self, $class;
      $MBDB::AlbumSet = $self
   }
   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
      $self->{$k} = $v;
      push @MBDB::Data, "$k = $v";
      undef
   }
   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      my $emsg = undef;
      $emsg .= 'ALBUMSET requires TITLE and SETCOUNT;'
            unless defined $self->{TITLE} && defined $self->{SETCOUNT};
      $emsg
   }
} # }}}

{package MBDB::ALBUM; # {{{
   sub help_text{
      return <<__EOT__
# [ALBUM]: TITLE, TRACKCOUNT, (SETPART, YEAR, GENRE, GAPLESS, COMPILATION)
#  If the album is part of an ALBUMSET TITLE may only be 'CD 1' - it is
#  required nevertheless even though it could be deduced automatically
#  from the ALBUMSET's TITLE and the ALBUM's SETPART - sorry!
#  I.e. SETPART is required, then, and the two TITLEs are *concatenated*.
#  GENRE is one of the widely (un)known ID3 genres.
#  GAPLESS states wether there shall be no silence in between tracks,
#  and COMPILATION wether this is a compilation of various-artists or so.
__EOT__
   }
   sub is_key_supported{
      my $k = shift;
      ($k eq 'TITLE' ||
         $k eq 'TRACKCOUNT' ||
         $k eq 'SETPART' || $k eq 'YEAR' || $k eq 'GENRE' ||
         $k eq 'GAPLESS' || $k eq 'COMPILATION')
   }

   sub new{
      my ($class, $emsgr) = @_;
      if(defined $MBDB::Album){
         $$emsgr = 'ALBUM yet defined';
         return undef
      }
      ::v("MBDB::ALBUM::new()");
      push(@MBDB::Data, '[ALBUM]');
      my $self = {
         objectname => 'ALBUM',
         TITLE => undef, TRACKCOUNT => undef,
         SETPART => undef, YEAR => undef, GENRE => undef,
         GAPLESS => 0, COMPILATION => 0
      };
      $self = bless $self, $class;
      $MBDB::Album = $self
   }
   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
      if($k eq 'SETPART'){
         return 'ALBUM: SETPART without ALBUMSET'
               unless defined $MBDB::AlbumSet;
         return "ALBUM: SETPART $v not a number" unless $v =~ /^\d+$/;
         return 'ALBUM: SETPART value larger than SETCOUNT'
               if int $v > int $MBDB::AlbumSet->{SETCOUNT}
      }elsif($k eq 'GENRE'){
         my $g = ::genre($v);
         return "ALBUM: $v not a valid GENRE (try --genre-list)"
               unless defined $g;
         $v = $g
      }
      $self->{$k} = $v;
      push @MBDB::Data, "$k = $v";
      undef
   }
   sub finalize{
      my $self = shift;
      ::v("MBDB::$self->{objectname}: finalizing..");
      my $emsg = undef;
      $emsg .= 'ALBUM requires TITLE;' unless defined $self->{TITLE};
      $emsg .= 'ALBUM requires TRACKCOUNT;'
            unless defined $self->{TRACKCOUNT};
      $emsg .= 'ALBUM requires SETPART if ALBUMSET defined;'
            if defined $MBDB::AlbumSet && !defined $self->{SETPART};
      $emsg
   }
} # }}}

{package MBDB::CAST; # {{{
   sub help_text{
      return <<__EOT__
# [CAST]: (ARTIST, SOLOIST, CONDUCTOR, COMPOSER/SONGWRITER, SORT)
#  The CAST includes all the humans responsible for an artwork in detail.
#  Cast information not only applies to the ([ALBUMSET] and) [ALBUM],
#  but also to all following tracks; thus, if any [GROUP] or [TRACK] is to
#  be defined which shall not inherit the [CAST] fields, they need to be
#  defined first!
#  SORT fields are special in that they *always* apply globally; whereas
#  the other fields should be real names ("Wolfgang Amadeus Mozart") these
#  specify how sorting is to be applied ("Mozart, Wolfgang Amadeus"),
#  followed by the normal real name in parenthesis, e.g.:
#     SORT = Hope, Daniel (Daniel Hope)
#  For classical music the orchestra should be the ARTIST.
#  SOLOIST should include the instrument in parenthesis (Midori (violin)).
#  The difference between COMPOSER and SONGWRITER is only noticeable for
#  output file formats which do not support a COMPOSER information frame:
#  whereas the SONGWRITER is simply discarded then, the COMPOSER becomes
#  part of the ALBUM TITLE (Vivaldi: Le quattro stagioni - "La Primavera")
#  if there were any COMPOSER(s) in global [CAST], or part of the TRACK
#  TITLE (The Killing Joke: Pssyche) otherwise ([GROUP]/[TRACK]);
#  the S-Music interface always uses the complete database entry, say.
__EOT__
   }
   sub is_key_supported{
      my $k = shift;
      ($k eq 'ARTIST' ||
         $k eq 'SOLOIST' || $k eq 'CONDUCTOR' ||
         $k eq 'COMPOSER' || $k eq 'SONGWRITER' ||
         $k eq 'SORT')
   }

   sub new{
      my ($class, $emsgr) = @_;
      my $parent = (@_ > 2) ? $_[2] : undef;
      if(!defined $parent && defined $MBDB::Cast){
         $$emsgr = 'CAST yet defined';
         return undef
      }
      ::v("MBDB::CAST::new(" .
         (defined $parent ? "parent=$parent)" : ')'));
      push @MBDB::Data, '[CAST]' unless defined $parent;
      my $self = {
         objectname => 'CAST', parent => $parent,
         ARTIST => [],
         SOLOIST => [], CONDUCTOR => [],
         COMPOSER => [], SONGWRITER => [],
         _parent_composers => 0,
         SORT => []
      };
      $self = bless $self, $class;
      $MBDB::Cast = $self unless defined $parent;
      $self
   }
   sub new_state_clone{
      my $parent = shift;
      my $self = MBDB::CAST->new(undef, $parent);
      if($parent eq 'TRACK' && defined $MBDB::Group){
         $parent = $MBDB::Group->{cast}
      }elsif(defined $MBDB::Cast){
         $parent = $MBDB::Cast
      }else{
         $parent = undef
      }
      if(defined $parent){
         push @{$self->{ARTIST}}, $_ foreach (@{$parent->{ARTIST}});
         push @{$self->{SOLOIST}}, $_ foreach (@{$parent->{SOLOIST}});
         push @{$self->{CONDUCTOR}}, $_ foreach (@{$parent->{CONDUCTOR}});
         push @{$self->{COMPOSER}}, $_ foreach (@{$parent->{COMPOSER}});
         $self->{_parent_composers} = scalar @{$self->{COMPOSER}};
         push @{$self->{SONGWRITER}}, $_ foreach (@{$parent->{SONGWRITER}})
      }
      $self
   }
   sub set_tuple{
      my ($self, $k, $v) = @_;
      $k = uc $k;
      ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
      return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
      push @{$self->{$k}}, $v;
      push @MBDB::Data, "$k = $v";
      undef
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
   # For TRACK to decide where the composer list is to be placed
   sub has_parent_composers{
      $_[0]->{_parent_composers} != 0
   }
} # }}}

{package MBDB::GROUP; # {{{
   sub help_text{
      return <<__EOT__
# [GROUP]: LABEL, (YEAR, GENRE, GAPLESS, COMPILATION, [CAST]-fields)
#  Grouping information applies to all following tracks until the next
#  [GROUP]; TRACKs which do not apply to any GROUP must thus be defined
#  first!
#  GENRE is one of the widely (un)known ID3 genres.
#  GAPLESS states wether there shall be no silence in between tracks,
#  and COMPILATION wether this is a compilation of various-artists or so.
#  CAST-fields may be used to *append* to global [CAST] fields; to specify
#  CAST fields exclusively, place the GROUP before the global [CAST].
__EOT__
   }
   sub is_key_supported{
      my $k = shift;
      ($k eq 'LABEL' || $k eq 'YEAR' || $k eq 'GENRE' ||
         $k eq 'GAPLESS' || $k eq 'COMPILATION' ||
         MBDB::CAST::is_key_supported($k))
   }

   sub new{
      my ($class, $emsgr) = @_;
      ::v("MBDB::GROUP::new()");
      unless(defined $MBDB::Album){
         $$emsgr = 'GROUP requires ALBUM';
         return undef
      }
      push @MBDB::Data, '[GROUP]';
      my $self = {
         objectname => 'GROUP',
         LABEL => undef, YEAR => undef, GENRE => undef,
         GAPLESS => 0, COMPILATION => 0,
         cast => MBDB::CAST::new_state_clone('GROUP')
      };
      $self = bless $self, $class;
      $MBDB::Group = $self
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
         $self->{$k} = $v;
         push @MBDB::Data, "$k = $v"
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
} # }}}

{package MBDB::TRACK; # {{{
   sub help_text{
      return <<__EOT__
# [TRACK]: NUMBER, TITLE, (YEAR, GENRE, COMMENT, [CAST]-fields)
#  GENRE is one of the widely (un)known ID3 genres.
#  CAST-fields may be used to *append* to global [CAST] (and those of the
#  [GROUP], if any) fields; to specify CAST fields exclusively, place the
#  TRACK before the global [CAST].
#  Note: all TRACKs need an ARTIST in the end, from whatever CAST it is
#  inherited.
__EOT__
   }
   sub is_key_supported{
      my $k = shift;
      ($k eq 'NUMBER' || $k eq 'TITLE' ||
         $k eq 'YEAR' || $k eq 'GENRE' || $k eq 'COMMENT' ||
         MBDB::CAST::is_key_supported($k))
   }

   sub new{
      my ($class, $emsgr) = @_;
      unless(defined $MBDB::Album){
         $$emsgr = 'TRACK requires ALBUM';
         return undef
      }
      ::v("MBDB::TRACK::new()");
      push @MBDB::Data, '[TRACK]';
      my $self = {
         objectname => 'TRACK',
         NUMBER => undef, TITLE => undef,
         YEAR => undef, GENRE => undef, COMMENT =>undef,
         group => $MBDB::Group,
         cast => MBDB::CAST::new_state_clone('TRACK')
      };
      bless $self, $class
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
         $emsg = "TRACK: NUMBER $v yet defined"
               if $Title::List[$v - 1]->{TAG_INFO}->{IS_SET}
      }
      if(exists $self->{$k}){
         $self->{$k} = $v;
         push @MBDB::Data, "$k = $v"
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
      my $em = $self->{cast}->finalize();
      $emsg .= $em if defined $em;
      $self->_create_tag_info() unless defined $emsg || $MBDB::Error;
      $emsg
   }

   sub _create_tag_info{ # {{{
      my $self = shift;
      my ($c, $composers, $i, $s, $x);
      my $tir = $Title::List[$self->{NUMBER} - 1]->{TAG_INFO};
      $tir->{IS_SET} = 1;

      # TPE1/TCOM,--artist,--artist - TCOM MAYBE UNDEF
      $c = $self->{cast};
      ($composers, $i, $s, $x) = (undef, -1, '', 0);
      foreach(@{$c->{ARTIST}}){
         $s .= '/' if ++$i > 0;
         $s .= $_
      }
      $x = ($i >= 0);
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
         if ($x) {
            $s .= ', ';
            $x = 0;
         }
         $s .= '/' if ++$i > 0;
         $s .= "$_"
      }
      $tir->{TCOM} = $s if length $s > 0;

      # TALB,--album,--album
      $tir->{TALB} =
      $tir->{ALBUM} = (defined $MBDB::AlbumSet
            ? "$MBDB::AlbumSet->{TITLE} - " : '') . $MBDB::Album->{TITLE};
      $tir->{ALBUM} = "$composers: $tir->{ALBUM}"
            if $c->has_parent_composers();

      # TIT1/TIT2,--title,--title - TIT1 MAYBE UNDEF
      $tir->{TIT1} = (defined $MBDB::Group ? $MBDB::Group->{LABEL} : undef);
      $tir->{TIT2} = $self->{TITLE};
      $tir->{TITLE} = (defined $tir->{TIT1}
            ? "$tir->{TIT1} - $tir->{TIT2}" : $tir->{TIT2});
      $tir->{TITLE} = "$composers: $tir->{TITLE}"
            if !$c->has_parent_composers() && defined $composers;

      # TRCK,--track: TRCK; --tracknum: TRACKNUM
      $tir->{TRCK} =
      $tir->{TRACKNUM} = $self->{NUMBER};
      $tir->{TRCK} .= "/$MBDB::Album->{TRACKCOUNT}";

      # TPOS,--disc - MAYBE UNDEF
      $tir->{TPOS} = (defined $MBDB::AlbumSet
            ? ($MBDB::Album->{SETPART} . '/' .  $MBDB::AlbumSet->{SETCOUNT})
            : undef);

      # TYER,--year,--date: YEAR - MAYBE UNDEF
      $tir->{YEAR} = (defined $self->{YEAR}
            ? $self->{YEAR} : ((defined $MBDB::Group &&
               defined $MBDB::Group->{YEAR})
            ? $MBDB::Group->{YEAR} : (defined $MBDB::Album->{YEAR}
            ? $MBDB::Album->{YEAR} : ((defined $MBDB::AlbumSet &&
               defined $MBDB::AlbumSet->{YEAR})
            ? $MBDB::AlbumSet->{YEAR} : ((defined $CDDB{YEAR} &&
               length($CDDB{YEAR}) > 0)
            ? $CDDB{YEAR} : undef)))));

      # TCON,--genre,--genre
      $tir->{GENRE} = (defined $self->{GENRE}
            ? $self->{GENRE} : ((defined $MBDB::Group &&
               defined $MBDB::Group->{GENRE})
            ? $MBDB::Group->{GENRE} : (defined $MBDB::Album->{GENRE}
            ? $MBDB::Album->{GENRE} : ((defined $MBDB::AlbumSet &&
               defined $MBDB::AlbumSet->{GENRE})
            ? $MBDB::AlbumSet->{GENRE} : (defined $CDDB{GENRE}
            ? $CDDB{GENRE} : ::genre('Humour'))))));
      $tir->{GENREID} = ::genre_id($tir->{GENRE});

      # COMM,--comment,--comment - MAYBE UNDEF
      $tir->{COMM} = $self->{COMMENT}
   } # }}}
} # }}}
} # }}}

{package Enc;
   # vars,funs # {{{
   my (@FormatList,%UserFormats,$VolNorm);

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
         print "\nVolume normalization has been turned off\n";
         return
      }
      print "\nCalculating average volume normalization over all tracks:\n  ";
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
         print "\n  Volume normalization fuzzy/redundant, turned off\n";
         $VolNorm = undef
      }else{
         print "\n  Volume amplitude will be changed by: $VolNorm\n";
         $VolNorm = "-v $VolNorm" # (For sox(1))
      }
   } # }}}

   sub encode_selected{
      print "\nEncoding selected tracks:\n";
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
         push @Coders, &{"Enc::Coder::${_}::new"}($title);
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

{package Enc::Helper;
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
} # Enc::Helper

{package Enc::Coder;
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
            'high', '-q 3.8');
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
}
# }}}
} # Enc::Coder
} # Enc

{package main; main_fun()}

# s-it-mode
