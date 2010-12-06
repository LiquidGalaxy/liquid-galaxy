#!/usr/bin/perl -w
# Copyright 2010 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# GoogleEarth ViewSync packet relayer & tweaker
#
# 20101019 Andrew Leahy a.leahy@uws.edu.au alfski@gmail.com
#
# FEATURES:
# - Listens on port and dumps packets to screen, just "viewsyncrelay.pl -listen"
#
# - Can relay packets to UDP directed or UDP broadcast or UDP multicast group.
# 
# - If the ViewSync counter is reset, and the IP address of whoever is sending
#   ViewSync packets hasn't changed, then this relay will automatically take over
#   the counting. ie. you can restart the ViewMaster and not have to restart clients.
#
# REQUIREMENTS: Depending on your system you may need to install the Perl
# module IO::Socket::Multicast from CPAN, may also require IO::Interface to
# build (or just comment out the mutlicast stuff).
#
# TODO: lot's of clean up, this is like version 0.00001! built with head full
# of flu.  recving from multicast src, recving from multiple masters, sending
# to multiple destinations detect local broadcast nets and use them to simplify
# cli args.
# 
#
# Accepted commandline arguments:
#
# -inport=PORT (udp port to listen on)
# -verbose/-noverbose (print messages to screen or not)
# -listen (just listen and dump packets to screen, forces -verbose)
# -udpout=IPADDRESS:PORT (where to send packets)
# -broadcast (needed if sending UDP to local broadcast address)
# -multicastdst=MULTICASTGROUP:PORT (where to send multicast packets to)
# -ttl=NUM (set multicast TTL value)
#

use strict;
use IO::Socket;
use IO::Socket::Multicast;
use Getopt::Long;

my $IN_PORT = 21568;
my $UDP_OUT = '10.42.42.255:21567';
my $OUT_PORT = 21567;
my $MULTICAST_OUT = 0;
my $BROADCAST = 0;
my $DIRECTED = 1;
my $MCAST_TTL = 1;
#my $MCAST_OUT_IF = 'eth0';
my $MCAST_DEST = '239.255.1.1:21567';
my $MULTICAST_IN = 0;
my $MCAST_IN_GROUP = '239.255.2.2';
my $MAXLEN = 256;
my $JUST_LISTEN = 0;
my $VERBOSE = 0;

# media variables
my $MEDIAPATH = '/home/lg/media/videos';
my $MEDIAFILE = 'flight';

GetOptions('inport=i' => \$IN_PORT, 'verbose!' => \$VERBOSE, 'listen!' => \$JUST_LISTEN,
	'udp_out=s' => \$UDP_OUT, 'broadcast!' => \$BROADCAST,
	'ttl=i' => \$MCAST_TTL, 'multicastdest=s' => \$MCAST_DEST, 'multicastsrc=s' => \$MCAST_IN_GROUP );

my ($UDP_OUT_HOST, $UDP_OUT_PORT) = split(':', $UDP_OUT);

my ($recv, $send);

if ($JUST_LISTEN) { $VERBOSE = 1; };

if ($MULTICAST_IN) {
 $recv = IO::Socket::Multicast->new( LocalPort => $IN_PORT, Proto => 'udp') or die "recv mcast socket: $@";
 $recv->mcast_add($MCAST_IN_GROUP) or die "Couldn't set multicast group: $!\n";
} else {
 $recv = IO::Socket::INET->new( LocalPort => $IN_PORT, Proto => 'udp') or die "recv socket: $@";
}

print "Listening for UDP ViewSync messages on port $IN_PORT\n" if $VERBOSE;

if (!$JUST_LISTEN) {
 if ($MULTICAST_OUT) {
  $send = IO::Socket::Multicast->new( PeerAddr=> $MCAST_DEST, Proto=>'udp') or die "creating (multicast) socket: $@";
  $send->mcast_ttl($MCAST_TTL);
  print "Sending ViewSync messages to $MCAST_DEST (udp multicast ttl=$MCAST_TTL)\n" if $VERBOSE;
 } elsif ($BROADCAST or $DIRECTED) {
  $send = IO::Socket::INET->new( PeerAddr=> $UDP_OUT_HOST, PeerPort => $UDP_OUT_PORT, Proto => 'udp', Broadcast => $BROADCAST) or die "creating udp socket: $@";
  print "Sending ViewSync messages to $UDP_OUT (udp " if $VERBOSE;
  print "broadcast)\n" if $VERBOSE && $BROADCAST;
  print "directed)\n" if $VERBOSE && $DIRECTED;
 } else {
  print "No packet transmit mode?\n";
  exit(0);
 }
}

