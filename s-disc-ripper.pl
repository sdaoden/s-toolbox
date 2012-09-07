#!/usr/bin/perl
require 5.008_001;
my $SELF = 's-disc-ripper.pl'; #@ part of S-MusicBox; handles CD ripping.
#@ Requirements:
#@  - unless --no-volume-normalize is used: sox(1) (sox.sourceforge.net)
#@  - if MP3 is used: lame(1) (www.mp3dev.org)
#@  - if MP4/AAC is used: faac(1) (www.audiocoding.com)
#@  - if Ogg/Vorbis is used: oggenc(1) (www.xiph.org)
#@  - OPTIONAL: CDDB.pm (www.CPAN.org)
my $VERSION = '0.5.0rc0';
my $COPYRIGHT =<<__EOT__;
Copyright (c) 1998 - 2003,
Copyright (c) 2010 - 2012 Steffen "Daode" Nurpmeso <sdaoden\@users.sf.net>.
All rights reserved under the terms of the ISC license.
__EOT__
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

# May be changed for different site-global default settings
my ($MP3HI,$MP3LO, $AACHI,$AACLO, $OGGHI,$OGGLO) = (0,0, 1,1, 1,0);
# Dito: change the undef to '/Desired/Path'
my $MUSICDB = defined $ENV{S_MUSICDB} ? $ENV{S_MUSICDB} : undef;
my $CDROM = defined $ENV{CDROM} ? $ENV{CDROM} : undef;
my $CDROMDEV = (defined $ENV{CDROMDEV} ? $ENV{CDROMDEV} #: undef;
               : defined $CDROM ? $CDROM : undef);
my $TMPDIR = (defined $ENV{TMPDIR} && -d $ENV{TMPDIR}) ? $ENV{TMPDIR} : undef;

##  --  >8  --  8<  --  ##

use diagnostics -verbose;
use warnings;
use strict;

use Encode;
use Getopt::Long;

# Genre list, alpha sorted {{{
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
); # }}}

my $INTRO =<<__EOT__;
$SELF (v$VERSION)
$COPYRIGHT
__EOT__

my ($RIP_ONLY, $ENC_ONLY, $NO_VOL_NORM, $VERBOSE) = (0, 0, 0, 0);
my ($CLEANUP_OK, $WORK_DIR, $TARGET_DIR, %CDDB) = (0);

jMAIN: { # {{{
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
    print <<__EOT__;

TARGET directory : $TARGET_DIR
WORKing directory: $WORK_DIR
(In worst-case error situations it may be necessary to remove those manually.)
__EOT__
    die 'Non-existent session cannot be resumed via --encode-only'
        if $ENC_ONLY && ! -d $WORK_DIR;
    unless (-d $WORK_DIR) {
        die "Can't create $WORK_DIR: $!" unless mkdir $WORK_DIR;
    }
    unless ($RIP_ONLY || -d $TARGET_DIR) {
        die "Can't create $TARGET_DIR: $!" unless mkdir $TARGET_DIR;
    }

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

    if (! $RIP_ONLY && $needs_cddb) {
        cddb_query();
        MBDB::create_data();
    }

    # Handling files
    if ($RIP_ONLY || ! $ENC_ONLY) {
        user_tracks();
        Title::rip_all_selected();
        print "\nUse --encode-only=$CDInfo::Id to resume ...\n" if $RIP_ONLY;
    } elsif ($ENC_ONLY) {
        my @rawfl = glob "$WORK_DIR/*.raw";
        die '--encode-only session on empty file list' if @rawfl == 0;
        foreach (sort @rawfl) {
            die '--encode-only session: illegal filenames exist'
                unless /(\d+).raw$/;
            my $i = int $1;
            die "\
--encode-only session: track $_ is unknown!
It does not seem to belong to this disc, you need to re-rip it."
                unless $i > 0 && $i <= $CDInfo::TrackCount;
            my $t = $Title::List[$i - 1];
            $t->{IS_SELECTED} = 1;
        }
        #print "\nThe following raw tracks will now be encoded:\n  ";
        #print "$_->{NUMBER} " foreach (@Title::List);
        #print "\n  Is this really ok?  You may interrupt now! ";
        #exit(5) unless user_confirm();
    }

    unless ($RIP_ONLY) {
        Enc::calculate_volume_normalize($NO_VOL_NORM);
        Enc::encode_selected();
        $CLEANUP_OK = 1;
    }

    exit 0;
} # }}}

END { finalize() if $CLEANUP_OK; }

