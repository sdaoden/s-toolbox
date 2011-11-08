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

my $WEB = 'http://www.openbsd.org/cgi-bin/man.cgi';
my $manre = '[][+.:\w-]+';

my @days;

while (<STDIN>) {
    chomp;
    s/^\s*(.*?)\s*$/$1/g;   # Remove leading + trailing WS
    next if /^\s*$/;        # Ign empty

    # Start a new day?
    if ($_ =~ /^<!--\s+\d{4}\/\d{2}\/\d{2}\s+-->/o) {
        my @new_entries;
        push @new_entries, $_;
        push @days, \@new_entries;
        next;
    }

    die "First non-blank line must EQ <!-- YYYY/MM/DD -->" unless @days;
    my ($l, $w) = '<li>' . $_;

    # abc(4)
    $w = '';
    while ($l =~ /(.*?)($manre)\((\d)\)(.*)/o) {
        $l = $4;
        $w .= $1 if defined $1;
        my ($q, $s, $ql) = ($2, $3);
        ($ql = $q) =~ s/([^\w()'*~!.-])/sprintf '%%%02X', ord $1/eg;
        $w .= "<a href=\"$WEB?query=$ql&sektion=$s&format=html\">$q($s)</a>";
    }
    $l = "$w$l" if length $w;

    # abc(4/amd64)
    $w = '';
    while ($l =~ /(.*?)($manre)\((\d)\/(\w+)\)(.*)/o) {
        $l = $5;
        $w .= $1 if defined $1;
        my ($q, $s, $a, $ql) = ($2, $3, $4);
        ($ql = $q) =~ s/([^\w()'*~!.-])/sprintf '%%%02X', ord $1/eg;
        $a = lc $a;
        $w .= "<a href=\"$WEB?query=$ql&sektion=$s&arch=$a&format=html\">$q($s/$a)</a>";
    }
    $l = "$w$l" if length $w;

    # abc(!4) is not expanded to link but to plain abc(4)
    $l =~ s/($manre)\(!(\d(?:\/\w+)?)\)/$1(\L$2\E)/og;
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
