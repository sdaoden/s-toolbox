#!/usr/bin/env perl
#@ gmane-fetch.pl: connect to $HOSTNAME and query/update all groups that are
#@ mentioned in the configuration file $RCFILE, store fetched articles of
#@ updated groups in $MBOX (appended), finally update $RCFILE.
#@ $RCFILE can contain comments: lines that start with # (like this one).
#@ To init a new group, simply place its name alone on a line, as in:
#@    gmane.mail.s-nail.user
#@ then run this script.
#@ TODO Primitive yet: no real error recovery, no command line, no help etc.
my $HOSTNAME = "news.gmane.org";
my $RCFILE = "${ENV{HOME}}/arena/data/mail/.gmane.rc";
my $MBOX = "${ENV{HOME}}/arena/data/mail/gmane";
#
# Copyright © 2014 Steffen (Daode) Nurpmeso <sdaoden@users.sf.net>.
#
# Based on the script nntp-to-mbox.pl that is:
#
# Copyright © 1999, 2000 Jamie Zawinski <jwz@jwz.org>
#
# Permission to use, copy, modify, distribute, and sell this software and its
# documentation for any purpose is hereby granted without fee, provided that
# the above copyright notice appear in all copies and that both that
# copyright notice and this permission notice appear in supporting
# documentation.  No representations are made about the suitability of this
# software for any purpose.  It is provided "as is" without express or 
# implied warranty.

use POSIX;
use Socket;

sub nntp_command {
    my ($cmd) = @_;
    $cmd =~ s/[\r\n]+$//; # canonicalize linebreaks.
    #print STDERR ">> $cmd\n";
    print NNTP "$cmd\r\n";
}

sub nntp_response {
    my ($no_error) = @_;
    $_ = <NNTP>;
    s/[\r\n]+$//; # canonicalize linebreaks.
    #print STDERR "<< $_\n";
    if ( ! m/^[0-9][0-9][0-9] / ) {
        die("malformed NNTP response: $_");
    }
    if ( ! $no_error && ! m/^2[0-9][0-9] / ) {
        die("NNTP error: $_");
    }
    return $_;
}

sub nntp_open {
    my ($hostname, $port) = @_;
    $port = 119 unless $port;

    # Open a socket and get the data
    my ($sockaddr,$there,$response,$tries) = ("Snc4x8");
    my $there = pack($sockaddr,2,$port, &getaddress($hostname));
    my ($a, $b, $c, $d) = unpack('C4', $hostaddr);

    my $proto = (getprotobyname ('tcp'))[2];

    if (!socket(NNTP,AF_INET,SOCK_STREAM,$proto)) {
	die "$0:  Fatal Error.  $!\n"; }
    if (!connect(NNTP,$there)) { die "$0:  Fatal Error.  $!\n"; }
    select(NNTP);$|=1;
    select(STDOUT);$|=1;

    nntp_response;

    sub getaddress {
      my($host) = @_;
      my(@ary);
      @ary = gethostbyname($host);
      return(unpack("C4",$ary[4]));
    }
}

sub nntp_close {
    nntp_command "QUIT";
    close NNTP;
}

sub nntp_group {
    my ($group) = @_;
    nntp_command "GROUP $group";
    $_ = nntp_response;
    my ($from, $to) = m/^[0-9]+ [0-9]+ ([0-9]+) ([0-9]+) .*/;
    return ($from, $to);
}

sub nntp_article {
    my ($fh, $group, $art) = @_;
    nntp_command "ARTICLE $art";
    $_ = nntp_response 1;

    if ( m/^423 / ) {
        print STDERR "\n! Article $art expired or cancelled?\n";
        return;
    }

    if ( ! m/^2[0-9][0-9] / ) {
        die("NNTP error: $_");
    }

    print $fh "From ${group}-${art} ", scalar gmtime, "\n";
    while (<NNTP>) {
        s/[\r\n]+$//;    # canonicalize linebreaks.
        last if m/^\.$/; # lone dot terminates
        s/^\.//;         # de-dottify.
        s/^(From )/>\1/; # de-Fromify.
        print $fh "$_\n";
    }
    print $fh "\n";
}

sub main {
   print STDERR ". Reading resource file ${RCFILE}..\n";
   open RC, '<', $RCFILE or die $^E;
   my @ogrps = <RC>;
   close RC or die $^E;

   my (@ngrps, @comments);
   my ($update, $query) = (0, 0);
   while (@ogrps) {
      my $g = shift @ogrps;
      chomp $g;
      if ($g =~ /^\s*#/) {
         push @comments, $g;
         next
      }

      $g =~ /^\s*([^\s]+)(?:\s+(\d+)\s+(\d+)\s+(\d+))?\s*$/;
      die "Error parsing <$g>" unless $1;
      if (!defined $2 || !defined $3 || !defined $4) {
         print STDERR ".. Group <$1> seems to be new: will only query status\n";
         ++$query;
         push @ngrps, [$1, 0, 0, -1]
      } else {
         ++$update;
         push @ngrps, [$1, $2, $3, $4]
      }
   }

   if ($update > 0) {
      open MBOX, '>>', $MBOX or die $^E;
   }
   print STDERR ". Connecting to ${HOSTNAME}..\n";
   nntp_open $HOSTNAME;

   for (my $i = 0; $i < @ngrps; ++$i) {
      my $gr = $ngrps[$i];
      if ($gr->[3] < 0) {
         print STDERR ". Query $gr->[0] .. "
      } else {
         print STDERR
            ". Update $gr->[0] #$gr->[3] ($gr->[1]/$gr->[2]) .. "
      }
      ($gr->[1], $gr->[2]) = nntp_group($gr->[0]);
      print STDERR "$gr->[1]/$gr->[2]\n";

      if ($gr->[3] < 0) {
         $gr->[3] = $gr->[2]
      } else {
         my $j = 0;
         while ($gr->[3] < $gr->[2]) {
            ++$gr->[3];
            if ($j++ == 0) {
               print STDERR "   $gr->[3]"
            } elsif ($j % 8 == 0) {
               print STDERR "\n   $gr->[3]"
            } else {
               print STDERR " $gr->[3]";
            }
            nntp_article(($update > 0 ? *MBOX : *STDOUT), $gr->[0], $gr->[3])
         }
         print STDERR "\n" if $j > 0;
      }
   }

   nntp_close;
   if ($update > 0) {
      close MBOX or die $^E
   }

   print STDERR ". Writing resource file ${RCFILE}..\n";
   open RC, '>', $RCFILE or die $^E;
   while (@comments) {
      my $c = shift @comments;
      print RC $c, "\n"
   }
   while (@ngrps) {
      my $gr = shift @ngrps;
      print RC "$gr->[0] $gr->[1] $gr->[2] $gr->[3]\n"
   }
   close RC or die $^E
}

main;
exit 0;
# s-it-mode
