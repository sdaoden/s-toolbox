#!/usr/bin/perl
#@ Simple thing to maintain entries of OpenBSD plus.html, version 2.
#@ - Leading and trailing whitespace of lines are ignored.
#@ - Everything before the first <!-- YYYY/MM/DD --> line is thrown away;
#@   any such line is supposed to start a new day.
#@ - Entries may span multiple lines; a blank line (or new day, or EOF)
#@   completes the currently active entry.
#@ - Inside entries <ONELETTER>.*?</> is expanded (see %EXPMAP below).
#@ - Inside entries links are produced for name(section) and name(section/arch);
#@   name(!section) and name(!section/arch) are not converted, but the
#@   exclamation mark is simply removed.
#@ - The links which are produced are percent-escaped rather acc. to RFC 3986,
#@   and their style is identical to OpenBSD man page content (i.e. archive is
#@   lowercase).
#@ - At the end of processing the order of all entries is reversed and the
#@   entry content is printed to STDOUT inside <li></li> markup.

# For which version of OpenBSD this is ment?  Current or X.Y
my $VERSION = 'OpenBSD Current';
my $WEB = 'http://www.openbsd.org/cgi-bin/man.cgi';

# Expansions; value may be undef -> remove this outer tag (keep content)
my %EXPMAP = (
    a => 'b',       # Arguments, Environ
    c => 'code',    # Code, Constants
    e => 'kbd',     # Examples (command lines)
    f => 'code',    # Function protos
    p => undef      # Paths, Files
);

# What is considered to be valid content of a manual page (-name)?
my $manre = '[][+.:\w-]+';

##

use strict;
use warnings;

sub urlesc {
    my $urlc = shift;
    $urlc =~ s/([^\w()'*~!.-])/sprintf '%%%02X', ord $1/eg;
    return $urlc;
}

my $_version = urlesc($VERSION);

sub buildurl {
    my %a = @_;
    my $u = ('<a href="' . $WEB . '?query=' . urlesc($a{query}) .
             '&manpath=' . $_version . '&sektion=' . urlesc($a{section}));
    my $o = '';
    if (defined $a{arch}) {
        $o = lc $a{arch};
        $u .= '&arch=' . urlesc($o);
        $o = '/' . $o;
    }
    $u .= '&format=html">' . $a{query} . '(' . $a{section} . $o . ')</a>';
    return $u;
}

my ($_exptags, @entry, @days) = join '', keys %EXPMAP;

sub buildentry {
    my ($l, $w) = '<li>' . join ' ', @entry;
    @entry = ();

    # Expansions
    $l =~ s#<([$_exptags])>(.*?)<\/>
           #defined $EXPMAP{$1} ? "<$EXPMAP{$1}>$2</$EXPMAP{$1}>" : $2#xeg;
    # abc(4) and abc(4/amd64) are expanded (not abc(3p))
    $l =~ s/($manre)\((\d)(?:\/(\w+))?\)
           /&buildurl(query => $1, section => $2, arch => $3)/xeg;
    # abc(!4) is not expanded to link but to plain abc(4)
    $l =~ s/($manre)\(!(\d(?:\/\w+)?)\)/$1(\L$2\E)/g;

    push @{$days[@days - 1]}, $l;# . '</li>';
}

while (<STDIN>) {
    chomp;
    s/^\s*(.*?)\s*$/$1/og;  # Remove leading + trailing WS
    s/\s+/ /og;             # Normalize WS to single spaces

    # Start a new day?
    if ($_ =~ /^<!-- \d{4}\/\d{2}\/\d{2} -->$/o) {
        buildentry() if @entry; # Finish partial entry, if any
        my @new_entries;
        push @new_entries, $_;
        push @days, \@new_entries;
        next;
    }
    # Premature EOF?
    last if $_ =~ /^<!--\s*EOF\s*-->$/o;
    # Ignore other HTML comments and everything before first day entry
    next if ($_ =~ /^<!--.*-->$/o || !@days);

    # Empty line starts new entry
    if (0 == length) {
        buildentry() if @entry;
    } else {
        push @entry, $_;
    }
}
buildentry() if @entry; # Finish partial entry, if any

while (@days) {
    my $d = pop @days;
    print shift(@$d), "\n";
    while (@$d) {
        print pop(@$d), "\n";
    }
}

exit 0;
# vim:set fenc=utf-8 filetype=perl syntax=perl ts=4 sts=4 sw=4 et tw=79:
