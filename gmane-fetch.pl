#!/usr/bin/env perl
require 5.008_001;
#@ gmane-fetch.pl: connect to any hostnames in %HOSTS and query/update all
#@ groups that are mentioned for the corresponding name in the configuration
#@ file $RCFILE (are named NAME.), store fetched articles of updated groups in
#@ $MBOX (appended), finally update $RCFILE.
#@ $RCFILE can contain comments: lines that start with # (like this one).
#@ To init a new group, simply place its name alone on a line, as in:
#@    gwene.mail.s-mailx
#@ then run this script.
#@ TODO Primitive yet: no command line, no help, no file locking.
my %HOSTS = ("gmane" => "news.gmane.org");#, "gwene" => "news.gwene.org");
my $RCFILE = "${ENV{HOME}}/sec.arena/mail/.gmane.rc";
my $MBOX = "${ENV{HOME}}/sec.arena/mail/gmane";
my $SAFE_FSYNC = 1; # fsync(3) after each message (etc.)?
#
# Copyright (c) 2014 - 2018 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
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

use diagnostics -verbose;
use warnings;
use strict;

use Encode;
use IO::Handle;
use POSIX;
use Socket;

my (@OGRPS, @COMMENTS, @NGRPS);
my ($RCFILE_SAVE, $UPDATE, $QUERY) = (0, 0, 0);

sub rcfile_parse{
   print STDERR ". Reading resource file ${RCFILE}..\n";
   open RC, '<:bytes', $RCFILE or die $^E;
   @OGRPS = <RC>;
   close RC or die $^E;

   while(@OGRPS){
      my $g = shift @OGRPS;
      chomp $g;
      if($g =~ /^\s*#/){
         push @COMMENTS, $g;
         next
      }

      $g =~ /^\s*([^\s]+)(?:\s+(\d+)\s+(\d+)\s+(\d+))?\s*$/;
      die "Error parsing <$g>" unless $1;
      if(!defined $2 || !defined $3 || !defined $4){
         print STDERR ".. Group <$1> seems to be new: will only query status\n";
         ++$QUERY;
         push @NGRPS, [$1, 0, 0, -1]
      }else{
         ++$UPDATE;
         push @NGRPS, [$1, $2, $3, $4]
      }
   }
}

sub rcfile_save{
   return unless $RCFILE_SAVE;

   print STDERR ". Writing resource file ${RCFILE}..\n";
   open RC, '>:bytes', $RCFILE or die $^E;
   while(@COMMENTS){
      my $c = shift @COMMENTS;
      print RC $c, "\n"
   }
   while(@NGRPS){
      my $gr = shift @NGRPS;
      print RC "$gr->[0] $gr->[1] $gr->[2] $gr->[3]\n"
   }
   RC->flush;
   RC->sync if $SAFE_FSYNC;
   close RC or die $^E
}

sub nntp_command{
   my ($cmd) = @_;
   $cmd =~ s/[\r\n]+$//; # canonicalize linebreaks.
   #print STDERR ">> $cmd\n";
   print NNTP "$cmd\r\n"
}

sub nntp_response{
   my ($no_error) = @_;
   $_ = <NNTP>;
   die "Got no NNTP response" unless defined $_;
   s/[\r\n]+$//; # canonicalize linebreaks.
   #print STDERR "<< $_\n";
   die "Malformed NNTP response: $_" if !m/^[0-9][0-9][0-9] /;
   die "NNTP error: $_" if !$no_error && !m/^2[0-9][0-9] /;
   $_
}

sub nntp_open{
   my ($hostname, $port) = @_;
   $port = 119 unless $port;

   my $iaddr = gethostbyname($hostname);
   die "$0: Cannot resolve hostname \"$hostname\".  $!" unless $iaddr;

   # Open a socket and get the data

   die "$0: Cannot create socket: $!\n"
      if !socket NNTP, AF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2];

   die "$0: Cannot connect: $!\n"
      unless connect NNTP, pack_sockaddr_in($port, $iaddr);
   binmode NNTP, ":bytes";
   select(NNTP);$|=1;

   nntp_response;
}

sub nntp_close{
   nntp_command "QUIT";
   close NNTP
}

sub nntp_group{
   my ($group) = @_;
   nntp_command "GROUP $group";
   $_ = nntp_response 1;
   return (undef, undef) if /^411 /; # No such newsgroup
   my ($from, $to) = m/^[0-9]+ [0-9]+ ([0-9]+) ([0-9]+) .*/;
   ($from, $to)
}

sub nntp_article{
   my ($fh, $group, $art) = @_;
   nntp_command "ARTICLE $art";
   $_ = nntp_response 1;

   if(m/^423 /){
      print STDERR "\n! Article $art expired or cancelled?\n";
      return 0
   }
   if(!m/^2[0-9][0-9] /){
      print STDERR "\n! NNTP error: $_\n";
      return 0
   }

   print $fh "From ${group}-${art} ", scalar gmtime, "\n";
   while(<NNTP>){
      s/[\r\n]+$//;    # canonicalize linebreaks.
      last if m/^\.$/; # lone dot terminates
      s/^\.//;         # de-dottify.
      s/^(From )/>$1/; # de-Fromify.
      print $fh "$_\n"
   }
   print $fh "\n";
   $fh->flush;
   $fh->sync if $SAFE_FSYNC;
   1
}

sub main {
   my ($o);

   rcfile_parse;

   if($UPDATE > 0){
      open MBOX, '>>:bytes', $MBOX or die $^E;
      select MBOX;$|=1;
   }

   foreach my $name (keys %HOSTS){
      my $hostname = $HOSTS{$name};
      print STDERR ". Connecting to ${hostname}..\n";
      nntp_open $hostname;

      for(my $i = 0; $i < @NGRPS; ++$i){
         my $gr = $NGRPS[$i];

         next unless $gr->[0] =~ /^$name\./;

         if($gr->[3] < 0){
            print STDERR ". Query $gr->[0] .. "
         }else{
            print STDERR ". Update $gr->[0] #$gr->[3] ($gr->[1]/$gr->[2]) .. "
         }

         my ($f, $t) = nntp_group($gr->[0]);
         if(!defined $f){
            print STDERR "GROUP INACCESSABLE, skipping entry\n";
            next;
         }
         print STDERR "$f/$t\n";
         ($gr->[1], $gr->[2]) = ($f, $t);

         if(!defined $gr->[3] || $gr->[3] < 0 || $gr->[3] > $t){
            $gr->[3] = $t;
            $RCFILE_SAVE = 1
         }else{
            my $j = 0;
            while($gr->[3] < $t){
               ++$gr->[3];
               $RCFILE_SAVE = 1;
               if($j++ == 0){
                  print STDERR "   $gr->[3]"
               }elsif ($j % 8 == 0){
                  print STDERR "\n   $gr->[3]"
               }else{
                  print STDERR " $gr->[3]";
               }
               last unless
                  nntp_article(($UPDATE > 0 ? *MBOX : *STDOUT),
                     $gr->[0], $gr->[3])
            }
            print STDERR "\n" if $j > 0
         }
      }

      nntp_close;
   }

   if($UPDATE > 0){
      close MBOX or die $^E
   }
}

END{
   rcfile_save
}

main;
exit 0;
# s-it-mode
