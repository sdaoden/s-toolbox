#!/usr/bin/perl
require 5.008;
#@ S-Disc-Ripper - part of S-MusicBox; this one handles ripping of Audio-CD's.
#@ Requirements:
#@  - CDDB.pm (www.CPAN.org)
#@  - dd(1) (On UNIX; standart UNIX tool)
#@  - sox(1) (sox.sourceforge.net)
#@  - if MP3 is used: lame(1) (www.mp3dev.org)
#@  - if MP4/AAC is used: faac(1) (www.audiocoding.com)
#@  - if Ogg/Vorbis is used: oggenc(1) (www.xiph.org)
#@ TODO: Implement CDDB query ourselfs
my $VERSION = 'v0.5.0';
my $COPYRIGHT =<<_EOT;
Copyright (c) 2010 - 2011 Steffen Daode Nurpmeso <sdaoden@gmail.com>.
All rights reserved.
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

# May be changed for different site-global default settings
my ($MP3HI,$MP3LO, $AACHI,$AACLO, $OGGHI,$OGGLO) = (0,0, 1,1, 1,0);
# Dito: change the undef to '/Desired/Path'
my $MUSICDB = defined $ENV{S_MUSICDB} ? $ENV{S_MUSICDB} : undef;
my $CDROM = defined $ENV{CDROM} ? $ENV{CDROM} : undef;
my $CDROMDEV = (defined $ENV{CDROMDEV} ? $ENV{CDROMDEV} #: undef;
               : defined $CDROM ? $CDROM : undef);
my $TMPDIR = (defined $ENV{TMPDIR} && -d $ENV{TMPDIR}) ? $ENV{TMPDIR} : undef;

use diagnostics -verbose;
use warnings;
use strict;

use CDDB;
use Encode;
use Getopt::Long;

my @Genres = (
    [ 123, 'A Cappella' ],  [ 34, 'Acid' ],         [ 74, 'Acid Jazz' ],
    [ 73, 'Acid Punk' ],    [ 99, 'Acoustic' ],     [ 20, 'Alternative' ],
    [ 40, 'Alt. Rock' ],    [ 26, 'Ambient' ],      [ 145, 'Anime' ],
    [ 90, 'Avantgarde' ],   [ 116, 'Ballad' ],      [ 41, 'Bass' ],
    [ 135, 'Beat' ],        [ 85, 'Bebob' ],        [ 96, 'Big Band' ],
    [ 138, 'Black Metal' ], [ 89, 'Bluegrass' ],    [ 0, 'Blues' ],
    [ 107, 'Booty Bass' ],  [ 132, 'BritPop' ],     [ 65, 'Cabaret' ],
    [ 88, 'Celtic' ],       [ 104, 'Chamber Music' ], [ 102, 'Chanson' ],
    [ 97, 'Chorus' ],       [ 136, 'Christian Gangsta Rap' ],
    [ 61, 'Christian Rap' ], [ 141, 'Christian Rock' ],
    [ 32, 'Classical' ],    [ 1, 'Classic Rock' ],  [ 112, 'Club' ],
    [ 128, 'Club-House' ],  [ 57, 'Comedy' ],
    [ 140, 'Contemporary Christian' ],
    [ 2, 'Country' ],       [ 139, 'Crossover' ],   [ 58, 'Cult' ],
    [ 3, 'Dance' ],         [ 125, 'Dance Hall' ],  [ 50, 'Darkwave' ],
    [ 22, 'Death Metal' ],  [ 4, 'Disco' ],         [ 55, 'Dream' ],
    [ 127, 'Drum & Bass' ], [ 122, 'Drum Solo' ],   [ 120, 'Duet' ],
    [ 98, 'Easy Listening' ], [ 52, 'Electronic' ], [ 48, 'Ethnic' ],
    [ 54, 'Eurodance' ],    [ 124, 'Euro-House' ],  [ 25, 'Euro-Techno' ],
    [ 84, 'Fast-Fusion' ],  [ 80, 'Folk' ],         [ 115, 'Folklore' ],
    [ 81, 'Folk/Rock' ],    [ 119, 'Freestyle' ],   [ 5, 'Funk' ],
    [ 30, 'Fusion' ],       [ 36, 'Game' ],         [ 59, 'Gangsta Rap' ],
    [ 126, 'Goa' ],         [ 38, 'Gospel' ],       [ 49, 'Gothic' ],
    [ 91, 'Gothic Rock' ],  [ 6, 'Grunge' ],        [ 129, 'Hardcore' ],
    [ 79, 'Hard Rock' ],    [ 137, 'Heavy Metal' ], [ 7, 'Hip-Hop' ],
    [ 35, 'House' ],        [ 100, 'Humour' ],      [ 131, 'Indie' ],
    [ 19, 'Industrial' ],   [ 33, 'Instrumental' ],
    [ 46, 'Instrumental Pop' ], [ 47, 'Instrumental Rock' ],
    [ 8, 'Jazz' ],          [ 29, 'Jazz+Funk' ],    [ 146, 'JPop' ],
    [ 63, 'Jungle' ],       [ 86, 'Latin' ],        [ 71, 'Lo-Fi' ],
    [ 45, 'Meditative' ],   [ 142, 'Merengue' ],    [ 9, 'Metal' ],
    [ 77, 'Musical' ],      [ 82, 'National Folk' ],
    [ 64, 'Native American' ],
    [ 133, 'Negerpunk' ],   [ 10, 'New Age' ],      [ 66, 'New Wave' ],
    [ 39, 'Noise' ],        [ 11, 'Oldies' ],       [ 103, 'Opera' ],
    [ 12, 'Other' ],        [ 75, 'Polka' ],        [ 134, 'Polsk Punk' ],
    [ 13, 'Pop' ],          [ 53, 'Pop-Folk' ],     [ 62, 'Pop/Funk' ],
    [ 109, 'Porn Groove' ], [ 117, 'Power Ballad' ], [ 23, 'Pranks' ],
    [ 108, 'Primus' ],      [ 92, 'Progressive Rock' ],
    [ 67, 'Psychedelic' ],  [ 93, 'Psychedelic Rock' ],
    [ 43, 'Punk' ],         [ 121, 'Punk Rock' ],   [ 15, 'Rap' ],
    [ 68, 'Rave' ],         [ 14, 'R&B' ],          [ 16, 'Reggae' ],
    [ 76, 'Retro' ],        [ 87, 'Revival' ],
    [ 118, 'Rhythmic Soul' ], [ 17, 'Rock' ],       [ 78, 'Rock & Roll' ],
    [ 143, 'Salsa' ],       [ 114, 'Samba' ],       [ 110, 'Satire' ],
    [ 69, 'Showtunes' ],    [ 21, 'Ska' ],          [ 111, 'Slow Jam' ],
    [ 95, 'Slow Rock' ],    [ 105, 'Sonata' ],      [ 42, 'Soul' ],
    [ 37, 'Sound Clip' ],   [ 24, 'Soundtrack' ],
    [ 56, 'Southern Rock' ], [ 44, 'Space' ],       [ 101, 'Speech' ],
    [ 83, 'Swing' ],        [ 94, 'Symphonic Rock' ], [ 106, 'Symphony' ],
    [ 147, 'Synthpop' ],    [ 113, 'Tango' ],       [ 18, 'Techno' ],
    [ 51, 'Techno-Industrial' ], [ 130, 'Terror' ],
    [ 144, 'Thrash Metal' ], [ 60, 'Top 40' ],      [ 70, 'Trailer' ],
    [ 31, 'Trance' ],       [ 72, 'Tribal' ],       [ 27, 'Trip-Hop' ],
    [ 28, 'Vocal' ]
);

my ($RIP_ONLY, $ENC_ONLY, $NO_VOL_NORM, $VERBOSE) = (0, 0, 0, 0);
my $INTRO =<<_EOT;
s-disc-ripper.pl ($VERSION)
$COPYRIGHT
_EOT
my ($CLEANUP_OK, $WORK_DIR, $TARGET_DIR, %CDDB) = (0);