my ($recv_msg, $send_msg, $viewmaster_inet, $viewmaster_port);
my $View_Counter = -1; my $i_am_counter = 0;

while ($recv->recv($recv_msg, $MAXLEN)) {

#my($port, $ipaddr) = sockaddr_in($sock->peername);
#$hishost = gethostbyaddr($ipaddr, AF_INET);
#$ip = inet_ntoa($ipaddr);
#print "Client $ip sent $len bytes '$recv_msg'\n";
#print "$recv_msg\n" if $VERBOSE;

 if (!$viewmaster_inet) {
  ($viewmaster_port, $viewmaster_inet) = sockaddr_in($recv->peername);
  print "Found View Master on " . inet_ntoa($viewmaster_inet) . "\n" if $VERBOSE;
 }
 
 if ($JUST_LISTEN) {
	print "$recv_msg\n" if $VERBOSE;
 } else {
  my @viewsync = split(',', $recv_msg);
  my $mpaudioload = '';
  my $mpvideoload = '';
  my $detectmode  = '';

# in $viewsync[x] ....
# 0=counter, 1=lat, 2=long, 3=alt, 4=heading, 5=tilt, 6=roll, 7=time start, 8=time end, 9=planet

  if (!$i_am_counter) {
   if ($viewsync[0] > $View_Counter) { 
    $View_Counter = $viewsync[0];
   } else { # do we take control?
    print "View Counter has not increased. internal counter=$View_Counter, recvd view_counter=$viewsync[0]\n" if $VERBOSE;
    # has viewmaster host changed?
    my ($new_viewmaster_port, $new_viewmaster_inet) = sockaddr_in($recv->peername);
    if ($new_viewmaster_inet eq $viewmaster_inet) {
     print "View Master IP address is same as old, taking control of View Counter.\n" if $VERBOSE;
     $i_am_counter = 1;
    } else {
     print "View Master IP address has changed from ". inet_ntoa($viewmaster_inet) ." to ". inet_ntoa($new_viewmaster_inet) . "\n";
     print "Exiting.\n";
     exit(0);
    }
   }
  }

# example for altitude-based audio
  my $altval = int($viewsync[3]);
  # space at 50,000 meters. flight from 0 to 50,000 meters. ocean below 0 meters.
  if (($altval > 80000) && ($mpaudioload ne 'space')) {
    $mpaudioload = 'space';
  } elsif (($altval < 80000) && ($altval > 0) && ($mpaudioload ne 'flight')) {
    $mpaudioload = 'flight';
  } elsif (($altval <= 0) && ($mpaudioload ne 'ocean')) {
    $mpaudioload = 'ocean';
  }

# example for lat-long-based video
  my $latval  = sprintf("%.6g", $viewsync[1]);
  my $longval = sprintf("%.6g", $viewsync[2]);
  if (($latval eq 41.8885) && ($longval eq 12.4893)) {
    $mpvideoload = '1080playlist';
    $detectmode = 'location';
  } else {
#    print "latval = \"" . $latval . "\" longval = \"" . $longval . "\"\n";
    $detectmode = 'altitude';
  }

# execute for above examples
  if (($detectmode eq 'altitude') && ($mpaudioload ne $MEDIAFILE)) {
    print "loading audio playlist \"" . $MEDIAPATH . "/" . $mpaudioload . "\"\n";
    system("/home/lg/bin/lg-run-bg /home/lg/bin/fadeswitch audio $MEDIAPATH/$mpaudioload &");
    $MEDIAFILE = $mpaudioload;
  } elsif (($detectmode eq 'location') && ($mpvideoload ne $MEDIAFILE)) {
    print "loading video playlist \"" . $MEDIAPATH . "/" . $mpvideoload . "\"\n";
    system("/home/lg/bin/lg-run-bg /home/lg/bin/fadeswitch video $MEDIAPATH/$mpvideoload &");
    $MEDIAFILE = $mpvideoload;
  }

  if ($i_am_counter) { $viewsync[0] = ++$View_Counter; } # increment and overwrite counter

  #$viewsync[3] -= 70; # subtract 70m from view altitude
  #if ($viewsync[3] > 350000) { $viewsync[3] = 350000; } # limit altitude to 350km

  $send_msg = join(',', @viewsync) . ',';
  print "$send_msg\n" if $VERBOSE;
  $send->send($send_msg) or die "Socket send failed: $!";
 } # !$JUST_LISTEN

} 
die "$0: $!";
