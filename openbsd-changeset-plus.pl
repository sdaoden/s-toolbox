#!/usr/bin/perl
#@ Simple thing to maintain entries of OpenBSD plus.html.
#@ This one creates some kind of "Changeset", either from the command line with
#@ a (OpenBSD i.e. Canada/Mountain) date and a list of files, as in
#@  $ openbsd-changeset-plus.pl "OpenBSD-Time" [:FILES:]
#@ or from within mutt(1) or any other thing; pipe to STDIN of it a mail as is
#@ send to the OpenBSD source-changes mailing list.
#@ In both cases log and diff are sent to $PAGER, which might be exec'd,
#@ so one better ensures it doesn't go away for one-screenful's of data..
#
# Public Domain.

# Two possibilities:
# $USE_CHECKOUT != 0: $REPODIR must be a cvs(1) checkout; cvs(1) log and diff
# $USE_CHECKOUT == 0: $REPODIR must be a cvsync(1) clone; cvs(1) rlog and rdiff
my $USE_CHECKOUT = 0;
my $REPODIR = "$ENV{HOME}/arena/code.openbsd";

# The pager/ed/ to use
my $PAGER = '/usr/bin/less --ignore-case --no-init';
# (In mail mode this would do, too)
#my $PAGER = 'sh -c "(echo ========; cat)" >>~/tmp/LOG < ';
# (And in command line mode this)
#my $PAGER = '(echo ========; cat) >>~/tmp/LOG';

# Do print *only* the log message?
my $LOGONLY = 0;

# Include cvs(1) diff?
my $CVSDIFF = 1     && !$LOGONLY;

# In pipe mode this script exec's off to $PAGER, so store the data somewhere to
# not mess up a pipeline which we may be part of
my $TMPFILE = "$ENV{HOME}/tmp/openbsd-changeset-plus.dat";

# Time fuzzyness in seconds; is /2 before and /2 after real time XXX silly
my $FUZZY = 180;

# /usr/sbin/zdump -v Canada/Mountain
# Only mails/times in covered range will produce correct results
my @ZONE = (
    [ 'Sun Nov  6 07:59:59 2011', 1320566399 - 6*60*60, '-0600' ],
    [ 'Sun Mar 11 08:59:59 2012', 1331456399 - 7*60*60, '-0700' ],
    [ 'Sun Nov  4 07:59:59 2012', 1352015999 - 6*60*60, '-0600' ],
    [ 'Sun Mar 10 08:59:59 2013', 1362905999 - 7*60*60, '-0700' ],
    [ 'Sun Nov  3 07:59:59 2013', 1383465599 - 6*60*60, '-0600' ]
);

##

use strict;
use warnings;

use Date::Parse;

if ($USE_CHECKOUT) { chdir $REPODIR || die "Can't chdir $REPODIR: $^E"; }

$ENV{TZ} = 'Canada/Mountain'; # (Only for CVS log output and such)
my ($Obsd, $Gmt, $Files);

if (-t STDIN) {
    &command_line();
} else {
    &mailparse();
}
exit 1;

sub command_line() {
    @ARGV > 1 ||
        die 'USAGE: openbsd-changeset-plus.pl "OpenBSD-Time" [:FILES:]';

    open PAGER, "| $PAGER" || die "Can't open $PAGER: $^E";
    $| = 1; $| = 0;
    select PAGER;
    print "\n"; $| = 1;

    calctimes($ARGV[0]);
    shift @ARGV;
    $Files = \@ARGV;
    cvslog();
    cvsdiff();

    $| = 1;
    select STDOUT;
    $| = 0;
    close PAGER;
    exit 0;
}