jMAIN: {
    # Also verifies we have valid (DB,TMP..) paths
    command_line();

    $SIG{INT} = sub { print STDERR "\nInterrupted ... bye\n"; exit 1; };
    print $INTRO, "Press <CNTRL-C> at any time to interrupt\n";

    my ($info_ok, $needs_cddb) = (0, 1);
    # Unless we've seen --encode-only=ID
    unless (defined $CDInfo::Id) {
        CDInfo::discover();
        $info_ok = 1;
    }

    $WORK_DIR = "$TMPDIR/s-disc-ripper.$CDInfo::Id";
    $TARGET_DIR = "$MUSICDB/disc.${CDInfo::Id}-";
    if (-d "${TARGET_DIR}1") {
        $TARGET_DIR = quick_and_dirty_dir_selector();
    } else {
        $TARGET_DIR .= '1';
    }
    print <<_EOT;

TARGET directory: $TARGET_DIR
WORKing directory: $WORK_DIR
(In worst-case error situations it may be necessary to remove those manually.)
_EOT
    die 'Non-existent session cannot be resumed via --encode-only'
        if ($ENC_ONLY && !-d $WORK_DIR);
    mkdir($WORK_DIR) or die "Can't create <$WORK_DIR>: $! -- $^E"
        unless -d $WORK_DIR;
    mkdir($TARGET_DIR) or die "Can't create <$TARGET_DIR>: $! -- $^E"
        unless -d $TARGET_DIR;

    CDInfo::init_paths();
    MBDB::init_paths();

    # Get the info right, and maybe the database
    if (-f $MBDB::FinalFile) {
        die 'Database corrupted - remove TARGET and re-rip entire disc'
            # Creates $Title::List etc. as approbiate
            unless MBDB::read_data();
        ($info_ok, $needs_cddb) = (1, 0);
    } else {
        if ($info_ok) {
            CDInfo::write_data();
        } else {
            # (Can only be --encode-only.. dies as approbiate...)
            CDInfo::read_data();
            $info_ok = 1;
        }
        Title::create_that_many($CDInfo::TrackCount);
    }

    if ($needs_cddb && !$RIP_ONLY) {
        cddb_query();
        MBDB::create_data();
    }

    # Handling files
    if ($RIP_ONLY || !$ENC_ONLY) {
        user_tracks();
        Title::rip_all_selected();
        print "\nUse --encode-only=$CDInfo::Id to resume ...\n" if $RIP_ONLY;
    } elsif ($ENC_ONLY) {
        my @rawfl = glob("$WORK_DIR/*.raw");
        die '--encode-only session on empty file list' if @rawfl == 0;
        foreach (sort @rawfl) {
            die '--encode-only session: illegal filenames exist'
                unless /(\d+).raw$/;
            my $i = int $1;
            die "\
--encode-only session: track <$_> is unknown!
It does not seem to belong to this disc, you need to re-rip it."
                unless ($i > 0 && $i <= $CDInfo::TrackCount);
            my $t = $Title::List[$i - 1];
            $t->{IS_SELECTED} = 1;
        }
        #print "\nThe following raw tracks will now be encoded:\n\t";
        #print "$_->{NUMBER} " foreach (@Title::List);
        #print "\n\tIs this really ok?  You may interrupt now! ";
        #exit(5) unless user_confirm();
    }

    unless ($RIP_ONLY) {
        Enc::calculate_volume_normalize($NO_VOL_NORM);
        Enc::encode_selected();
        $CLEANUP_OK = 1;
    }

    exit 0;
}

END { finalize() if $CLEANUP_OK; }

sub command_line {
    my $emsg = undef;
    Getopt::Long::Configure('bundling');
    unless (GetOptions( 'h|help|?'  => sub { goto jdocu; },
                'g|genre-list'      => sub {
                    foreach my $tr (@Genres) {
                        printf("%3d %s\n", $tr->[0], $tr->[1]);
                    }
                    exit 0;
                },
                'musicdb=s'         => \$MUSICDB,
                'tmpdir=s'          => \$TMPDIR,
                'cdrom=s'           => \$CDROM,
                'cdromdev=s'        => \$CDROMDEV,
                'r|rip-only'        => \$RIP_ONLY,
                'e|encode-only=s'   => \$ENC_ONLY,
                'no-volume-normalize'           => \$NO_VOL_NORM,
                'mp3=i' => \$MP3HI, 'mp3lo=i'   => \$MP3LO,
                'aac=i' => \$AACHI, 'aaclo=i'   => \$AACLO,
                'ogg=i' => \$OGGHI, 'ogglo=i'   => \$OGGLO,
                'v|verbose'         => \$VERBOSE)) {
        $emsg = 'Invocation failure';
        goto jdocu;
    }

    unless (defined $MUSICDB && -d $MUSICDB && -w _) {
        $emsg = "S-MusicBox DB directory unaccessible";
        goto jdocu;
    }
    unless (defined $TMPDIR && -d $TMPDIR && -w _) {
        $emsg = "The given TMPDIR is somehow not accessible";
        goto jdocu;
    }
    if ($ENC_ONLY) {
        if ($RIP_ONLY) {
            $emsg = '--rip-only and --encode-only are mutual exclusive';
            goto jdocu;
        }
        if ($ENC_ONLY !~ /[[:alnum:]]+/) {
            $emsg = "$ENC_ONLY is not a valid CD(DB)ID";
            goto jdocu;
        }
        $CDInfo::Id = lc $ENC_ONLY;
        $ENC_ONLY = 1;
    }
    return;

jdocu:  print STDERR "!\t$emsg\n\n" if defined $emsg;
    print STDERR <<_EOT;
${INTRO}S-Disc-Ripper is the disc ripper of the S-MusicBox set of tools.
It will rip discs, query CDDB servers and finally encode the raw data to MP3,
and/or (MP4/)AAC and/or (Ogg )Vorbis (as desired).
Setting the EDITOR environment gives more comfort (currently <$ENV{EDITOR}>).

USAGE:
s-disc-ripper.pl -h|--help
s-disc-ripper.pl -g|--genre-list
s-disc-ripper.pl [-v|--verbose] [--musicdb=PATH] [--tmpdir=PATH]
                 [--cdrom=SPEC] [--cdromdev=DEVSPEC]
                 [-r|--rip-only] [-e|--encode-only=CD(DB)ID]
                 [--mp3] [--mp3lo] [--aac] [--aaclo] [--ogg] [--ogglo]

 -h,--help        prints this help text and exits
 -g,--genre-list  dumps out a list of all GENREs and exits
 -v,--verbose     mostly debug, prints a lot of status messages and does
                  neither delete temporary files nor directory!
 --musicdb=PATH   specifies the path to the S-MusicBox database directory.
                  Default setting is the S_MUSICDB environment variable.
                  Currently <$MUSICDB>
 --tmpdir=PATH    the (top) temporary directory to use - defaults to the TMPDIR
                  environment variable.
                  Currently <$TMPDIR>
 --cdrom=SPEC,--cdromdev=DEVSPEC
                  set CDROM drive/device to be used.  SPEC is system-dependend
                  and may be something like </dev/cdrom> or </dev/acd1c>.
                  Mac OS X: SPEC and DEVSPEC are simple drivenumbers, e.g. <1>!
                  There (only) it may also be necessary to specify --cdromdev:
                  --cdrom= is used for the drutil(1) '-drive' option,
                  whereis --cdromdev is used for raw </dev/diskDEVSPEC> access
                  (dependend on USB usage order these numbers may even vary..).
                  The default settings are the CDROM/CDROMDEV environ variables
 -r,--rip-only    exit after the data rip is completed (and see --encode-only)
 -e CDID,--encode-only=CDID
                  resume a --rip-only session.  CDID is the CDDB ID of the
                  CDROM, and has been printed out by --rip-only before ...
 --no-volume-normalize
                  By default the average volume adjustment is calculated over
                  all (selected) files and then used to normalize files.
                  If single files are ripped that may be counterproductive.
 --mp3=BOOL,--mp3lo=.., --aac=..,--aaclo=.., --ogg=..,--ogglo=..
                  by default one adjusts the script header once for the
                  requirements of a specific site, but these command line
                  options can also be used to define which output files shall
                  be produced: MP3, MP4/AAC and OGG in high/low quality.
                  Current settings: $MP3HI,$MP3LO, $AACHI,$AACLO, $OGGHI,$OGGLO
_EOT
    exit defined $emsg ? 1 : 0;
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
        $g = lc $g;
        foreach my $tr (@Genres) {
            return $tr->[1] if lc($tr->[1]) eq $g;
        }
    }
    return undef;
}

sub genre_id {
    my $g = shift;
    foreach my $tr (@Genres) {
        return $tr->[0] if $tr->[1] eq $g;
    }
    # (Used only for valid genre-names)
}

# (Called by END{} only if $CLEANUP_OK)
sub finalize {
    if ($VERBOSE) {
        v("--verbose mode: NOT removing <$WORK_DIR>");
        return;
    }

    print "\nRemoving temporary <$WORK_DIR>\n";
    unlink($CDInfo::DatFile, $MBDB::EditFile);
    foreach (@Title::List) {
        next unless -f $_->{RAW_FILE};
        die "Can't unlink $_->{RAW_FILE}: $! -- $^E"
            unless unlink($_->{RAW_FILE});
    }
    rmdir($WORK_DIR) or die "rmdir <$WORK_DIR> failed: $! -- $^E";
}

