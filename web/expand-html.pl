#!/usr/bin/perl -w
# Extremely simple... Reads from <STDIN>, dumps to <STDOUT>.
# Public Domain.
#
# TODO: no interlocked conditionals, no auto-link generation or -verify...
# TODO: Problems:
# - Recursive ifn?def..fi not yet implemented.
# - No if0 yet.
# - This is not possible:
#   XML = <?hreft "http://www.w3.org;<?ac XML?>"?>
#   Only this will do
#   XML = <?hreft "http://www.w3.org;<acronym>XML</acronym>"?>

# Default variables, most adjusted in preface_end()..
my %HASH = (
    AUTHOR      => 'Your Name',
    AUTHOR_AND_EMAIL => 'Your Name &lt;YOUR@MAIL&gt;',
    AUTHOR_AND_EMAIL_RAW => 'Your Name, YOUR@MAIL',
    #STREET      => 'Au&szlig;erhalb 42',
    #CITY        => 'CH-4221 Ancona',
    #PHONE       => '##49 (0)6151 / 101010',
    #FAX         => '##49 (0)6151 / 1010',
    WEB         => 'YOUR-WEB',
    MAIL        => 'YOUR@MAIL',
    COPY_DATE_SPEC => '1997 - 2012',
    #
    WWW         => '<strong class="_web" title="WEB!">&infin;</strong>',
    NAVI_UP     => '&uArr;',
    NAVI_FIRST  => '&lArr;',
    NAVI_LAST   => '&rArr;',
    NAVI_PREV   => '&larr;',
    NAVI_NEXT   => '&rarr;',
    NAVI_PTOP   => '<a class="_top" href="#_top" title="Page-Top">&uarr;</a>',
    PTOP_NAVI   => '<div class="_topdown"><p><a class="_topdownmove" ' .
                   'href="#_top" title="Page-Top">&uarr;</a>&nbsp;&nbsp;' .
                   '<a class="_topdownmove" href="#_bottom" ' .
                   'title="Page-Bottom">&darr;</a></p></div>',
    CVS         => undef,
    # Don't touch the rest directly, use <?var ?> PI's ...
    TITLE           => undef,
    DESC            => undef,
    KEYWORDS        => undef,
    TOPMENU         => undef,
    LAST_MODIFIED   => undef,
    HEAD_INJECT     => ''
);

my @sb;
my $line;
my $last_line = undef;
my $FHDL;
my $begin_end = 0;  # In between <?begin?> .. <?end?> ?
my $raw = 0;        # In a <?raw?> PI?
my $in_iffi = 0;    # In a <?if?>
my ($i,$j);

# Timestamp; do that first not in preface_end
(@sb = stat(STDIN)) || die "Cannot stat STDIN";
@sb = gmtime($sb[9]);
$i = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",
             $sb[5]+1900, $sb[4]+1, $sb[3], $sb[2], $sb[1], $sb[0]);
$HASH{'LAST_MODIFIED'} = $i;

# Everything until <?begin?>
while ($line = <STDIN>) {
    next if line_adjust_drop();
    last if preface_line();
}
preface_end();

# Header
open(FD, "<../header") || die $^E;
    $FHDL = *FD;
    process_fhdl();
close(FD);

# Everything until <?end?>
$FHDL = *STDIN;
$begin_end = 1;
process_fhdl();
$begin_end = 0;

# Footer
open(FD, "<../footer") || die $^E;
    $FHDL = *FD;
    process_fhdl();
close(FD);

exit(0);

sub line_adjust_drop {
    $line =~ s/\s+$//o;

    # <?raw?> lines are always passed through unchanged
    return 0 if $raw;
    # Empty lines are discarded
    return 1 if $line =~ /^\s*$/o;
    # Perlish comment lines are discarded
    return 1 if $line =~ /^\s*#/o;

    $line =~ s/^\s+//o;
    $line =~ s/\s+/ /o;
    return 0;
}

sub preface_line {
    return 1 if $line =~ /<\?begin\?>/o;

    # Special TOPMENU?
    if ($line =~ /^\s*TOPMENU/o) {
        print STDERR "TOPMENU already set\n" if $HASH{TOPMENU};
        my $str;
        while ($line = <STDIN>) {
            $line =~ s/^\s+//o;
            $line =~ s/\s+$//o;
            $line =~ s/\s+/ /o;
            last if $line eq 'TOPMENU';
            $str .= "<li>$line&nbsp;&nbsp;</li>";
        }
        $HASH{TOPMENU} = $str;
    # Variable assignments
    } elsif ($line =~ /^\s*(\w+)\s*=\s*(.*)$/o) {
        print STDERR "Variable $1 already set\n" if $HASH{$1};
        $HASH{$1} = $2;
    } else {
        die "Unknown directive, 1.: $line";
    }
    return 0;
}

sub preface_end {
    unless (defined $HASH{TITLE}) {
        print STDERR "TITLE variable not set!!\n";
        $HASH{TITLE} = 'TITLE NOT SET!!';
    }
    $HASH{PACK_LEVEL} = 1 unless defined $HASH{PACK_LEVEL};
}

sub process_fhdl {
    while ($line = <$FHDL>) {
        next if line_adjust_drop();
        last if line_conversion();
    }
    print($last_line, "\x0A") if $last_line;
    $last_line = undef;
    die "Conditional still open!" if $in_iffi != 0;
}