sub command_line { # {{{
    my $emsg = undef;
    Getopt::Long::Configure('bundling');
    unless (GetOptions( 'h|help|?'  => sub { goto jdocu; },
                'g|genre-list'      => sub {
                    printf("%3d %s\n", $_->[0], $_->[1]) foreach (@Genres);
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

    unless ($RIP_ONLY) {
        $MUSICDB = glob $MUSICDB if defined $MUSICDB;
        unless (defined $MUSICDB && -d $MUSICDB && -w _) {
            $emsg = "S-MusicBox DB directory not accessible";
            goto jdocu;
        }
    }

    $TMPDIR = glob $TMPDIR if defined $TMPDIR;
    unless (defined $TMPDIR && -d $TMPDIR && -w _) {
        $emsg = "The given TMPDIR is somehow not accessible";
        goto jdocu;
    }

    return;

jdocu:
    print STDERR <<__EOT__;
${INTRO}${SELF} is the disc ripper of the S-MusicBox set of tools.
It will rip discs, query CDDB servers and finally encode the raw data
to MP3 and/or (MP4/)AAC and/or (Ogg )Vorbis (as desired).
Setting the EDITOR environment gives more comfort ("$ENV{EDITOR}").

Synopsis:
 $SELF -h|--help
 $SELF -g|--genre-list
 $SELF [-v|--verbose] [--musicdb=PATH] [--tmpdir=PATH]
                  [--cdrom=SPEC] [--cdromdev=DEVSPEC]
                  [-r|--rip-only] [-e|--encode-only=CD(DB)ID]
                  [--mp3] [--mp3lo] [--aac] [--aaclo] [--ogg] [--ogglo]

 -h,--help        prints this help text and exits
 -g,--genre-list  dumps out a list of all GENREs and exits
 -v,--verbose     mostly debug, prints a lot of status messages and does
                  neither delete temporary files nor directory!
 --musicdb=PATH   specifies the path to the S-MusicBox database directory.
                  Default setting is the S_MUSICDB environment variable.
                  Currently "$MUSICDB"
 --tmpdir=PATH    the (top) temporary directory to use - defaults to the TMPDIR
                  environment variable.
                  Currently "$TMPDIR"
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
__EOT__
    print STDERR "\n! $emsg\n" if defined $emsg;
    exit defined $emsg ? 1 : 0;
} # }}}

# v, genre, genre_id, finalize, user_confirm, utf8ify {{{
sub v {
    return unless $VERBOSE > 0;
    print STDOUT '-V  ', shift, "\n";
    while (@_ != 0) { print STDOUT '-V  ++  ', shift, "\n" };
    1;
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
    undef;
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
        v("--verbose mode: NOT removing $WORK_DIR");
        return;
    }
    print "\nRemoving temporary $WORK_DIR\n";
    unlink $CDInfo::DatFile, $MBDB::EditFile; # XXX
    foreach (@Title::List) {
        next unless -f $_->{RAW_FILE};
        die "Can't unlink $_->{RAW_FILE}: $!" unless unlink $_->{RAW_FILE};
    }
    die "rmdir $WORK_DIR failed: $!" unless rmdir $WORK_DIR;
}

sub user_confirm {
    my $save = $|;
    $| = 1;
    print ' [Nn (or else)] ';
    my $u = <STDIN>;
    $| = $save;
    chomp $u;
    ($u =~ /n/i) ? 0 : 1;
}

sub utf8ify {
    # String comes from CDDB, may be latin1 or utf-8
    my $sr = shift;
    my ($s, $sc) = ($$sr);
    eval { $s = Encode::decode_utf8($s, 1); };
    eval { $s = Encode::encode_utf8($s); } if $@;
    $$sr = $s;
}
# }}}

sub quick_and_dirty_dir_selector { # {{{
    my @dlist = glob "${TARGET_DIR}*/musicbox.dat";
    return "${TARGET_DIR}1" if @dlist == 0;
    print <<__EOT__;

CD(DB)ID clash detected!
Either (1) the disc is not unique
or (2) you are trying to extend/replace some files of a yet existent disc.
(Note that the temporary WORKing directory will clash no matter what you do!)
Here is a list of yet existent albums which match that CDID:
__EOT__
    my ($i, $usr);
    for ($i = 1; $i <= @dlist; ++$i) {
        my $d = "${TARGET_DIR}$i";
        my $f = "$d/musicbox.dat";
        unless (open F, '<:encoding(UTF-8)', $f) {
            print "  [] Skipping due to failed open: $f\n";
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
        die "Can't close $f: $!" unless close F;
        unless (defined $at) {
            print "  [] No TITLE entry in $f!\n  ",
                  "Disc is corrupted and must be re-ripped!\n";
            next;
        }
        $at = "$ast - $at" if defined $ast;
        print "  [$i] $at\n";
    }
    print "  [0] None of these - the disc should create a new entry!\n";

jREDO:
    print "  Choose the number to use: ";
    $usr = <STDIN>;
    chomp $usr;
    unless ($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @dlist) {
        print "!  I'm expecting one of the [numbers] ... !\n";
        goto jREDO;
    }
    if ($usr == 0) {
        print "  .. forced to create a new disc entry\n";
        return "${TARGET_DIR}$i";
    } else {
        print "  .. forced to resume an existent album\n";
        return "${TARGET_DIR}$usr";
    }
} # }}}

sub cddb_query { # {{{
    print "\n";
    if ($CDInfo::IsFaked) {
        print "Creating CDDB entry fakes, 'cause CDDB-ID couldn't be queried\n";
        goto jFAKE;
    }
    eval 'require CDDB';
    if ($@) {
        print "Failed to load the CDDB.pm module!\n",
              "  Maybe it's not installed (search the internet for CPAN).\n",
              "  Shall i continue nonetheless?",
    } else {
        print 'Shall CDDB be contacted online (otherwise entries are faked)';
    }
    unless (user_confirm()) {
        print "  Creating entry fakes ...\n";
        goto jFAKE;
    }

    print "  Starting CDDB query for $CDInfo::Id\n";
    my $cddb = new CDDB;
    die "Can't create CDDB object: $!" unless defined $cddb;
    my @discs = $cddb->get_discs($CDInfo::Id, \@CDInfo::TrackOffsets,
                                 $CDInfo::TotalSeconds);

    if (@discs == 0) {
        print "! CDDB didn't match, i will create entry fakes!\n",
              '! Maybe there is no network connection? Shall i continue? ';
        exit 10 unless user_confirm();

jFAKE:  %CDDB = ();
        $CDDB{GENRE} = genre('Humour');
        $CDDB{ARTIST} = 'Unknown';
        $CDDB{ALBUM} = 'Unknown';
        $CDDB{YEAR} = '';
        my @titles;
        $CDDB{TITLES} = \@titles;
        for (my $i = 1; $i <= $CDInfo::TrackCount; ++$i) {
            my $s = 'TITLE ' . $i;
            push @titles, $s;
        }
        return;
    }

    my ($usr, $dinf);
jAREDO:
    $usr = 1;
    foreach (@discs) {
        my ($genre, undef, $title) = @$_; # (cddb_id)
        print "  [$usr] Genre:$genre, Title:$title\n";
        ++$usr;
    }
    print "  [0] None of those (creates a local entry fakes)\n";

jREDO:
    print "  Choose the number to use: ";
    $usr = <STDIN>;
    chomp $usr;
    unless ($usr =~ /\d+/ && ($usr = int $usr) >= 0 && $usr <= @discs) {
        print "! I'm expecting one of the [numbers] ... !\n";
        goto jREDO;
    }
    if ($usr == 0) {
        print "  creating entry fakes ...\n";
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
        print "! CDDB entry has illegal GENRE - using $CDDB{GENRE}\n";
    }
    {   my $aa = $usr->[2];
        my ($art, $alb, $i);
        $i = index $aa, '/';
        if ($i < 0) {
            $art = $alb = $aa;
        } else {
            $art = substr $aa, 0, $i;
            $alb = substr $aa, ++$i;
        }
        $art =~ s/^\s*(.*?)\s*$/$1/;
        ::utf8ify(\$art);
        $CDDB{ARTIST} = $art;
        $alb =~ s/^\s*(.*?)\s*$/$1/;
        ::utf8ify(\$alb);
        $CDDB{ALBUM} = $alb;
    }
    $CDDB{YEAR} = defined $dinf->{dyear} ? $dinf->{dyear} : '';
    $CDDB{TITLES} = $dinf->{ttitles};
    foreach (@{$dinf->{ttitles}}) {
        s/^\s*(.*?)\s*$/$1/;
        ::utf8ify(\$_);
    }

    print "  CDDB disc info for CD(DB)ID=$CDInfo::Id\n",
          "  (NOTE: terminal may not be able to display charset):\n",
          "    Genre=$CDDB{GENRE}, Year=$CDDB{YEAR}\n",
          "    Artist=$CDDB{ARTIST}\n",
          "    Album=$CDDB{ALBUM}\n",
          "    Titles in order:\n      ",
          join("\n      ", @{$CDDB{TITLES}}),
          "\n  Is this *really* the desired CD? ";
    goto jAREDO unless user_confirm();
} # }}}

sub user_tracks { # {{{
    print "\nDisc $CDInfo::Id contains $CDInfo::TrackCount songs - ",
          'shall all be ripped?';
    if (user_confirm()) {
        print "  Whee - all songs will be ripped!\n";
        $_->{IS_SELECTED} = 1 foreach (@Title::List);
        return;
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
    unless (@dt) {
        print "? So why are you using a disc ripper, then?\n";
        exit 42;
    }
    foreach (@dt) {
        if ($_ == 0 || $_ > $CDInfo::TrackCount) {
            print "!    Invalid track number: $_!\n\n";
            goto jREDO;
        }
    }

    $Title::List[$_ - 1]->{IS_SELECTED} = 1 foreach (@dt);
} # }}}

{package CDInfo; # {{{
    my ($DevId);
    BEGIN {
        # Id field may also be set from command_line()
        # Mostly set by _calc_id() or parse() only (except Ripper)
        $CDInfo::IsFaked = 0;
        $CDInfo::Id =
        $CDInfo::TotalSeconds =
        $CDInfo::TrackCount = undef;
        $CDInfo::FileRipper = $CDInfo::FallbackTrackCount = undef; # Impl subs
        @CDInfo::TrackOffsets = ();
    }

    sub init_paths {
        $CDInfo::DatFile = "$WORK_DIR/cdinfo.dat";
    }

    sub discover { # {{{
        no strict 'refs';
        die "System $^O not supported" unless defined *{"CDInfo::_os_$^O"};
        print "\nCDInfo: assuming an Audio-CD is in the drive ...\n";

        my $what = 'Calculated';
        my $i = &{"CDInfo::_os_$^O"}();
        if (defined $i) {
            print "! Error: $i\n",
                  "  Unable to collect CD Table-Of-Contents info.\n",
                  "  This may mean the Audio-CD was not yet fully loaded.\n",
                  "  It can also happen for copy-protection .. or whatever.\n",
                  "  Shall i continue?  I would collect track count info.\n",
                  "  Note: this may require a read of *all* the disc data!\n",
                  "  (I can't calculate a CDDB-ID anyway - no CDDB query..\n",
                  "  But i can generate a reproducable disk-ID etc.)\n",
                  "  A simple restart should be tried once first.  Continue? ";
            exit 1 unless ::user_confirm();

            $what = 'Faked';
            $CDInfo::IsFaked = 1;
            die "Don't know how to query the track count otherwise - sorry!\n"
                unless defined $CDInfo::FallbackTrackCount;
            $i = &$CDInfo::FallbackTrackCount();
            die "CDInfo: $i\n  Track count query failed, bailing out"
                if defined $i;

            $CDInfo::TrackCount = scalar @CDInfo::TrackOffsets;
            $CDInfo::Id = sprintf("%02dx%08x",
                                  $CDInfo::TrackCount, $CDInfo::TotalSeconds);
        }

        print "  $what disc ID: $CDInfo::Id\n  ",
              'Track offsets: ' . join(' ', @CDInfo::TrackOffsets),
              "\n  Total seconds: $CDInfo::TotalSeconds\n",
              "  Track count: $CDInfo::TrackCount\n";
    } # }}}

    sub _os_darwin { # {{{
        my $drive = defined $CDROM ? $CDROM : 1;
        $DevId = defined $CDROMDEV ? $CDROMDEV : $drive;
        print "  Darwin/Mac OS X: drive $drive and /dev/disk$DevId\n";

        $CDInfo::FileRipper = sub {
            my $title = shift;
            my $sf = '/dev/disk' . $DevId . 's' . $title->{NUMBER};
            return _unix_default_rip($sf, $title->{RAW_FILE});
        };
        $CDInfo::FallbackTrackCount = sub {
            # It's a pity!  Give MacOS X some time to reorder itself..
            sleep 1;
            return _unix_fallback_trackcount('/dev/disk');
        };

        # Problem: this non-UNIX thing succeeds even without media...
        ::v("Invoking drutil(1) -drive $drive toc");
        sleep 1;
        my $l = `drutil -drive $drive toc`;
        return "drive $drive: failed reading TOC: $!" if $?;
        my @res = split "\n", $l;

        my (@cdtoc, $leadout);
        for(;;) {
            $l = shift @res;
            return "drive $drive: no lead-out information found"
                unless defined $l;
            if ($l =~ /^\s*Lead-out:\s+(\d+):(\d+)\.(\d+)/) {
                $leadout = "999 $1 $2 $3";
                last;
            }
        }
        for (my $li = 0;; ++$li) {
            $l = shift @res;
            last unless defined $l;
            last unless $l =~ /^\s*Session\s+\d+,\s+Track\s+(\d+):
                                \s+(\d+):(\d+)\.(\d+)
                                .*/x;
            return "drive $drive: corrupted TOC: $1 follows $li"
                unless $1 == $li + 1;
            $cdtoc[$li] = "$1 $2 $3 $4";
        }
        return "drive $drive: no track information found" unless @cdtoc > 0;
        push @cdtoc, $leadout;

        _calc_cdid(\@cdtoc);
        return undef;
    } # }}}

    sub _os_freebsd { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "  FreeBSD: using drive $drive\n";
        die "FreeBSD support in fact missing";
    }

    sub _os_netbsd { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "  NetBSD: using drive $drive\n";
        die "NetBSD support in fact missing";
    }

    sub _os_linux { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "  Linux: using drive $drive\n";
        die "Linux support in fact missing";
    }

    sub _os_openbsd { # TODO
        my $drive = defined $CDROM ? $CDROM : '/dev/cdrom';
        print "  OpenBSD: using drive $drive\n";
        die "OpenBSD support in fact missing";
    }

    # Calculated CD(DB)-Id and *set*CDInfo*fields*
    sub _calc_cdid { # {{{
        # This is a stripped down version of CDDB.pm::calculate_id()
        my $cdtocr = shift;
        my ($sec_first, $sum);
        foreach (@$cdtocr) {
            my ($no, $min, $sec, $fra) = split /\s+/, $_, 4;
            my $frame_off = (($min * 60 + $sec) * 75) + $fra;
            my $sec_begin = int($frame_off / 75);
            $sec_first = $sec_begin unless defined $sec_first;
            # Track 999 was chosen for the lead-out information
            if ($no == 999) {
                $CDInfo::TotalSeconds = $sec_begin;
                last;
            }
            map { $sum += $_; } split //, $sec_begin;
            push @CDInfo::TrackOffsets, $frame_off;
        }
        $CDInfo::TrackCount = scalar @CDInfo::TrackOffsets;
        $CDInfo::Id = sprintf("%02x%04x%02x",
                              ($sum % 255),
                              ($CDInfo::TotalSeconds - $sec_first),
                              scalar(@CDInfo::TrackOffsets));
    } # }}}

    sub _unix_default_rip { # {{{
        my ($byteno, $blckno, $buf, $err) = (0, 0, undef, undef);
        my ($inf, $outf) = @_;
        return "can't open for reading: $inf: $!" unless open INFH, '<', $inf;
        # (Yet-exists case handled by caller)
        unless (open OUTFH, '>', $outf) {
            $err = $!;
            close INFH;
            return "can't open for writing: $outf: $err";
        }
        unless (binmode(INFH) && binmode(OUTFH)) {
            close OUTFH;
            close INFH;
            return "failed to set binary mode for $inf and/or $outf";
        }

jOUTER: while (1) {
            my $r = sysread INFH, $buf, 2352 * 20;
            unless (defined $r) {
                $err = "I/O read failed: $!";
                last;
            }
            last if $r == 0;
            $byteno += $r;
            $blckno += $r / 2352;

            for (my $o = 0;  $r > 0; ) {
                my $w = syswrite OUTFH, $buf, $r, $o;
                unless (defined $w) {
                    $err = "I/O write failed: $!";
                    last jOUTER;
                }
                $o += $w;
                $r -= $w;
            }
        }

        close OUTFH; # XXX
        close INFH; # XXX
        return $err if defined $err;
        print "    .. stored $blckno blocks ($byteno bytes)\n";
        return undef;
    } # }}}

    sub _unix_fallback_trackcount { # {{{
        my $diskdev = shift;
        my $i = 0;
        my $p = '/dev/disk' . $DevId . 's';
        for (; my $j = $i + 1; $i = $j) {
            my $x = $p . $j;
            last unless -e $x;

            $| = 1; print "    checking $x ... "; $| = 0;
            my $totlen = 0;
            return "failed to check $x" unless open FH, '<', $x;
            unless (binmode FH) {
                close FH;
                return "failed to set binary mode for $x";
            }
                my $buf;
                while (1) {
                    my $bread = sysread FH, $buf, 2352 * 20;
                    unless (defined $bread) {
                        close FH;
                        return "failed to read all data of $x";
                    }
                    last if $bread == 0;
                    $totlen += $bread;
                }
            close FH; # XXX
            push @CDInfo::TrackOffsets, $totlen;
            $CDInfo::TotalSeconds += $totlen;
            print "had $totlen bytes\n";
        }
        return "no such file: ${p}1.  Sure this is a CDROM?" unless $i != 0;
        $CDInfo::TrackCount = $i;
        return undef;
    } # }}}

    # write_data, read_data, parse_data (CDInfo::DatFile handling) {{{
    sub write_data {
        my $f = $CDInfo::DatFile;
        ::v("CDInfo::write_data($f)");
        die "Can't open $f: $!" unless open DAT, '>:encoding(UTF-8)', $f;
        print DAT "# $SELF CDDB info for project $CDInfo::Id\n",
                  "# Don't modify!  Or project needs to be re-ripped!!\n",
                  "CDID = $CDInfo::Id\n",
                  'TRACK_OFFSETS = ', join(' ', @CDInfo::TrackOffsets), "\n",
                  "TOTAL_SECONDS = $CDInfo::TotalSeconds\n";
        die "Can't close $f: $!" unless close DAT;
    }

    sub read_data {
        my $f = $CDInfo::DatFile;
        ::v("CDInfo::read_data($f)");
        die "Can't open $f: $!.\nCan't continue - remove $WORK_DIR and re-rip!"
            unless open DAT, '<:encoding(UTF-8)', $f;
        my @lines = <DAT>;
        die "Can't close $f: $!" unless close DAT;
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
            unless (/^\s*(.+?)\s*=\s*(.+?)\s*$/) {
                $emsg .= "Invalid line $_;";
                next;
            }
            my ($k, $v) = ($1, $2);
            if ($k eq 'CDID') {
                if (defined $old_id && $v ne $old_id) {
                    $emsg .= "Parsed CDID ($v) doesn't match;";
                    next;
                }
                $CDInfo::Id = $v;
            } elsif ($k eq 'TRACK_OFFSETS') {
                if (@CDInfo::TrackOffsets) {
                    $emsg .= 'TRACK_OFFSETS yet seen;';
                    next;
                }
                @CDInfo::TrackOffsets = split(/\s+/, $v);
            } elsif ($k eq 'TOTAL_SECONDS') {
                $emsg .= "illegal TOTAL_SECONDS: $v;" unless $v =~ /^(\d+)$/;
                $CDInfo::TotalSeconds = $1;
            } else {
                $emsg .= "Illegal line: $_;";
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

        print "\nResumed (parsed) CDInfo: disc: $CDInfo::Id\n  ",
              'Track offsets: ' . join(' ', @CDInfo::TrackOffsets),
              "\n  Total seconds: $CDInfo::TotalSeconds\n",
              "  Track count: $CDInfo::TrackCount\n";
        Title::create_that_many($CDInfo::TrackCount);
    }
    # }}}
} # }}}

# Title represents - a track
{package Title; # {{{
    # Title::vars,funs {{{
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
                print "  Raw ripped track $t->{NUMBER} exists - re-rip? ";
                next unless ::user_confirm();
            }

            print "  Rip track $t->{NUMBER} -> $t->{RAW_FILE}\n";
            my $emsg = &$CDInfo::FileRipper($t);
            if (defined $emsg) {
                print   "! Error occurred: $emsg\n",
                        "! Shall i deselect the track (else quit)?";
                exit 5 unless ::user_confirm();
                $t->{IS_SELECTED} = 0;
                unlink $t->{RAW_FILE} if -f $t->{RAW_FILE};
            }
        }
    }

    sub new {
        my ($class, $no) = @_;
        ::v("Title::new(number=$no)");
        my $nos = sprintf '%03d', $no;
        my $self = {
            NUMBER => $no,
            INDEX => $no - 1,
            NUMBER_STRING => $nos,
            RAW_FILE => "$WORK_DIR/$nos.raw",
            TARGET_PLAIN => "$TARGET_DIR/$nos",
            IS_SELECTED => 0,
            TAG_INFO => Title::TagInfo->new()
        };
        $self = bless $self, $class;
        $Title::List[$no - 1] = $self;
        return $self;
    }
    # }}}

# ID3v2.3 a.k.a. supported oggenc(1)/faac(1) tag stuff is bundled in here;
# fields are set to something useful by MBDB:: below
{package Title::TagInfo; # {{{
    sub new {
        my ($class) = @_;
        ::v("Title::TagInfo::new()");
        my $self = {};
        $self = bless $self, $class;
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
} # }}}
} # }}}

# MBDB - MusicBox (per-disc) database handling.
# This is small minded and a dead end street for all the data - but that's
# really sufficient here,
# because if the database has been falsely edited the user must correct it!
# At least a super-object based approach should have been used though.
# All strings come in as UTF-8 and remain unmodified
{package MBDB; # {{{
    # MBDB::vars,funs # {{{
    our ($CDDB, $AlbumSet, $Album, $Cast, $Group,   # [GROUP] objects
        $Error, @Data,                              # I/O & content
        @SongAddons, $SortAddons                    # First-Round addons
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
        @SongAddons = (); $SortAddons = '';
        _create_addons();

        my @old_data;
jREDO:  @old_data = @MBDB::Data;
        _reset_data();
        _write_editable(\@old_data);
        print "  Template: $MBDB::EditFile\n",
              "  Please do verify and edit this file as necessary\n",
              "  Shall i invoke EDITOR $ed? ";
        if (::user_confirm()) {
            my @args = ($ed, $MBDB::EditFile);
            system(@args);
        } else {
            print "  Ok, waiting: hit <RETURN> to continue ...";
            $ed = <STDIN>;
        }
        if (! _read_data($MBDB::EditFile)) {
            print "! Errors detected - edit once again!\n";
            goto jREDO;
        }
        @SongAddons = (); $SortAddons = '';

        print "  Once again - please verify the content:\n",
              "  (NOTE: terminal may not be able to display charset):\n";
        print "    $_\n" foreach (@MBDB::Data);
        print "  Is this data *really* OK? ";
        goto jREDO unless ::user_confirm();

        _write_final();
    }

    sub _create_addons {
        my $cddbt = $CDDB{TITLES};
        foreach my $title (@Title::List) {
            my $i = $title->{INDEX};
            my $t = $cddbt->[$i];
            if ($t =~ /^\s*(.+)\/\s*(.+)\s*$/) {
                my ($a, $t) = ($1, $2);
                $a =~ s/\s*$//;
                # First the plain versions
                $SortAddons .= "\n #" . _create_sort($a);
                $SongAddons[$i] = "\n #TITLE = $t\n #ARTIST = $a";
                # But try to take advantage of things like "feat." etc..
                my @as = _try_split_artist($a);
                foreach $a (@as) {
                    $SortAddons .= "\n  #" . _create_sort($a);
                    $SongAddons[$i] .= "\n  #ARTIST = $a";
                }
            }
        }
    }

    sub _create_sort {
        my $sort = shift;
        if ($sort =~ /^The/i && $sort !~ /^the the$/i) { # The The, The
            $sort =~ /^the\s+(.+)\s*$/i;
            $sort = "SORT = $1, The (The $1)";
        } elsif ($sort =~ /^\s*(\S+)\s+(.+)\s*$/) {
            $sort = "SORT = $2, $1 ($1 $2)";
        } else {
            $sort = "SORT = $sort ($sort)";
        }
        return $sort;
    }

    sub _try_split_artist {
        my ($art, $any, @r) = (shift, 0);
        while ($art =~ /(.+?)(?:feat(?:uring|\.)?|and|&)(.+)/i) {
            $any = 1;
            $art = $2;
            my $e = $1;
            $e =~ s/^\s*//;
            $e =~ s/\s*$//;
            push @r, $e;
        }
        if ($any) {
            $art =~ s/^\s*//;
            push @r, $art;
        }
        return @r;
    }

    sub _write_editable {
        my $dataref = shift;
        my $df = $MBDB::EditFile;
        ::v("Writing editable MusicBox data file as $df");
        die "Can't open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
        if (@$dataref > 0) {
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

        foreach my $title (@Title::List) {
            my $n = $title->{NUMBER};
            my $i = $title->{INDEX};
            my $a = (@SongAddons && defined $SongAddons[$i])?$SongAddons[$i]:'';
            die "Error writing $df: $!"
                unless print DF "[TRACK]\nNUMBER = $n\n",
                    "TITLE = $cddbt->[$i]$a\n\n";
        }

        if (@$dataref > 0) {
            die "Error writing $df: $!"
                unless print DF "\n# CONTENT OF FORMER USER EDIT:\n";
            foreach (@$dataref) {
                die "Error writing $df: $!" unless print DF "#$_\n";
            }
        }
        die "Error writing $df: $!"
            unless print DF "# vim:set fenc=utf-8 syntax=cfg tw=4221 et:\n";
        die "Can't close $df: $!" unless close DF;
    }

    sub _help_text {
        my $adder = (! $CDInfo::IsFaked ? ''
                     : "\n# (Disc-Id and thus [CDDB] entries were faked)\n");
        return <<__EOT__;
# S-MusicBox database, CDDB info: $CDDB{GENRE}/$CDInfo::Id$adder
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

    sub _write_final {
        my $df = $MBDB::FinalFile;
        ::v("Creating final MusicBox data file as $df");
        die "Can't open $df: $!" unless open DF, '>:encoding(UTF-8)', $df;
        die "Error writing $df: $!"
            unless print DF "[CDDB]\n",
                 (! $CDInfo::IsFaked ? ''
                  : "# (The [CDDB] entries were faked: offsets=seconds)\n"),
                 "CDID = $CDInfo::Id\n",
                 "TRACK_OFFSETS = ", join(' ', @CDInfo::TrackOffsets),
                 "\nTOTAL_SECONDS = $CDInfo::TotalSeconds\n";
        foreach (@MBDB::Data) {
            die "Error writing $df: $!" unless print DF $_, "\n";
        }
        die "Can't close $df: $!" unless close DF;
    }

    sub _read_data {
        my $df = shift;
        my $is_final = ($df eq $MBDB::FinalFile);
        _reset_data();

        die "Can't open $df: $!" unless open DF, '<:encoding(UTF-8)', $df;
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
                        print "! ERROR: $emsg\n";
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
                $emsg = "Line illegal: $_";
            }

            if (defined $emsg) {
jERROR:         $MBDB::Error = 1;
                print "! ERROR: $emsg\n";
                die "Disc database is corrupted!\n" .
                    "Remove $TARGET_DIR (!) and re-rip disc!"
                    if $is_final;
                $emsg = undef;
            }
        }
        if (defined $entry && defined($emsg = $entry->finalize())) {
            $MBDB::Error = 1;
            print "! ERROR: $emsg\n";
        }
        die "Can't close $df: $!" unless close DF;

        for (my $i = 1; $i <= $CDInfo::TrackCount; ++$i) {
            next if $Title::List[$i - 1]->{TAG_INFO}->{IS_SET};
            $MBDB::Error = 1;
            print "! ERROR: no entry for track number $i found\n";
        }
        $MBDB::Error == 0;
    }
    # }}}

{package MBDB::CDDB; # {{{
    sub is_key_supported {
        $_[0] eq 'CDID' || $_[0] eq 'TRACK_OFFSETS' || $_[0] eq 'TOTAL_SECONDS';
    }

    sub new {
        my ($class, $emsgr) = @_;
        if (defined $MBDB::CDDB) {
            $$emsgr = 'There may only be one (internal!) [CDDB] section';
            return undef;
        }
        ::v("MBDB::CDDB::new()");
        push @MBDB::Data, '[CDDB]';
        my @dat;
        my $self = {
            objectname => 'CDDB',
            CDID => undef, TRACK_OFFSETS => undef,
            TOTAL_SECONDS => undef, _data => \@dat
        };
        $self = bless $self, $class;
        $MBDB::CDDB = $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        return "$self->{objectname}: $k already set" if defined $self->{$k};
        $self->{$k} = $v;
        push @{$self->{_data}}, "$k = $v";
        push @MBDB::Data, "$k = $v";
        undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        return 'CDDB requires CDID, TRACK_OFFSETS and TOTAL_SECONDS;'
            unless (defined $self->{CDID} && defined $self->{TRACK_OFFSETS} &&
                    defined $self->{TOTAL_SECONDS});
        CDInfo::parse_data($self->{_data});
        undef;
    }
} # }}}

{package MBDB::ALBUMSET; # {{{
    sub help_text {
        return <<__EOT__;
# [ALBUMSET]: TITLE, SETCOUNT
#   If a multi-CD-Set is ripped each CD gets its own database file, say;
#   ALBUMSET and the SETPART field of ALBUM are how to group 'em
#   nevertheless: repeat the same ALBUMSET and adjust the SETPART field.
#   (No GENRE etc.: all that is in ALBUM only ... as you can see)
__EOT__
    }
    sub is_key_supported {
        $_[0] eq 'TITLE' || $_[0] eq 'SETCOUNT';
    }

    sub new {
        my ($class, $emsgr) = @_;
        if (defined $MBDB::AlbumSet) {
            $$emsgr = 'ALBUMSET yet defined';
            return undef;
        }
        ::v("MBDB::ALBUMSET::new()");
        push(@MBDB::Data, '[ALBUMSET]');
        my $self = {
            objectname => 'ALBUMSET',
            TITLE => undef, SETCOUNT => undef
        };
        $self = bless $self, $class;
        $MBDB::AlbumSet = $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        $self->{$k} = $v;
        push @MBDB::Data, "$k = $v";
        undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'ALBUMSET requires TITLE and SETCOUNT;'
            unless defined $self->{TITLE} && defined $self->{SETCOUNT};
        $emsg;
    }
} # }}}

{package MBDB::ALBUM; # {{{
    sub help_text {
        return <<__EOT__;
# [ALBUM]: TITLE, TRACKCOUNT, (SETPART, YEAR, GENRE, GAPLESS, COMPILATION)
#   If the album is part of an ALBUMSET TITLE may only be 'CD 1' - it is
#   required nevertheless even though it could be deduced automatically
#   from the ALBUMSET's TITLE and the ALBUM's SETPART - sorry!
#   I.e. SETPART is required, then, and the two TITLEs are *concatenated*.
#   GENRE is one of the widely (un)known ID3 genres.
#   GAPLESS states wether there shall be no silence in between tracks,
#   and COMPILATION wether this is a compilation of various-artists or so.
__EOT__
    }
    sub is_key_supported {
        my $k = shift;
        ($k eq 'TITLE' ||
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
        my $self = {
            objectname => 'ALBUM',
            TITLE => undef, TRACKCOUNT => undef,
            SETPART => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0
        };
        $self = bless $self, $class;
        $MBDB::Album = $self;
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
                if int $v > int $MBDB::AlbumSet->{SETCOUNT};
        } elsif ($k eq 'GENRE') {
            my $g = ::genre($v);
            return "ALBUM: $v not a valid GENRE (try --genre-list)"
                unless defined $g;
            $v = $g;
        }
        $self->{$k} = $v;
        push @MBDB::Data, "$k = $v";
        undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'ALBUM requires TITLE;' unless defined $self->{TITLE};
        $emsg .= 'ALBUM requires TRACKCOUNT;'
            unless defined $self->{TRACKCOUNT};
        $emsg .= 'ALBUM requires SETPART if ALBUMSET defined;'
            if defined $MBDB::AlbumSet && ! defined $self->{SETPART};
        $emsg;
    }
} # }}}

{package MBDB::CAST; # {{{
    sub help_text {
        return <<__EOT__;
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
__EOT__
    }
    sub is_key_supported {
        my $k = shift;
        ($k eq 'ARTIST' ||
            $k eq 'SOLOIST' || $k eq 'CONDUCTOR' ||
            $k eq 'COMPOSER' || $k eq 'SONGWRITER' ||
            $k eq 'SORT');
    }

    sub new {
        my ($class, $emsgr) = @_;
        my $parent = (@_ > 2) ? $_[2] : undef;
        if (! defined $parent && defined $MBDB::Cast) {
            $$emsgr = 'CAST yet defined';
            return undef;
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
        $self;
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
            push @{$self->{ARTIST}}, $_ foreach (@{$parent->{ARTIST}});
            push @{$self->{SOLOIST}}, $_ foreach (@{$parent->{SOLOIST}});
            push @{$self->{CONDUCTOR}}, $_ foreach (@{$parent->{CONDUCTOR}});
            push @{$self->{COMPOSER}}, $_ foreach (@{$parent->{COMPOSER}});
            $self->{_parent_composers} = scalar @{$self->{COMPOSER}};
            push @{$self->{SONGWRITER}}, $_ foreach (@{$parent->{SONGWRITER}});
        }
        $self;
    }
    sub set_tuple {
        my ($self, $k, $v) = @_;
        $k = uc $k;
        ::v("MBDB::$self->{objectname}::set_tuple($k=$v)");
        return "$self->{objectname}: $k not supported"
            unless is_key_supported($k);
        push @{$self->{$k}}, $v;
        push @MBDB::Data, "$k = $v";
        undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        if (defined $self->{parent} && $self->{parent} eq 'TRACK' &&
                @{$self->{ARTIST}} == 0) {
            $emsg .= 'TRACK requires at least one ARTIST;';
        }
        $emsg;
    }
    # For TRACK to decide where the composer list is to be placed
    sub has_parent_composers {
        $_[0]->{_parent_composers} != 0;
    }
} # }}}

{package MBDB::GROUP; # {{{
    sub help_text {
        return <<__EOT__;
# [GROUP]: LABEL, (YEAR, GENRE, GAPLESS, COMPILATION, [CAST]-fields)
#   Grouping information applies to all following tracks until the next
#   [GROUP]; TRACKs which do not apply to any GROUP must thus be defined
#   first!
#   GENRE is one of the widely (un)known ID3 genres.
#   GAPLESS states wether there shall be no silence in between tracks,
#   and COMPILATION wether this is a compilation of various-artists or so.
#   CAST-fields may be used to *append* to global [CAST] fields; to specify
#   CAST fields exclusively, place the GROUP before the global [CAST].
__EOT__
    }
    sub is_key_supported {
        my $k = shift;
        ($k eq 'LABEL' || $k eq 'YEAR' || $k eq 'GENRE' ||
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
        push @MBDB::Data, '[GROUP]';
        my $self = {
            objectname => 'GROUP',
            LABEL => undef, YEAR => undef, GENRE => undef,
            GAPLESS => 0, COMPILATION => 0,
            cast => MBDB::CAST::new_state_clone('GROUP')
        };
        $self = bless $self, $class;
        $MBDB::Group = $self;
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
            push @MBDB::Data, "$k = $v";
        } else {
            $self->{cast}->set_tuple($k, $v);
        }
        undef;
    }
    sub finalize {
        my $self = shift;
        ::v("MBDB::$self->{objectname}: finalizing..");
        my $emsg = undef;
        $emsg .= 'GROUP requires LABEL;' unless defined $self->{LABEL};
        my $em = $self->{cast}->finalize();
        $emsg .= $em if defined $em;
        $emsg;
    }
} # }}}

{package MBDB::TRACK; # {{{
    sub help_text {
        return <<__EOT__;
# [TRACK]: NUMBER, TITLE, (YEAR, GENRE, COMMENT, [CAST]-fields)
#   GENRE is one of the widely (un)known ID3 genres.
#   CAST-fields may be used to *append* to global [CAST] (and those of the
#   [GROUP], if any) fields; to specify CAST fields exclusively, place the
#   TRACK before the global [CAST].
#   Note: all TRACKs need an ARTIST in the end, from whatever CAST it is
#   inherited.
__EOT__
    }
    sub is_key_supported {
        my $k = shift;
        ($k eq 'NUMBER' || $k eq 'TITLE' ||
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
        push @MBDB::Data, '[TRACK]';
        my $self = {
            objectname => 'TRACK',
            NUMBER => undef, TITLE => undef,
            YEAR => undef, GENRE => undef, COMMENT =>undef,
            group => $MBDB::Group,
            cast => MBDB::CAST::new_state_clone('TRACK')
        };
        bless $self, $class;
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
                if int($v) <= 0 || int($v) > $CDInfo::TrackCount;
            $emsg = "TRACK: NUMBER $v yet defined"
                if $Title::List[$v - 1]->{TAG_INFO}->{IS_SET};
        }
        if (exists $self->{$k}) {
            $self->{$k} = $v;
            push @MBDB::Data, "$k = $v";
        } else {
            $self->{cast}->set_tuple($k, $v);
        }
        $emsg;
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
        $self->_create_tag_info() unless defined $emsg || $MBDB::Error;
        $emsg;
    }

    sub _create_tag_info { # {{{
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
            $s .= ', ' if ++$i > 0 || $x;
            $x = 0;
            $s .= $_;
        }
        foreach (@{$c->{CONDUCTOR}}) {
            $s .= ', ' if ++$i > 0 || $x;
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
        $composers = $s if length $s > 0;
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
        $tir->{TCOM} = $s if length $s > 0;

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
            if ! $c->has_parent_composers() && defined $composers;

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
    } # }}}
} # }}}
} # }}}

{package Enc;
    # vars,funs # {{{
    my $VolNorm;

    sub calculate_volume_normalize { # {{{
        $VolNorm = undef;
        my $nope = shift;
        if ($nope) {
            print "\nVolume normalization has been turned off\n";
            return;
        }
        print "\nCalculating average volume normalization over all tracks:\n  ";
        foreach my $t (@Title::List) {
            next unless $t->{IS_SELECTED};
            my $f = $t->{RAW_FILE};
            die "Can't open SOX stat for $f: $!"
                unless open SOX,
                    "sox -t raw -r44100 -c2 -w -s $f -e stat -v 2>&1 |";
            my $avg = <SOX>;
            die "Can't close SOX stat for $f: $!" unless close SOX;
            chomp $avg;

            if ($t->{INDEX} != 0 && $t->{INDEX} % 7 == 0) {
                print "\n  $t->{NUMBER}: $avg, ";
            } else {
                print "$t->{NUMBER}: $avg, ";
            }
            $VolNorm = $avg unless defined $VolNorm;
            $VolNorm = $avg if $avg < $VolNorm;
        }
        if (! defined $VolNorm || ($VolNorm >= 0.98 && $VolNorm <= 1.05)) {
            print "\n  Volume normalization fuzzy/redundant, turned off\n";
            $VolNorm = undef;
        } else {
            print "\n  Volume amplitude will be changed by: $VolNorm\n";
            $VolNorm = "-v $VolNorm"; # (For sox(1))
        }
    } # }}}

    sub encode_selected {
        print "\nEncoding selected tracks:\n";
        foreach my $t (@Title::List) {
            unless ($t->{IS_SELECTED}) {
                ::v("  Skipping $t->{NUMBER}: not selected");
                next;
            }
            print "  Track $t->{NUMBER} -> $t->{TARGET_PLAIN}.*\n";
            _encode_file($t);
        }
    }

    sub _encode_file {
        my $title = shift;
        my $tpath = $title->{TARGET_PLAIN};
        my @Coders;

        if (defined $VolNorm) {
            die "Can't open RAW input sox(1) pipe: $!"
                unless open RAW, "sox $VolNorm -t raw -r44100 -c2 -w -s " .
                    $title->{RAW_FILE} . ' -t raw - |';
        } else {
            die "Can't open RAW input file: $!"
                unless open RAW, '<', $title->{RAW_FILE};
        }
        die "binmode RAW input failed: $!" unless binmode RAW;

        push @Coders, Enc::Coder::MP3->new($title) if $MP3HI || $MP3LO;
        push @Coders, Enc::Coder::AAC->new($title) if $AACHI || $AACLO;
        push @Coders, Enc::Coder::OGG->new($title) if $OGGHI || $OGGLO;

        for (my $data;;) {
            my $bytes = sysread RAW, $data, 1024 * 1000;
            die "Error reading RAW input: $!" unless defined $bytes;
            last if $bytes == 0;
            $_->write($data) foreach @Coders;
        }

        die "Can't close RAW input: $!" unless close RAW;
        $_->del() foreach @Coders;
    }
    # }}}

{package Enc::Coder;
    # Super funs # {{{
    sub new {
        my ($self, $title, $hiname, $loname, $ext) = @_;
        my $p = $title->{TARGET_PLAIN};
        $self = {
            hiname => $hiname, hif => undef, hipath => $p . '.' . $ext,
            loname => $loname, lof => undef, lopath => $p . '.lo.' . $ext
        };
        bless $self;
    }

    sub write {
        my ($self, $data) = @_;
        if ($self->{hif}) {
            die "Write error $self->{hiname}: $!"
                unless print {$self->{hif}} $data;
        }
        if ($self->{lof}) {
            die "Write error $self->{loname}: $!"
                unless print {$self->{lof}} $data;
        }
        $self;
    }

    sub del {
        my ($self) = @_;
        if ($self->{hif}) {
            die "Close error $self->{hiname}: $!" unless close $self->{hif};
        }
        if ($self->{lof}) {
            die "Close error $self->{loname}: $!" unless close $self->{lof};
        }
        $self;
    }
    # }}}

{package Enc::Coder::MP3; # {{{
    our @ISA;
    BEGIN { @ISA = 'Enc::Coder'; }

    sub new {
        my ($self, $title) = @_;
        $self = Enc::Coder::new($self, $title, 'MP3', 'MP3LO', 'mp3');
        $self = bless $self;
        $self->_mp3tag_file($title);
        $self->_open($title, 1) if $MP3HI;
        $self->_open($title, 0) if $MP3LO;
        $self;
    }

    sub _open {
        my ($self, $title, $ishi) = @_;
        my ($s, $t, $b, $f) = ($ishi
                               ? ('high', ' (high)', '-V 0', $self->{hipath})
                               : ('low', 'LO', '-V 7', $self->{lopath}));
        ::v("Creating MP3 lame(1) $s-quality encoder");
        die "Can't open AAC$t: $!"
            unless open(my $fd, '| lame --quiet -r -x -s 44.1 --bitwidth 16 ' .
                "--vbr-new $b -q 0 - - >> $f");
        die "binmode error MP3$t: $!" unless binmode $fd;
        $self->{$ishi ? 'hif' : 'lof'} = $fd;
    }

    # MP3 tag stuff {{{
    sub _mp3tag_file {
        # Stuff in (parens) refers ID3 tag version 2.3.0, www.id3.org.
        my ($self, $title) = @_;
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
        {   my $l = length $tag;
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
            my $f;
            if ($i == 0) {
                next if $MP3HI == 0;
                $f = $self->{hipath};
            } else {
                next if $MP3LO == 0;
                $f = $self->{lopath};
            }
            die "Can't open $f: $!" unless open F, '>', $f;
            die "binmode $f failed: $!" unless binmode F;
            die "Error writing $f: $!" unless print F $header, $tag;
            die "Can't close $f: $!" unless close F;
        }
    }

    sub _mp3_frame {
        my ($fid, $ftxt) = @_;
        ::v("  MP3 frame: $fid: $ftxt") unless $fid eq 'COMM';
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
        $fid;
    }

    sub _mp3_string {
        my ($force_uni, $txtr, $lenr) = @_;
        my $i = $$txtr;
        my $isuni;
        unless ($force_uni) { eval {
            $isuni = Encode::from_to($i, 'utf-8', 'iso-8859-1', 1);
        }; }
        if ($force_uni || $@ || ! defined $isuni) {
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
    # }}}
} # }}}

{package Enc::Coder::AAC; # {{{
    our @ISA;
    BEGIN { @ISA = 'Enc::Coder'; }

    sub new {
        my ($self, $title) = @_;
        $self = Enc::Coder::new($self, $title, 'AAC', 'AACLO', 'mp4');
        $self = bless $self;
        $self->_faac_comment($title);
        $self->_open($title, 1) if $AACHI;
        $self->_open($title, 0) if $AACLO;
        $self;
    }

    sub _open {
        my ($self, $title, $ishi) = @_;
        my ($s, $t, $b, $f) = ($ishi
                               ? ('high', ' (high)', '-q 300', $self->{hipath})
                               : ('low', 'LO', '-q 80', $self->{lopath}));
        ::v("Creating AAC faac(1) $s-quality encoder");
        die "Can't open AAC$t: $!"
            unless  open(my $fd, '| faac -XP --mpeg-vers 4 -ws --tns ' .
                "$b $self->{aactag} -o $f - >/dev/null 2>&1");
        die "binmode error AAC$t: $!" unless binmode $fd;
        $self->{$ishi ? 'hif' : 'lof'} = $fd;
    }

     sub _faac_comment {
        my ($self, $title) = @_;
        my $ti = $title->{TAG_INFO};
        my $i;
        $self->{aactag} = '';
        $i = $ti->{ARTIST};
            $i =~ s/"/\\"/g;
            $self->{aactag} .= "--artist \"$i\" ";
        $i = $ti->{ALBUM};
            $i =~ s/"/\\"/g;
            $self->{aactag} .= "--album \"$i\" ";
        $i = $ti->{TITLE};
            $i =~ s/"/\\"/g;
            $self->{aactag} .= "--title \"$i\" ";
        $self->{aactag} .= "--track \"$ti->{TRCK}\" "
            . (defined $ti->{TPOS} ? "--disc \"$ti->{TPOS}\" " :'')
            . "--genre '$ti->{GENRE}' "
            . (defined $ti->{YEAR} ? "--year \"$ti->{YEAR}\"" :'');
        $i = $ti->{COMM};
        if (defined $i) {
            $i =~ s/"/\\"/g;
            $self->{aactag} .=" --comment \"S-MUSICBOX:COMM=$i\"";
        }
        ::v("AACTag: $self->{aactag}");
    }
} # }}}

{package Enc::Coder::OGG; # {{{
    our @ISA;
    BEGIN { @ISA = 'Enc::Coder'; }

    sub new {
        my ($self, $title) = @_;
        $self = Enc::Coder::new($self, $title, 'OGG', 'OGGLO', 'ogg');
        $self = bless $self;
        $self->_oggenc_comment($title);
        $self->_open($title, 1) if $OGGHI;
        $self->_open($title, 0) if $OGGLO;
        $self;
    }

    sub _open {
        my ($self, $title, $ishi) = @_;
        my ($s, $t, $b, $f) = ($ishi
                               ? ('high', ' (high)', '-q 8.5', $self->{hipath})
                               : ('low', 'LO', '-q 3.8', $self->{lopath}));
        ::v("Creating OGG Vorbis oggenc(1) $s-quality encoder");
        die "Can't open AAC$t: $!"
            unless open(my $fd, "| oggenc -Q -r $b $self->{oggtag} -o $f -");
        die "binmode error AAC$t: $!" unless binmode $fd;
        $self->{$ishi ? 'hif' : 'lof'} = $fd;
    }

    sub _oggenc_comment {
        my ($self, $title) = @_;
        my $ti = $title->{TAG_INFO};
        my $i;
        $self->{oggtag} = '';
        $i = $ti->{ARTIST};
            $i =~ s/"/\\"/g;
            $self->{oggtag} .= "--artist \"$i\" ";
        $i = $ti->{ALBUM};
            $i =~ s/"/\\"/g;
            $self->{oggtag} .= "--album \"$i\" ";
        $i = $ti->{TITLE};
            $i =~ s/"/\\"/g;
            $self->{oggtag} .= "--title \"$i\" ";
        $self->{oggtag} .= "--tracknum \"$ti->{TRACKNUM}\" "
            . (defined $ti->{TPOS}
                ? "--comment=\"TPOS=$ti->{TPOS}\" " : '')
            . "--comment=\"TRCK=$ti->{TRCK}\" "
            . "--genre \"$ti->{GENRE}\" "
            . (defined $ti->{YEAR} ? "--date \"$ti->{YEAR}\"" :'');
        $i = $ti->{COMM};
        if (defined $i) {
            $i =~ s/"/\\"/g;
            $self->{oggtag} .=" --comment \"S-MUSICBOX:COMM=$i\"";
        }
        ::v("OGGTag: $self->{oggtag}");
    }
} # }}}
} # Enc::Coder
} # Enc
# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
