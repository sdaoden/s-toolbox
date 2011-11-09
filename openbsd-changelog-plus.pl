#!/usr/bin/perl
#@ Simple thing to maintain entries of OpenBSD plus.html
#@ - Blank lines are ignored
#@ - First non-blank line must consist only of <!-- YYYY/MM/DD -->
#@ - Any other such line starts a new day
#@ - All remaining lines are converted to <li> lines in FILO order
#@ - Links are produced for name(section) and name(section/arch);
#@   name(!section) and name(!section/arch) are not converted, but the
#@   exclamation mark is simply removed.
#@ - The links which are produced are percent-escaped rather acc. to RFC 3986,
#@   and their style is identical to OpenBSD man page content (i.e. archive is
#@   lowercase)

# For which version of OpenBSD this is ment?  Current or X.Y
my $VERSION = 'OpenBSD Current';
my $WEB = 'http://www.openbsd.org/cgi-bin/man.cgi';

my $manre = '[][+.:\w-]+';

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
    my $o;
    if (defined $a{arch}) {
        $o = lc $a{arch};
        $u .= '&arch=' . urlesc($o);
        $o = '/' . $o;
    }
    $u .= '&format=html">' . $a{query} . '(' . $a{section} . $o . ')</a>';
    return $u;
}

my @days;
while (<STDIN>) {
    chomp;
    s/^\s*(.*?)\s*$/$1/og;  # Remove leading + trailing WS
    s/\s+/ /og;             # Normalize WS to single spaces
    next if /^\s*$/o;       # Ignore empty

    # Start a new day?
    if ($_ =~ /^<!-- \d{4}\/\d{2}\/\d{2} -->/o) {
        my @new_entries;
        push @new_entries, $_;
        push @days, \@new_entries;
        next;
    }

    die "First non-blank line must EQ <!-- YYYY/MM/DD -->" unless @days;
    my ($l, $w) = '<li>' . $_;

    # abc(4) and abc(4/amd64) are expanded (not abc(3p))
    $l =~ s/($manre)\((\d)(?:\/(\w+))?\)
           /&buildurl(query => $1, section => $2, arch => $3)/xeg;

    # abc(!4) is not expanded to link but to plain abc(4)
    $l =~ s/($manre)\(!(\d(?:\/\w+)?)\)/$1(\L$2\E)/g;
    push @{$days[@days - 1]}, $l;
}

while (@days) {
    my $d = pop @days;
    print shift(@$d), "\n";
    while (@$d) {
        print pop(@$d), "\n";
    }
}

exit 0;