sub user_confirm {
    print ' [Nn (or else)] ';
    my $u = <STDIN>;
    return ($u =~ /n/i) ? 0 : 1;
}

sub quick_and_dirty_dir_selector {
    my @dlist = glob("${TARGET_DIR}*/musicbox.dat");
    return "${TARGET_DIR}1" if @dlist == 0;
    print <<_EOT;

CD(DB)ID clash detected!
Either (1) the disc is not unique
or (2) you are trying to extend/replace some files of a yet existent disc.
(Note that the temporary WORKing directory will clash no matter what you do!)
Here is a list of yet existent albums which match that CDID:
_EOT
    my ($i, $usr);
    for ($i = 1; $i <= @dlist; ++$i) {
        my $d = "${TARGET_DIR}$i";
        my $f = "$d/musicbox.dat";
        unless (open(F, "<$f")) {
            print "\t[] Failed to open <$f>!\n\t\tSkipping!!!\n";
            next;
        }
        my ($ast, $at, $tr) = (undef, undef, undef);
        while (<F>) {
            if (/^\s*\[ALBUMSET\]/) { $tr = \$ast; }
            elsif (/^\s*\[ALBUM\]/) { $tr = \$at; }
            elsif (/^\s*\[CDDB\]/)  { next; }
            elsif (/^\s*\[\w+\]/)   { last; }
            elsif (defined $tr && /^\s*TITLE\s*=\s*(.+?)\s*$/) {
                $$tr = $1;
            }
        }
        close(F) or die "Can't close <$f>: $! -- $^E";
        unless (defined $at) {
            print "\t[] No TITLE entry in <$f>!\n\t\t",
                "Disc is corrupted and must be re-ripped!\n";
            next;
        }
        $at = "$ast - $at" if defined $ast;
        print "\t[$i] $at\n";
    }
    print "\t[0] None of these - the disc should create a new entry!\n";

jREDO:  print "\tChoose the number to use: ";
    $usr = <STDIN>;
    chomp $usr;
    unless ($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @dlist) {
        print "!\tI'm expecting one of the [numbers] ... !\n";
        goto jREDO;
    }
    if ($usr == 0) {
        print "\t.. forced to create a new disc entry\n";
        return "${TARGET_DIR}$i";
    } else {
        print "\t.. forced to resume an existent album\n";
        return "${TARGET_DIR}$usr";
    }
}

sub cddb_query {
    print "\nShall the CDDB be contacted online ",
          '(otherwise the entries are faked) ';
    unless (user_confirm()) {
        print "\tcreating entry fakes ...\n";
        goto jFAKE;
    }

    print "Starting CDDB query for $CDInfo::Id\n";
    my $cddb = new CDDB or die "Can't create CDDB object: $! -- $^E";
    my @discs = $cddb->get_discs($CDInfo::Id, \@CDInfo::TrackOffsets,
                                 $CDInfo::TotalSeconds);

    if (@discs == 0) {
        print "CDDB didn't match, i will create entry fakes!\n",
              'Maybe there is no network connection? Shall i continue? ';
        exit(10) unless user_confirm();

jFAKE:  %CDDB = ();
        $CDDB{GENRE} = genre('Humour');
        $CDDB{ARTIST} = 'Unknown';
        Encode::_utf8_off($CDDB{ARTIST});
        $CDDB{ALBUM} = 'Unknown';
        Encode::_utf8_off($CDDB{ALBUM});
        $CDDB{YEAR} = '';
        my @titles;
        $CDDB{TITLES} = \@titles;
        for (my $i = 1; $i <= $CDInfo::TrackCount; ++$i) {
            my $s = 'TITLE ' . $i;
            Encode::_utf8_off($s);
            push(@titles, $s);
        }
        return;
    }

    my ($usr, $dinf);
jAREDO:
    $usr = 1;
    foreach (@discs) {
        my ($genre, undef, $title) = @$_; # (cddb_id)
        print "\t[$usr] Genre:$genre, Title:$title\n";
        ++$usr;
    }
    print "\t[0] None of those (creates a local entry fakes)\n";

jREDO:
    print "\tChoose the number to use: ";
    $usr = <STDIN>;
    chomp $usr;
    unless ($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @discs) {
        print "!\tI'm expecting one of the [numbers] ... !\n";
        goto jREDO;
    }
    if ($usr == 0) {
        print "\tcreating entry fakes ...\n";
        goto jFAKE;
    }
    $usr = $discs[--$usr];

    print "\nStarting CDDB detail read for $usr->[0]/$CDInfo::Id\n";
    $dinf = $cddb->get_disc_details($usr->[0], $CDInfo::Id);
    die 'CDDB failed to return disc details' unless defined $dinf;

    # Prepare TAG as UTF-8 (CDDB entries may be ISO-8859-1 or UTF-8)
    %CDDB = ();
    $CDDB{GENRE} = genre($usr->[0]);
    unless (defined $CDDB{GENRE}) {
        $CDDB{GENRE} = genre('Humour');
        print "!\tCDDB entry has illegal GENRE - using $CDDB{GENRE}\n";
    }
    {   my $aa = $usr->[2];
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
        $CDDB{ARTIST} = $art;
        $alb =~ s/^\s*(.*?)\s*$/$1/;
            $i = $alb;
            eval { Encode::from_to($alb, 'iso-8859-1', 'utf-8'); };
            $alb = $i if $@;
            Encode::_utf8_off($alb);
        $CDDB{ALBUM} = $alb;
    }
    $CDDB{YEAR} = defined $dinf->{dyear} ? $dinf->{dyear} : '';
    $CDDB{TITLES} = $dinf->{ttitles};
    foreach (@{$dinf->{ttitles}}) {
        s/^\s*(.*?)\s*$/$1/;
        my $save = $_;
        eval { Encode::from_to($_, 'iso-8859-1', 'utf-8'); };
        $_ = $save if $@;
        Encode::_utf8_off($_);
    }

    print "CDDB disc info for CD(DB)ID=$CDInfo::Id\n",
          "(NOTE: terminal may not be able to display charset):\n",
          "\t\tGenre=$CDDB{GENRE}, Year=$CDDB{YEAR}\n",
          "\t\tArtist=$CDDB{ARTIST}\n",
          "\t\tAlbum=$CDDB{ALBUM}\n",
          "\t\tTitles in order:\n",
          join("\n\t\t\t", @{$CDDB{TITLES}}),
          "\n\tIs this *really* the desired CD? ";
    goto jAREDO unless user_confirm();
}

sub user_tracks {
    print "Disc $CDInfo::Id contains $CDInfo::TrackCount songs - ",
          'shall all be ripped?  ';
    if (user_confirm()) {
        print "\tWhee - all songs will be ripped\n";
        $_->{IS_SELECTED} = 1 foreach (@Title::List);
        return;
    }

    my ($line, @dt);
jREDO:
    print "Please enter a space separated list of the desired track numbers\n";
    $line = <STDIN>;
    chomp $line;
    @dt = split(/\s+/, $line);
    print "\tIs this list correct <", join(' ', @dt), '> ';
    goto jREDO unless user_confirm();
    foreach (@dt) {
        if ($_ == 0 || $_ > $CDInfo::TrackCount) {
            print "!\tInvalid track number: $_!\n\n";
            goto jREDO;
        }
    }

    $Title::List[$_ - 1]->{IS_SELECTED} = 1 foreach (@dt);
}

{package CDInfo;
    my ($DevId);
    BEGIN { # Id field may also be set from command_line()
        # Mostly set by _calc_id() or parse() only (except Ripper)
        $CDInfo::Id =
        $CDInfo::TotalSeconds =
        $CDInfo::TrackCount = undef;
        $CDInfo::FileRipper = undef; # Ref to actual ripper sub
        @CDInfo::TrackOffsets = ();
    }

    sub init_paths {
        $CDInfo::DatFile = "$WORK_DIR/cdinfo.dat";
    }

    sub discover {
        no strict 'refs';
        die "Operating system <$^O> not supported"
            unless defined *{"CDInfo::_os_$^O"};
        print "\nCDInfo: assuming an Audio-CD is in the drive ...\n",
              "\t(Otherwise insert it, wait a second and restart)\n";
        &{"CDInfo::_os_$^O"}();
        print "\tCalculated CDInfo: disc: $CDInfo::Id\n\t\t",
              'Track offsets: ' . join(' ', @CDInfo::TrackOffsets),
              "\n\t\tTotal seconds: $CDInfo::TotalSeconds\n",
              "\t\tTrack count: $CDInfo::TrackCount\n";
    }

    sub _os_openbsd { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "\tOpenBSD: using drive $drive \n";
        die "OpenBSD support in fact missing";
    }

    sub _os_freebsd { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "\tFreeBSD: using drive $drive \n";
        die "FreeBSD support in fact missing";
    }

    sub _os_darwin {
        my $drive = defined $CDROM ? $CDROM : 1;
        $DevId = defined $CDROMDEV ? $CDROMDEV : $drive;
        print "\tDarwin/Mac OS X: using drive $drive and /dev/disk$DevId\n";

        $CDInfo::FileRipper = sub {
            my $title = shift;
            my $sf = '/dev/disk' . $DevId . 's' . $title->{NUMBER};
            return "Device node does not exist: $sf" unless -e $sf;
            system "dd bs=2352 if=$sf of=$title->{RAW_FILE}";
            return undef if ($? >> 8) == 0;
            return "$! -- $^E";
        };

        # Problem: this non-UNIX thing succeeds even without media...
        ::v("Invoking drutil(1) -drive $drive toc");
        my $l = `drutil -drive $drive toc`;
        my @res = split("\n", $l);
        die "Drive $drive: failed reading TOC: $! -- $^E" if $?;

        my (@cdtoc, $leadout);
        for(;;) {
            $l = shift(@res);
            die "Drive $drive: no lead-out information found" unless defined $l;
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

    sub _os_linux { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "\tLinux: using drive $drive \n";
        die "Linux support in fact missing";
    }

    # Calculated CD(DB)-Id and *set*CDInfo*fields* (except $FileRipper)!
    sub _calc_cdid {
        # This is a stripped down version of CDDB.pm::calculate_id()
        my $cdtocr = shift;
        my ($sec_first, $sum);
        foreach (@$cdtocr) {
            my ($no, $min, $sec, $fra) = split(/\s+/, $_, 4);
            my $frame_off = (($min * 60 + $sec) * 75) + $fra;
            my $sec_begin = int($frame_off / 75);
            $sec_first = $sec_begin unless defined $sec_first;
            # Track 999 was chosen for the lead-out information
            if ($no == 999) {
                $CDInfo::TotalSeconds = $sec_begin;
                last;
            }
            map { $sum += $_; } split(//, $sec_begin);
            push(@CDInfo::TrackOffsets, $frame_off);
        }
        $CDInfo::TrackCount = scalar @CDInfo::TrackOffsets;
        $CDInfo::Id = sprintf("%02x%04x%02x",
                              ($sum % 255),
                              ($CDInfo::TotalSeconds - $sec_first),
                              scalar(@CDInfo::TrackOffsets));
    }

    sub write_data {
        my $f = $CDInfo::DatFile;
        ::v("CDInfo::write_data($f)");
        open(DAT, ">$f") or die "Can't open <$f>: $! -- $^E";
        print DAT "# S-Disc-Ripper CDDB info for project $CDInfo::Id\n",
                  "# Don't modify! or project needs to be re-ripped!!\n",
                  "CDID = $CDInfo::Id\n",
                  'TRACK_OFFSETS = ', join(' ', @CDInfo::TrackOffsets), "\n",
                  "TOTAL_SECONDS = $CDInfo::TotalSeconds\n";
        close(DAT) or die "Can't close <$f>: $! -- $^E";
    }

    sub read_data {
        my $f = $CDInfo::DatFile;
        ::v("CDInfo::read_data($f)");
        open(DAT, "<$f") or die "\
Can't open <$f>: $! -- $^E.
This project cannot be continued!
Remove <$WORK_DIR> and re-rip the disc!";
        my @lines = <DAT>;
        close(DAT) or die "Can't close <$f>: $! -- $^E";
        parse_data(\@lines);
    }

    sub parse_data {
        # It may happen that this is called even though discover()
        # already queried the disc in the drive - nevertheless: resume!
        my $old_id = $CDInfo::Id;
        my $laref = shift;
        ::v("CDInfo::parse_data()");
        $CDInfo::Id = $CDInfo::TotalSeconds = $CDInfo::TrackCount = undef;
        @CDInfo::TrackOffsets = ();

        my $emsg = undef;
        foreach (@$laref) {
            chomp;
            next if /^\s*#/;
            $emsg .= "Invalid line <$_>;" and next
                unless /^\s*(.+?)\s*=\s*(.+?)\s*$/;
            my ($k, $v) = ($1, $2);
            if ($k eq 'CDID') {
                $emsg .= "Parsed CDID ($v) doesn't match;" and next
                    if (defined $old_id && $v ne $old_id);
                $CDInfo::Id = $v;
            } elsif ($k eq 'TRACK_OFFSETS') {
                $emsg .= 'TRACK_OFFSETS yet seen;' and next
                    if @CDInfo::TrackOffsets > 0;
                @CDInfo::TrackOffsets = split(/\s+/, $v);
            } elsif ($k eq 'TOTAL_SECONDS') {
                $emsg .= "illegal TOTAL_SECONDS: $v;" unless $v =~ /^(\d+)$/;
                $CDInfo::TotalSeconds = $1;
            } else {
                $emsg .= "Illegal line: <$_>;";
            }
        }
        $emsg .= 'corrupted: no CDID seen;' unless defined $CDInfo::Id;
        $emsg .= 'corrupted: no TOTAL_SECONDS seen;'
            unless defined $CDInfo::TotalSeconds;
        $CDInfo::TrackCount = scalar @CDInfo::TrackOffsets;
        $emsg .= 'corrupted: no TRACK_OFFSETS seen;'
            unless $CDInfo::TrackCount > 0;
        if (@Title::List > 0) {
            $emsg .= 'corrupted: TRACK_OFFSETS illegal;'
                if $CDInfo::TrackCount != @Title::List;
        }
        die "CDInfo: $emsg" if defined $emsg;

        print "\n\tResumed (parsed) CDInfo: disc: $CDInfo::Id\n\t\t",
              'Track offsets: ' . join(' ', @CDInfo::TrackOffsets),
              "\n\t\tTotal seconds: $CDInfo::TotalSeconds\n",
              "\t\tTrack count: $CDInfo::TrackCount\n";
        Title::create_that_many($CDInfo::TrackCount);
    }
}

# Title represents - a track
{package Title;
    my (@List);
    sub create_that_many {
        return if @List != 0;
        my $no = shift;
        for (my $i = 1; $i <= $no; ++$i) {
            Title->new($i);
        }
    }

    sub rip_all_selected {
        print "\nRipping selected tracks:\n";
        foreach my $t (@Title::List) {
            next unless $t->{IS_SELECTED};
            if (-f $t->{RAW_FILE}) {
                print "\tRaw ripped track $t->{NUMBER} exists - re-rip? ";
                next unless ::user_confirm();
            }

            print "\tRip track $t->{NUMBER} -> $t->{RAW_FILE}\n";
            my $emsg = &$CDInfo::FileRipper($t);
            if (defined $emsg) {
                print   "!\tError occurred: $emsg\n",
                        "!\tTrack will be deselected - or quit? ";
                exit(5) if ::user_confirm();
                $t->{IS_SELECTED} = 0;
                unlink($t->{RAW_FILE}) if -f $t->{RAW_FILE};
            }
        }
    }

    sub new {
        my ($class, $no) = @_;
        ::v("Title::new(number=$no)");
        my $nos = sprintf('%03d', $no);
        my $self = {
            NUMBER => $no,
            INDEX => $no - 1,
            NUMBER_STRING => $nos,
            RAW_FILE => "$WORK_DIR/$nos.raw",
            TARGET_PLAIN => "$TARGET_DIR/$nos",
            IS_SELECTED => 0,
            TAG_INFO => Title::TagInfo->new()
        };
        $self = bless($self, $class);
        $Title::List[$no - 1] = $self;
        return $self;
    }

# ID3v2.3 a.k.a. supported oggenc(1)/faac(1) tag stuff is bundled in here;
# fields are set to something useful by MBDB:: below
{package Title::TagInfo;
    sub new {
        my ($class) = @_;
        ::v("Title::TagInfo::new()");
        my $self = {};
        $self = bless($self, $class);
        return $self->reset();
    }

    sub reset {
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
        return $self;
    }
}
}

# MBDB - MusicBox (per-disc) database handling.
# This is small minded and a dead end street for all the data - but that's
# really sufficient here,
# because if the database has been falsely edited the user must correct it!
# At least a super-object based approach should have been used though.
# All strings come in as UTF-8 and remain unmodified
{package MBDB;
    our ($CDDB, $AlbumSet, $Album, $Cast, $Group,   # [GROUP] objects
        $Error, @Data                               # I/O & content
    );

    sub init_paths {
        $MBDB::EditFile = "$WORK_DIR/template.dat";
        $MBDB::FinalFile = "$TARGET_DIR/musicbox.dat";
    }

    sub _reset_data {
        $AlbumSet = $Album = $Cast = $Group = undef;
        $_->{TAG_INFO}->reset() foreach (@Title::List);
        $Error = 0; @Data = ();
    }

    sub read_data { return _read_data($MBDB::FinalFile); }

    sub create_data {
        my $ed = defined $ENV{EDITOR} ? $ENV{EDITOR} : '/usr/bin/vi';
        print "\nCreating S-MusicBox per-disc database\n";

        my @old_data;
jREDO:  @old_data = @MBDB::Data;
        _reset_data();
        _write_editable(\@old_data);
        print "\tTemplate: $MBDB::EditFile\n",
              "\tPlease do verify and edit this file as necessary\n",
              "\tShall i invoke EDITOR <$ed>? ";
        if (::user_confirm()) {
            my @args = ($ed, $MBDB::EditFile);
            system(@args);
        } else {
            print "\tOk, waiting: hit <RETURN> to continue ...";
            $ed = <STDIN>;
        }
        if (!_read_data($MBDB::EditFile)) {
            print "!\tErrors detected - edit once again!\n";
            goto jREDO;
        }

        print "\n\tOnce again - please verify the content:\n";
        print "\t\t$_\n" foreach (@MBDB::Data);
        print "\tIs this data *really* OK? ";
        goto jREDO unless ::user_confirm();

        _write_final();
    }

    sub _write_editable {
        my $df = $MBDB::EditFile;
        my $dataref = shift;
        ::v("Writing editable MusicBox data file as <$df>");
        open(DF, ">$df") or die "Can't open <$df>: $! -- $^E";
        if (@$dataref > 0) {
            print DF "\n# CONTENT OF LAST USER EDIT AT END OF FILE!\n\n"
                or die "Error writing <$df>: $! -- $^E";
        }

        my $cddbt = $CDDB{TITLES};
        my $sort = $CDDB{ARTIST};
        if ($sort =~ /^The/i && $sort !~ /^the the$/i) { # The The, The
            $sort =~ /^the\s+(.+)$/i;
            $sort = "SORT = $1, The (The $1)";
        } elsif ($sort =~ /^([-\w]+)\s+(.+)$/) {
            $sort = "SORT = $2, $1 ($1 $2)";
        } else {
            $sort = "#SORT = $sort ($sort)";
        }

        print DF _help_text(), "\n",
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
                "$sort\n\n",
                MBDB::GROUP::help_text(),
                "#[GROUP]\n#LABEL = \n#GAPLESS = 0\n",
                "\n",
                MBDB::TRACK::help_text()
            or die "Error writing <$df>: $! -- $^E";

        foreach my $title (@Title::List) {
            my $n = $title->{NUMBER};
            my $i = $title->{INDEX};
            print DF "[TRACK]\nNUMBER = $n\nTITLE = $cddbt->[$i]\n\n"
                or die "Error writing <$df>: $! -- $^E";
        }

        if (@$dataref > 0) {
            print DF "\n# CONTENT OF FORMER USER EDIT:\n"
                or die "Error writing <$df>: $! -- $^E";
            print DF "#$_\n" or die "Error writing <$df>: $! -- $^E"
                foreach (@$dataref);
        }
        print DF "# vim:set fenc=utf-8 filetype=txt syntax=cfg:\n",
            or die "Error writing <$df>: $! -- $^E";
        close(DF) or die "Can't close <$df>: $! -- $^E";
    }

    sub _help_text {
        return <<_EOT;
# S-MusicBox database, CDDB info: $CDDB{GENRE}/$CDInfo::Id
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

    sub _write_final {
        my $df = $MBDB::FinalFile;
        ::v("Creating final MusicBox data file as <$df>");
        open(DF, ">$df") or die "Can't open <$df>: $! -- $^E";
        print DF "[CDDB]\nCDID = $CDInfo::Id\n",
                 "TRACK_OFFSETS = ", join(' ', @CDInfo::TrackOffsets),
                 "\nTOTAL_SECONDS = $CDInfo::TotalSeconds\n",
            or die "Error writing <$df>: $! -- $^E";
        print DF $_, "\n" or die "Error writing <$df>: $! -- $^E"
            foreach (@MBDB::Data);
        close(DF) or die "Can't close <$df>: $! -- $^E";
    }

    sub _read_data {
        my $df = shift;
        my $is_final = ($df eq $MBDB::FinalFile);
        _reset_data();

        open(DF, "<$df") or die "Can't open <$df>: $! -- $^E";
        my ($emsg, $entry) = (undef, undef);
        while (<DF>) {
            s/^\s*(.*?)\s*$/$1/;
            next if length() == 0 || /^#/;
            my $line = $_;

            if ($line =~ /^\[(.*?)\]$/) {
                my $c = $1;
                if (defined $entry) {
                    $emsg = $entry->finalize();
                    $entry = undef;
                    if (defined $emsg) {
                        $MBDB::Error = 1;
                        print "!\tERROR: $emsg\n";
                        $emsg = undef;
                    }
                } elsif ($is_final && $c ne 'CDDB') {
                    $emsg = 'Database corrupted - it does not start with a ' .
                            '(internal) [CDDB] group';
                    goto jERROR;
                }

                no strict 'refs';
                my $class = "MBDB::${c}";
                my $sym = "${class}::new";
                unless (defined %{"${class}::"}) {
                    $emsg = "Illegal command: [$c]";
                    goto jERROR;
                }
                $entry = &$sym($class, \$emsg);
            } elsif ($line =~ /^(.*?)\s*=\s*(.*)$/) {
                my ($k, $v) = ($1, $2);
                unless (defined $entry) {
                    $emsg = "KEY=VALUE line without group: <$k=$v>";
                    goto jERROR;
                }
                $emsg = $entry->set_tuple($k, $v);
            } else {
                $emsg = "Line illegal: <$_>";
            }

            if (defined $emsg) {
jERROR:         $MBDB::Error = 1;
                print "!\tERROR: $emsg\n";
                die "Disc database is corrupted!\n" .
                    "Remove <$TARGET_DIR> (!) and re-rip disc!"
                    if $is_final;
                $emsg = undef;
            }
        }
        if (defined $entry && defined($emsg = $entry->finalize())) {
            $MBDB::Error = 1;
            print "!\tERROR: $emsg\n";
        }
        close(DF) or die "Can't close <$df>: $! -- $^E";

        for (my $i = 1; $i <= $CDInfo::TrackCount; ++$i) {
            next if $Title::List[$i - 1]->{TAG_INFO}->{IS_SET};
            $MBDB::Error = 1;
            print "!\tERROR: no entry for track number $i found\n";
        }
        return ($MBDB::Error == 0);
    }

{package MBDB::CDDB;
    sub is_key_supported {
        my $k = shift;
        return $k eq 'CDID' || $k eq 'TRACK_OFFSETS' || $k eq 'TOTAL_SECONDS';
    }

    sub new {
        my ($class, $emsgr) = @_;
        if (defined $MBDB::CDDB) {
            $$emsgr = 'There may only be one (internal!) [CDDB] section';
            return undef;
        }
        ::v("MBDB::CDDB::new()");
        push(@MBDB::Data, '[CDDB]');
        my @dat;
        my $self = { objectname => 'CDDB',
            CDID => undef, TRACK_OFFSETS => undef,
            TOTAL_SECONDS => undef, _data => \@dat
        };
        $self = bless($self, $class);
        $MBDB::CDDB = $self;
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        return "$self->{objectname}: $k already set" if defined $self->{$k};
        $self->{$k} = $v;
        push(@{$self->{_data}}, "$k = $v");
        push(@MBDB::Data, "$k = $v");
        return undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        return 'CDDB requires CDID, TRACK_OFFSETS and TOTAL_SECONDS;'
            unless (defined $self->{CDID} && defined $self->{TRACK_OFFSETS} &&
                    defined $self->{TOTAL_SECONDS});
        CDInfo::parse_data($self->{_data});
        return undef;
    }
}

{package MBDB::ALBUMSET;
    sub help_text {
        return <<_EOT;
# [ALBUMSET]: TITLE, SETCOUNT
#   If a multi-CD-Set is ripped each CD gets its own database file, say;
#   ALBUMSET and the SETPART field of ALBUM are how to group 'em
#   nevertheless: repeat the same ALBUMSET and adjust the SETPART field.
#   (No GENRE etc.: all that is in ALBUM only ... as you can see)
_EOT
    }
    sub is_key_supported {
        my $k = shift;
        return $k eq 'TITLE' || $k eq 'SETCOUNT';
    }

    sub new {
        my ($class, $emsgr) = @_;
        if (defined $MBDB::AlbumSet) {
            $$emsgr = 'ALBUMSET yet defined';
            return undef;
        }
        ::v("MBDB::ALBUMSET::new()");
        push(@MBDB::Data, '[ALBUMSET]');
        my $self = { objectname => 'ALBUMSET',
            TITLE => undef, SETCOUNT => undef
        };
        $self = bless($self, $class);
        $MBDB::AlbumSet = $self;
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        $self->{$k} = $v;
        push(@MBDB::Data, "$k = $v");
        return undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'ALBUMSET requires TITLE and SETCOUNT;'
            unless (defined $self->{TITLE} && defined $self->{SETCOUNT});
        return $emsg;
    }
}

{package MBDB::ALBUM;
    sub help_text {
        return <<_EOT;
# [ALBUM]: TITLE, TRACKCOUNT, (SETPART, YEAR, GENRE, GAPLESS, COMPILATION)
#   If the album is part of an ALBUMSET TITLE may only be 'CD 1' - it is
#   required nevertheless even though it could be deduced automatically
#   from the ALBUMSET's TITLE and the ALBUM's SETPART - sorry!
#   I.e. SETPART is required, then, and the two TITLEs are *concatenated*.
#   GENRE is one of the widely (un)known ID3 genres.
#   GAPLESS states wether there shall be no silence in between tracks,
#   and COMPILATION wether this is a compilation of various-artists or so.
_EOT
    }
    sub is_key_supported {
        my $k = shift;
        return ($k eq 'TITLE' ||
                $k eq 'TRACKCOUNT' ||
                $k eq 'SETPART' || $k eq 'YEAR' || $k eq 'GENRE' ||
                $k eq 'GAPLESS' || $k eq 'COMPILATION');
    }

    sub new {
        my ($class, $emsgr) = @_;
        if (defined $MBDB::Album) {
            $$emsgr = 'ALBUM yet defined';
            return undef;
        }
        ::v("MBDB::ALBUM::new()");
        push(@MBDB::Data, '[ALBUM]');
        my $self = { objectname => 'ALBUM',
            TITLE => undef, TRACKCOUNT => undef,
            SETPART => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0
        };
        $self = bless($self, $class);
        $MBDB::Album = $self;
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        if ($k eq 'SETPART') {
            return 'ALBUM: SETPART without ALBUMSET'
                unless defined $MBDB::AlbumSet;
            return "ALBUM: SETPART $v not a number" unless $v =~ /^\d+$/;
            return 'ALBUM: SETPART value larger than SETCOUNT'
                if int($v) > int($MBDB::AlbumSet->{SETCOUNT});
        } elsif ($k eq 'GENRE') {
            my $g = ::genre($v);
            return "ALBUM: $v not a valid GENRE (try --genre-list)"
                unless defined $g;
            $v = $g;
        }
        $self->{$k} = $v;
        push(@MBDB::Data, "$k = $v");
        return undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'ALBUM requires TITLE;' unless defined $self->{TITLE};
        $emsg .= 'ALBUM requires TRACKCOUNT;'
            unless defined $self->{TRACKCOUNT};
        if (defined $MBDB::AlbumSet && !defined $self->{SETPART}) {
            $emsg .= 'ALBUM requires SETPART if ALBUMSET defined;';
        }
        return $emsg;
    }
}

{package MBDB::CAST;
    sub help_text {
        return <<_EOT;
# [CAST]: (ARTIST, SOLOIST, CONDUCTOR, COMPOSER/SONGWRITER, SORT)
#   The CAST includes all the humans responsible for an artwork in detail.
#   Cast information not only applies to the ([ALBUMSET] and) [ALBUM],
#   but also to all following tracks; thus, if any [GROUP] or [TRACK] is to
#   be defined which shall not inherit the [CAST] fields, they need to be
#   defined first!
#   SORT fields are special in that they *always* apply globally; whereas
#   the other fields should be real names ("Wolfgang Amadeus Mozart") these
#   specify how sorting is to be applied ("Mozart, Wolfgang Amadeus"),
#   followed by the normal real name in parenthesis, e.g.:
#       SORT = Hope, Daniel (Daniel Hope)
#   For classical music the orchestra should be the ARTIST.
#   SOLOIST should include the instrument in parenthesis (Midori (violin)).
#   The difference between COMPOSER and SONGWRITER is only noticeable for
#   output file formats which do not support a COMPOSER information frame:
#   whereas the SONGWRITER is simply discarded then, the COMPOSER becomes
#   part of the ALBUM TITLE (Vivaldi: Le quattro stagioni - "La Primavera")
#   if there were any COMPOSER(s) in global [CAST], or part of the TRACK
#   TITLE (The Killing Joke: Pssyche) otherwise ([GROUP]/[TRACK]);
#   the S-MusicBox interface always uses the complete database entry, say.
_EOT
    }
    sub is_key_supported {
        my $k = shift;
        return ($k eq 'ARTIST' ||
                $k eq 'SOLOIST' || $k eq 'CONDUCTOR' ||
                $k eq 'COMPOSER' || $k eq 'SONGWRITER' ||
                $k eq 'SORT');
    }

    sub new {
        my ($class, $emsgr) = @_;
        my $parent = (@_ > 2) ? $_[2] : undef;
        if (!defined $parent && defined $MBDB::Cast) {
            $$emsgr = 'CAST yet defined';
            return undef;
        }
        ::v("MBDB::CAST::new(" .
            (defined $parent ? "parent=$parent)" : ')'));
        push(@MBDB::Data, '[CAST]') unless defined $parent;
        my $self = { objectname => 'CAST', parent => $parent,
                ARTIST => [],
                SOLOIST => [], CONDUCTOR => [],
                COMPOSER => [], SONGWRITER => [],
                _parent_composers => 0,
                SORT => []
            };
        $self = bless($self, $class);
        $MBDB::Cast = $self unless defined $parent;
        return $self;
    }
    sub new_state_clone {
        my $parent = shift;
        my $self = MBDB::CAST->new(undef, $parent);
        if ($parent eq 'TRACK' && defined $MBDB::Group) {
            $parent = $MBDB::Group->{cast};
        } elsif (defined $MBDB::Cast) {
            $parent = $MBDB::Cast;
        } else {
            $parent = undef;
        }
        if (defined $parent) {
            push(@{$self->{ARTIST}}, $_) foreach (@{$parent->{ARTIST}});
            push(@{$self->{SOLOIST}}, $_) foreach (@{$parent->{SOLOIST}});
            push(@{$self->{CONDUCTOR}}, $_) foreach (@{$parent->{CONDUCTOR}});
            push(@{$self->{COMPOSER}}, $_) foreach (@{$parent->{COMPOSER}});
            $self->{_parent_composers} = scalar @{$self->{COMPOSER}};
            push(@{$self->{SONGWRITER}}, $_) foreach (@{$parent->{SONGWRITER}});
        }
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        push(@{$self->{$k}}, $v);
        push(@MBDB::Data, "$k = $v");
        return undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        if (defined $self->{parent} && $self->{parent} eq 'TRACK' &&
                @{$self->{ARTIST}} == 0) {
            $emsg .= 'TRACK requires at least one ARTIST;';
        }
        return $emsg;
    }
    # For TRACK to decide where the composer list is to be placed
    sub has_parent_composers {
        my $self = shift;
        return ($self->{_parent_composers} != 0);
    }
}

{package MBDB::GROUP;
    sub help_text {
        return <<_EOT;
# [GROUP]: LABEL, (YEAR, GENRE, GAPLESS, COMPILATION, [CAST]-fields)
#   Grouping information applies to all following tracks until the next
#   [GROUP]; TRACKs which do not apply to any GROUP must thus be defined
#   first!
#   GENRE is one of the widely (un)known ID3 genres.
#   GAPLESS states wether there shall be no silence in between tracks,
#   and COMPILATION wether this is a compilation of various-artists or so.
#   CAST-fields may be used to *append* to global [CAST] fields; to specify
#   CAST fields exclusively, place the GROUP before the global [CAST].
_EOT
    }
    sub is_key_supported {
        my $k = shift;
        return ($k eq 'LABEL' || $k eq 'YEAR' || $k eq 'GENRE' ||
                $k eq 'GAPLESS' || $k eq 'COMPILATION' ||
                MBDB::CAST::is_key_supported($k));
    }

    sub new {
        my ($class, $emsgr) = @_;
        ::v("MBDB::GROUP::new()");
        unless (defined $MBDB::Album) {
            $$emsgr = 'GROUP requires ALBUM';
            return undef;
        }
        push(@MBDB::Data, '[GROUP]');
        my $self = { objectname => 'GROUP',
            LABEL => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0,
            cast => MBDB::CAST::new_state_clone('GROUP')
        };
        $self = bless($self, $class);
        $MBDB::Group = $self;
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        if ($k eq 'GENRE') {
            $v = ::genre($v);
            return "GROUP: $v not a valid GENRE (try --genre-list)"
                unless defined $v;
        }
        if (exists $self->{$k}) {
            $self->{$k} = $v;
            push(@MBDB::Data, "$k = $v");
        } else {
            $self->{cast}->set_tuple($k, $v);
        }
        return undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'GROUP requires LABEL;' unless defined $self->{LABEL};
        my $em = $self->{cast}->finalize();
        $emsg .= $em if defined $em;
        return $emsg;
    }
}

{package MBDB::TRACK;
    sub help_text {
        return <<_EOT;
# [TRACK]: NUMBER, TITLE, (YEAR, GENRE, COMMENT, [CAST]-fields)
#   GENRE is one of the widely (un)known ID3 genres.
#   CAST-fields may be used to *append* to global [CAST] (and those of the
#   [GROUP], if any) fields; to specify CAST fields exclusively, place the
#   TRACK before the global [CAST].
#   Note: all TRACKs need an ARTIST in the end, from whatever CAST it is
#   inherited.
_EOT
    }
    sub is_key_supported {
        my $k = shift;
        return ($k eq 'NUMBER' || $k eq 'TITLE' ||
                $k eq 'YEAR' || $k eq 'GENRE' || $k eq 'COMMENT' ||
                MBDB::CAST::is_key_supported($k));
    }

    sub new {
        my ($class, $emsgr) = @_;
        unless (defined $MBDB::Album) {
            $$emsgr = 'TRACK requires ALBUM';
            return undef;
        }
        ::v("MBDB::TRACK::new()");
        push(@MBDB::Data, '[TRACK]');
        my $self = { objectname => 'TRACK',
            NUMBER => undef, TITLE => undef,
            YEAR => undef, GENRE => undef, COMMENT =>undef,
            group => $MBDB::Group,
            cast => MBDB::CAST::new_state_clone('TRACK')
        };
        $self = bless($self, $class);
        return $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        if ($k eq 'GENRE') {
            $v = ::genre($v);
            return "TRACK: $v not a valid GENRE (try --genre-list)"
                unless defined $v;
        }
        my $emsg = undef;
        if ($k eq 'NUMBER') {
            return "TRACK: NUMBER $v does not exist"
                if (int($v) <= 0 || int($v) > $CDInfo::TrackCount);
            $emsg = "TRACK: NUMBER $v yet defined"
                if $Title::List[$v - 1]->{TAG_INFO}->{IS_SET};
        }
        if (exists $self->{$k}) {
            $self->{$k} = $v;
            push(@MBDB::Data, "$k = $v");
        } else {
            $self->{cast}->set_tuple($k, $v);
        }
        return $emsg;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        unless (defined $self->{NUMBER} && defined $self->{TITLE}) {
            $emsg .= 'TRACK requires NUMBER and TITLE;';
        }
        my $em = $self->{cast}->finalize();
        $emsg .= $em if defined $em;
        $self->_create_tag_info() unless (defined $emsg || $MBDB::Error);
        return $emsg;
    }

    sub _create_tag_info {
        my $self = shift;
        my ($c, $composers, $i, $s, $x);
        my $tir = $Title::List[$self->{NUMBER} - 1]->{TAG_INFO};
        $tir->{IS_SET} = 1;

        # TPE1/TCOM,--artist,--artist - TCOM MAYBE UNDEF
        $c = $self->{cast};
        ($composers, $i, $s, $x) = (undef, -1, '', 0);
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
        $tir->{TPE1} =
        $tir->{ARTIST} = $s;

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
        $tir->{TCOM} = $s if length($s) > 0;

        # TALB,--album,--album
        $tir->{TALB} =
        $tir->{ALBUM} = (defined $MBDB::AlbumSet
                         ? "$MBDB::AlbumSet->{TITLE} - " : ''
                        ) . $MBDB::Album->{TITLE};
        $tir->{ALBUM} = "$composers: $tir->{ALBUM}"
            if $c->has_parent_composers();

        # TIT1/TIT2,--title,--title - TIT1 MAYBE UNDEF
        $tir->{TIT1} = (defined $MBDB::Group ? $MBDB::Group->{LABEL} : undef);
        $tir->{TIT2} = $self->{TITLE};
        $tir->{TITLE} = (defined $tir->{TIT1}
                        ? "$tir->{TIT1} - $tir->{TIT2}" : $tir->{TIT2});
        $tir->{TITLE} = "$composers: $tir->{TITLE}"
            if (!$c->has_parent_composers() && defined $composers);

        # TRCK,--track: TRCK; --tracknum: TRACKNUM
        $tir->{TRCK} =
        $tir->{TRACKNUM} = $self->{NUMBER};
        $tir->{TRCK} .= "/$MBDB::Album->{TRACKCOUNT}";

        # TPOS,--disc - MAYBE UNDEF
        $tir->{TPOS} = (defined $MBDB::AlbumSet
                        ? ($MBDB::Album->{SETPART} . '/' .
                           $MBDB::AlbumSet->{SETCOUNT})
                        : undef);

        # TYER,--year,--date: YEAR - MAYBE UNDEF
        $tir->{YEAR} = (defined $self->{YEAR} ? $self->{YEAR}
                        : ((defined $MBDB::Group &&
                            defined $MBDB::Group->{YEAR})
                           ? $MBDB::Group->{YEAR}
                           : (defined $MBDB::Album->{YEAR}
                              ? $MBDB::Album->{YEAR}
                              : ((defined $MBDB::AlbumSet &&
                                  defined $MBDB::AlbumSet->{YEAR})
                                 ? $MBDB::AlbumSet->{YEAR}
                                 : ((defined $CDDB{YEAR} &&
                                     length($CDDB{YEAR}) > 0)
                                    ? $CDDB{YEAR}
                                    : undef)))));

        # TCON,--genre,--genre
        $tir->{GENRE} = (defined $self->{GENRE} ? $self->{GENRE}
                        : ((defined $MBDB::Group &&
                            defined $MBDB::Group->{GENRE})
                           ? $MBDB::Group->{GENRE}
                           : (defined $MBDB::Album->{GENRE}
                              ? $MBDB::Album->{GENRE}
                              : ((defined $MBDB::AlbumSet &&
                                  defined $MBDB::AlbumSet->{GENRE})
                                 ? $MBDB::AlbumSet->{GENRE}
                                 : (defined $CDDB{GENRE}
                                    ? $CDDB{GENRE}
                                    : ::genre('Humour'))))));
        $tir->{GENREID} = ::genre_id($tir->{GENRE});

        # COMM,--comment,--comment - MAYBE UNDEF
        $tir->{COMM} = $self->{COMMENT};
    }
}
}

{package Enc;
    my ($VolNorm, $AACTag, $OGGTag);

    sub calculate_volume_normalize {
        my $nope = shift;
        if ($nope) {
            print "\nVolume normalization has been turned off\n";
            $VolNorm = '';
            return;
        }
        print "\nCalculating average volume normalization over all tracks:\n\t";
        $VolNorm = undef;
        foreach my $t (@Title::List) {
            next unless $t->{IS_SELECTED};
            my $f = $t->{RAW_FILE};
            open(SOX, "sox -t raw -r44100 -c2 -w -s $f -e stat -v 2>&1 |")
                or die "Can't open SOX stat for <$f>: $! -- $^E";
            my $avg = <SOX>;
            close(SOX) or die "Can't close SOX stat for <$f>: $! -- $^E";
            chomp $avg;

            if ($t->{INDEX} != 0 && $t->{INDEX} % 7 == 0) {
                print "\n\t$t->{NUMBER}: $avg, ";
            } else {
                print "$t->{NUMBER}: $avg, ";
            }
            $VolNorm = $avg unless defined $VolNorm;
            $VolNorm = $avg if $avg < $VolNorm;
        }
        print "\n\tVolume amplitude will be changed by: $VolNorm\n";
        $VolNorm = "-v $VolNorm"; # Argument for sox(1)
    }

    sub encode_selected {
        print "\nEncoding selected tracks:\n";
        foreach my $t (@Title::List) {
            unless ($t->{IS_SELECTED}) {
                ::v("\tSkipping $t->{NUMBER}: not selected");
                next;
            }
            print "\tTrack $t->{NUMBER} -> $t->{TARGET_PLAIN}.*\n";
            _mp3tag_file($t) if ($MP3HI || $MP3LO);
            _faac_comment($t) if ($AACHI || $AACLO);
            _oggenc_comment($t) if ($OGGHI || $OGGLO);
            _encode_file($t);
        }
    }

    sub _mp3tag_file {
        # Stuff in (parens) refers ID3 tag version 2.3.0, www.id3.org.
        my $title = shift;
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
        $tag .= _mp3_frame('TYER', $ti->{YEAR}, 'NUM') if defined $ti->{YEAR};
        $ti = $ti->{COMM};
        if (defined $ti) {
            $ti = "engS-MUSICBOX:COMM\x00$ti";
            $tag .= _mp3_frame('COMM', $ti, 'UNI');
        }

        # (5.) Apply unsynchronization to all frames
        my $has_unsynced = int($tag =~ s/\xFF/\xFF\x00/gs);

        # (3.1.) Prepare the header
        # ID3v2, version 2
        my $header = 'ID3' . "\x03\00";
        # Flags 1 byte: bit 7 (first bit MSB) =$has_unsynced
        $header .= pack('C', ($has_unsynced > 0) ? 0x80 : 0x00);
        # Tag size: 4 bytes as 4*7 bits
        {   my $l = length($tag);
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
            my $f = $title->{TARGET_PLAIN};
            if ($i == 0) {
                $f .= '.mp3';
                next if $MP3HI == 0;
            } else {
                $f .= '.lo.mp3';
                next if $MP3LO == 0;
            }
            open(F, ">$f") or die "Can't open <$f>: $! -- $^E";
            binmode(F) or die "binmode <$f> failed: $! -- $^E";
            print F $header, $tag or die "Error writing <$f>: $! -- $^E";
            close(F) or die "Can't close <$f>: $! -- $^E";
        }
    }

    sub _mp3_frame {
        my ($fid, $ftxt) = @_;
        ::v("\tMP3 frame: $fid: <$ftxt>") unless $fid eq 'COMM';
        my ($len, $txtenc);
        # Numerical strings etc. always latin-1
        if (@_ > 2) {
            my $add = $_[2];
            if ($add eq 'NUM') {
                $len = length($ftxt);
                $txtenc = "\x00";
            } else { #if ($add eq 'UNI') \{
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
        unless ($force_uni) { eval {
            $isuni = Encode::from_to($i, 'utf-8', 'iso-8859-1', 1);
        }; }
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
        my $title = shift;
        my $ti = $title->{TAG_INFO};
        my $i;
        $AACTag = '';
        $i = $ti->{ARTIST};
            $i =~ s/"/\\"/g;
            $AACTag .= "--artist \"$i\" ";
        $i = $ti->{ALBUM};
            $i =~ s/"/\\"/g;
            $AACTag .= "--album \"$i\" ";
        $i = $ti->{TITLE};
            $i =~ s/"/\\"/g;
            $AACTag .= "--title \"$i\" ";
        $AACTag .= "--track \"$ti->{TRCK}\" "
            . (defined $ti->{TPOS} ? "--disc \"$ti->{TPOS}\" " :'')
            . "--genre '$ti->{GENRE}' "
            . (defined $ti->{YEAR} ? "--year \"$ti->{YEAR}\"" :'');
        $i = $ti->{COMM};
        if (defined $i) {
            $i =~ s/"/\\"/g;
            $AACTag .=" --comment \"S-MUSICBOX:COMM=$i\"";
        }
        Encode::_utf8_off($AACTag);
        ::v("AACTag: $AACTag");
    }

    sub _oggenc_comment {
        my $title = shift;
        my $ti = $title->{TAG_INFO};
        my $i;
        $OGGTag = '';
        $i = $ti->{ARTIST};
            $i =~ s/"/\\"/g;
            $OGGTag .= "--artist \"$i\" ";
        $i = $ti->{ALBUM};
            $i =~ s/"/\\"/g;
            $OGGTag .= "--album \"$i\" ";
        $i = $ti->{TITLE};
            $i =~ s/"/\\"/g;
            $OGGTag .= "--title \"$i\" ";
        $OGGTag .= "--tracknum \"$ti->{TRACKNUM}\" "
            . (defined $ti->{TPOS}
                ? "--comment=\"TPOS=$ti->{TPOS}\" " : '')
            . "--comment=\"TRCK=$ti->{TRCK}\" "
            . "--genre \"$ti->{GENRE}\" "
            . (defined $ti->{YEAR} ? "--date \"$ti->{YEAR}\"" :'');
        $i = $ti->{COMM};
        if (defined $i) {
            $i =~ s/"/\\"/g;
            $OGGTag .=" --comment \"S-MUSICBOX:COMM=$i\"";
        }
        Encode::_utf8_off($OGGTag);
        ::v("OGGTag: $OGGTag");
    }

    sub _encode_file {
        my $title = shift;
        my $tpath = $title->{TARGET_PLAIN};

        open(SOX, "sox $VolNorm -t raw -r44100 -c2 -w -s " .
                   $title->{RAW_FILE} . ' -t raw - |')
            or die "Can't open SOX pipe: $! -- $^E";
        binmode(SOX) or die "binmode SOX failed: $! -- $^E";

        if ($MP3HI) {
            ::v('Creating MP3 lame(1) high-quality encoder');
            open(MP3HI, '| lame --quiet -r -x -s 44.1 --bitwidth 16 ' .
                        "--vbr-new -V 0 -q 0 - - >> $tpath.mp3")
                or die "Can't open LAME-high: $! -- $^E";
            binmode(MP3HI) or die "binmode LAME-high failed: $! -- $^E";
        }
        if ($MP3LO) {
            ::v('Creating MP3 lame(1) low-quality encoder');
            open(MP3LO, '| lame --quiet -r -x -s 44.1 --bitwidth 16 ' .
                        "--vbr-new -V 7 -q 0 - - >> $tpath.lo.mp3")
                or die "Can't open LAME-low: $! -- $^E";
            binmode(MP3LO) or die "binmode LAME-low failed: $! -- $^E";
        }
        if ($AACHI) {
            ::v('Creating AAC faac(1) high-quality encoder');
            open(AACHI, '| faac -XP --mpeg-vers 4 -ws --tns -q 300 ' .
                        "$AACTag -o $tpath.mp4 - >/dev/null 2>&1")
                or die "Can't open FAAC-high: $! -- $^E";
            binmode(AACHI) or die "binmode FAAC-high failed: $! -- $^E";
        }
        if ($AACLO) {
            ::v('Creating AAC faac(1) low-quality encoder');
            open(AACLO, '| faac -XP --mpeg-vers 4 -ws --tns -q 80 ' .
                        "$AACTag -o $tpath.lo.mp4 - >/dev/null 2>&1")
                or die "Can't open FAAC-low: $! -- $^E";
            binmode(AACLO) or die "binmode FAAC-low failed: $! -- $^E";
        }
        if ($OGGHI) {
            ::v('Creating Vorbis oggenc(1) high-quality encoder');
            open(OGGHI, "| oggenc -Q -r -q 8.5 $OGGTag -o $tpath.ogg -")
                or die "Can't open OGGENC-high: $! -- $^E";
            binmode(OGGHI) or die "binmode OGGENC-high failed: $! -- $^E";
        }
        if ($OGGLO) {
            ::v('Creating Vorbis oggenc(1) low-quality encoder');
            open(OGGLO, "| oggenc -Q -r -q 3.8 $OGGTag -o $tpath.lo.ogg -")
                or die "Can't open OGGENC-low: $! -- $^E";
            binmode(OGGLO) or die "binmode OGGENC-low failed: $! -- $^E";
        }

        for (my $data;;) {
            my $bytes = read(SOX, $data, 1024*1000);
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

        close(SOX) or die "Can't close SOX pipe: $! -- $^E";
        close(MP3HI) or die "Can't close LAME-high pipe: $! -- $^E" if $MP3HI;
        close(MP3LO) or die "Can't close LAME-low: $! -- $^E" if $MP3LO;
        close(AACHI) or die "Can't close FAAC-high: $! -- $^E" if $AACHI;
        close(AACLO) or die "Can't close FAAC-low: $! -- $^E" if $AACLO;
        close(OGGHI) or die "Can't close OGGENC-high: $! -- $^E" if $OGGHI;
        close(OGGLO) or die "Can't close OGGENC-low: $! -- $^E" if $OGGLO;
    }
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
