#!/usr/bin/perl
#@ Simple thing to maintain entries of OpenBSD plus.html

my $WEB = 'http://www.openbsd.org/cgi-bin/man.cgi';
my $manre = '[][+.:\w-]+';
my @days;

while (<STDIN>) {
    chomp;
    next if /^\s*$/;
    if ($_ =~ /^<!--\s+\d{4}\/\d{2}\/\d{2}\s+-->/) {
        my @new_entries;
        push @new_entries, $_;
        push @days, \@new_entries;
        next;
    }
    die "First line must contain <!-- YYYY/MM/DD --> tag" unless @days;

    my ($l, $w) = $_;
    $l =~ s/^(\w)/<li>$1/;

    # abc(4)
    $w = '';
    while (defined $l && $l =~ /(.*?)($manre)\((\d)\)(.*)/) {
        $l = $4;
        $w .= $1 if defined $1;
        my ($q, $s, $ql) = ($2, $3);
        ($ql = $q) =~ s/\[/%5B/g;
        $ql =~ s/\+/%2B/g;
        $w .= "<a href=\"$WEB?query=$ql&sektion=$s&format=html\">$q($s)</a>";
    }
    $l = "$w$l" if length $w;

    # abc(4/amd64)
    $w = '';
    while (defined $l && $l =~ /(.*?)($manre)\((\d)\/(\w+)\)(.*)/) {
        $l = $5;
        $w .= $1 if defined $1;
        my ($q, $s, $au, $al, $ql) = ($2, $3, $4);
        ($ql = $q) =~ s/\[/%5B/g;
        $ql =~ s/\+/%2B/g;
        $al = lc $au;
        $au = uc $au;
        $w .= "<a href=\"$WEB?query=$ql&sektion=$s&arch=$al&format=html\">$q($s/$au)</a>";
    }
    $l = "$w$l" if length $w;

    # abc(!4) is not expanded to link but to plain abc(4)
    $l =~ s/($manre)\(!(\d)\)/$1($2)/g;
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