sub mailparse {
    @ARGV == 0 ||
        die 'USAGE: "one-source-changes-mail" | openbsd-changeset-plus.pl';

    my ($mod, $date, @files_store, $dir, $files);
    while (<STDIN>) {
        chomp;
        next unless /^Module name:\s+([^\s]+)$/;
        $mod = $1;
        goto jMOD;
    }
    die 'Invalid mail 1.: no "Module name: MODULE" line';
jMOD:
    $date = <STDIN>;
    die 'Invalid mail 2.: no "Changes by: COMMITTER DATE" line'
        unless $date =~ /^Changes by:\s+([^\s]+)\s+(.+)/;
    $date = $2;

    open TMPFILE, '>', $TMPFILE || die "Can't open $TMPFILE: $^E";
    $| = 1; $| = 0;
    select TMPFILE;

    print "Committer: $1\n" unless $LOGONLY;
    calctimes($date);

    $Files = \@files_store;
    $dir = 'FAULTY MAIL MESSAGE: NO DIRECTORY';
    while (<STDIN>) {
        chomp;
        # Ends with blank line
        next if /^(?:\s*$|(?:Modified|Added) files:)/;
        # Order is (each optional): Modified,Added,Removed, then 'Log message:'
        # Simply copy over removed file section and log message
        if (/^(?:Removed files|Log message):/) {
            print $_, "\n" unless $LOGONLY;
            print $_ while (<STDIN>);
            last;
        }
        # A file group
        if (/^\s+([^\s]+)\s*:\s*(.*)/) {
            $dir = $1;
            $files = $2;
        } else {
            /^\s+(.*)/;
            $files = $1;
        }
        push @$Files, $mod .'/'. $dir .'/'. $_ foreach (split /\s+/, $files);
    }

    cvsdiff();

    $| = 1;
    exec "$PAGER $TMPFILE";
    exit 1;
}

sub sync {
    print "\n";
    $| = 1;
    $| = 0;
}

sub calctimes {
    my ($date, $e) = @_;
    $Obsd = strtime($date, undef);
    $Obsd->[0] > 42 || die 'Unsupported time format';
    foreach (@ZONE) {
        $e = $_;
        goto jOK if $Obsd->[0] <= $e->[1];
    }
    die "NO ZONE INFORMATION for $date; see and adjust script header\n";
jOK:
    $Gmt = strtime($date, $e->[2]);

    print "Time: $Obsd->[1] OpenBSD, that's $Gmt->[1] UTC ($Gmt->[0])\n"
          unless $LOGONLY;
    sync();

    $Obsd->[0] = $Gmt->[0] - $FUZZY/2;
    $Gmt->[0] += $FUZZY/2;
}

sub strtime {
    my ($t, $unix) = @_;
    $unix = str2time($t . ' ' . ($unix || '-0000'));
    my ($ts, $tm, $th, $dd, $dm, $dy, undef, undef, undef) = gmtime $unix;
    $ts = '0' . $ts if $ts < 10;
    $tm = '0' . $tm if $tm < 10;
    $th = '0' . $th if $th < 10;
    $dd = '0' . $dd if $dd < 10;
    $dm += 1;
    $dm = '0' . $dm if $dm < 10;
    $dy += 1900;
    return [ $unix, "$dy-$dm-$dd $th:$tm:$ts" ];
}

sub cvslog {
    my $comm = $USE_CHECKOUT ? 'log -NS' : "-d $REPODIR rlog -NS";
    open L,
        "/bin/sh -c 'cvs -f $comm -d \"\@$Obsd->[0]<\@$Gmt->[0]\" @$Files' |" ||
        die $^E;
    while (<L>) { last if /^-+$/; }
    while (<L>) { last if /^=+$/; print $_; }
    while (<L>) {}
    close L;
    sync();
}

sub cvsdiff {
    return unless $CVSDIFF;

    my $comm = $USE_CHECKOUT ? 'diff -Napu ' : "-d $REPODIR rdiff -u ";
    open D,
        "/bin/sh -c 'cvs -f $comm -D \@$Obsd->[0] -D \@$Gmt->[0] @$Files' |" ||
        die $^E;
    while (<D>) { print $_; }
    close D;
    sync();
}

# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