sub line_conversion {
    if ($line =~ /<\?.+\?>/o) {
        my $i = pi_expansion();
        return 1 if $i > 0;
        return 0 if $i < 0;
    }

    # German umlauts and sharp-s
    $line =~ s/\xC3\xA4/&auml;/og;
    $line =~ s/\xC3\x84/&Auml;/og;
    $line =~ s/\xC3\xB6/&ouml;/og;
    $line =~ s/\xC3\x96/&Ouml;/og;
    $line =~ s/\xC3\xBC/&uuml;/og;
    $line =~ s/\xC3\x9C/&Uuml;/og;
    $line =~ s/\xC3\x9F/&szlig;/og;

    if ($raw) {
        print($last_line, "\x0A") if $last_line;
        $last_line = undef;
        print $line, "\x0A";
    } else {
        if ($last_line && $last_line =~ />$/ && $line =~ /^</) {
                $last_line .= $line;
        } else {
            print($last_line, "\x0A") if $last_line;
            $last_line = (length($line) > 0) ? $line : undef;
        }
    }
    return 0;
}

sub pi_expansion {
    return 0 if index($line, '<?xml ') == 0;
    my $xl = $line;
    $line = '';

    while ($xl =~ /(.*?)<\?(\w+)(?:\s+(?:(?:"([^"]*)")|([^\?]*)))?\?>(.*)/o) {
        $line .= $1 if (defined $1 && length($1) > 0);
        $xl = defined $5 ? $5 : '';
        $i = $2;
        $j = defined $3 ? $3 : defined $4 ? $4 : '';#undef;

        # Variable?
        if ($i eq 'ev') {
            unless (exists $HASH{$j} && defined $HASH{$j}) {
                print STDERR "ev: <$j> not set!\n";
                $i = '?';
            } else {
                $i = $HASH{$j};
            }
            # May contain more ev's, expand and redo!
            $xl = $i . $xl;
            next;
        }
        # Local link?
        elsif ($i eq 'lref') {
            $i = "<a href=\"$j\">$j</a>";
            $line .= $i;
        }
        # Local link with title/text?
        elsif ($i eq 'lreft') {
            $j =~ /(.+?);(.+)/o;
            my $w = $1;
            my $z = $2;
            my $y = $z;
            while ($y =~ s/(.*?)<\/?\w+>(.*)/$1$2/g) {;}
            $i = "<a href=\"$w\" title=\"$y\">$z</a>";
            $line .= $i;
        }
        # Hyper link?
        elsif ($i eq 'href') {
            $i = "<a href=\"$j\">$HASH{WWW}&nbsp;$j</a>";
            $line .= $i;
        }
        # Hyper link with title/text?
        elsif ($i eq 'hreft') {
            $j =~ /(.+?);(.+)/o;
            my $w = $1;
            my $z = $2;
            my $y = $z;
            while ($y =~ s/(.*?)<\/?\w+>(.*)/$1$2/g) {;}
            $i = "<a href=\"$w\" title=\"$y\">" .
                "$HASH{WWW}&nbsp;$z</a>";
            $line .= $i;
        }
        # Acronym?
        elsif ($i eq 'ac') {
            $i = "<acronym>$j</acronym>";
            $line .= $i;
        }
        # Acronym with title?
        elsif ($i eq 'act') {
            $j =~ /(.+);(.+)/o;
            $i = "<acronym title=\"$2\">$1</acronym>";
            $line .= $i;
        } elsif ($i eq 'ifdef') {
            die "ifdef: interlocked conditionals not supported"
                if $in_iffi != 0;
            $in_iffi = 1;
            elsefi_skip() unless defined $HASH{$j};
            return -1;
        } elsif ($i eq 'ifndef') {
            die "ifdef: interlocked conditionals not supported"
                if $in_iffi != 0;
            $in_iffi = 1;
            elsefi_skip() if defined $HASH{$j};
            return -1;
        } elsif ($i eq 'else') {
            # We only come here if last condition was true
            elsefi_skip();
            return -1;
        } elsif ($i eq 'fi') {
            die "Unmatched <?fi?>" if $in_iffi == 0;
            $in_iffi = 0;
            return -1;
        } elsif ($i eq 'raw') {
            if ($j =~ /ON|on/)  { $raw = 1; }
            elsif ($j =~ /OFF|off/) { $raw = 0; }
            else { die "Bad <?raw?>: $line"; }
            return -1;
        } elsif ($i eq 'include_raw') {
            $j = $1 if $j =~ /^"(.*)"$/o;
            open(MYFD, "<$j") || die $^E;
            print $_ foreach (<MYFD>);
            close MYFD;
            return -1;
        } elsif ($i eq 'end') {
            die "<?end?> may not be used here" unless $begin_end;
            return 1;
        } elsif ($i eq 'cvsid') {
            $line .= "<br />$HASH{CVS}" if defined $HASH{CVS};
        } else {
            die "Unknown directive, 2.: $i";
        }
    }

    $line .= $xl if length($xl) > 0;
    return 0;
}

sub elsefi_skip {
    while ($line = <$FHDL>) {
        last if $line =~ /^\s*<\?else\?>/o;
        if ($line =~ /^\s*<\?fi\?>/o) {
            $in_iffi = 0;
            last;
        }
    }
}

# vim:set fenc=utf-8 syntax=perl ts=4 sts=4 sw=4 et tw=79:
