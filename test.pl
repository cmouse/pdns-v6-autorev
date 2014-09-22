#!/usr/bin/perl
### This script is intended for testing/developing remotebackend scripts
### To use, please install libjson-any-perl (JSON::Any) and libjson-xs-perl (JSON::XS)
### (c) Aki Tuomi 2013 - Distributed under same license as PowerDNS Authoritative Server
use strict;
use warnings;
use 5.005;
use IPC::Open2;
use JSON::Any;

### CONFIGURATION SECTION

my $prefix = 'node';

## Full path to your remotebackend script
my $script = "/home/cmouse/projects/pdns-v6-autorev/rev.pl";

## These are used to send initialize method before your actual code
my $initparams = { username => "pdnstest", password => "wWTJ3tbS6L3f9Lsh", dsn => "DBI:mysql:pdns_test", prefix => $prefix };

## END CONFIGURATION

$|=1;
my $in;
my $out;
my $pid = open2($in,$out,$script);

my $j = JSON::Any->new;

sub rpc {
  my $meth = shift;
  my %p = @_;

  print "QUERY:\n";
  print $j->encode({method => $meth, parameters => \%p}),"\r\n";
  print $out $j->encode({method => $meth, parameters => \%p}),"\r\n";
  my $res = <$in>;
  print "RESPONSE:\n";
  if ($res) {
    chomp $res;
    print $res,"\n";
  }
}

rpc 'initialize', %$initparams;

if (@ARGV>1) {

## this lets you call whatever method with simple parameters
## like this:

# perl remotebackend-pipe-test.pl lookup qtype SOA qname powerdns.com 

## this will execute 
## {"parameters":{"qname":"powerdns.com","qtype":"SOA"},"method":"lookup"}
## on your remotebackend

my $meth = shift;
rpc $meth, @ARGV;

} else {

## Put whatever you want to run here. Or leave it empty if you
## only want to use the command line

# should succeed
rpc 'lookup', qname => 'dyn.powerdns.com', qtype => 'SOA';
# should return 2001:6e8::
rpc 'lookup', qname => "$prefix-yy.dyn.powerdns.com", qtype => 'ANY';
# should return $prefix-gr5y
rpc 'lookup', qname => '6.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.6.0.1.0.0.2.ip6.arpa', qtype => 'ANY';
# should return 2001:6e8::16
rpc 'lookup', "qtype"=>"SOA","qname"=>"$prefix-gr5y.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
# some things that should work as well
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-ny.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-nynynynynynynyy.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-nt5gd1p31frnt5gd1p31fry.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
# should fail
rpc 'lookup', "qtype"=>"ANY","qname"=>"0.2.a.1.d.2.f.7.e.1.b.a.e.7.8.5.0.0.0.0.0.0.0.0.8.e.6.0.1.0.0.2.ip6.arpa";
rpc 'lookup', "qtype"=>"SOA","qname"=>"test.dyn.powerdns.com";

rpc 'getalldomainmetadata', 'name' => 'dyn.powerdns.com';

#rpc 'adddomainkey', 'name' => 'dyn.powerdns.com', 'key' => { 'flags' => 257, 'active' => 1, 'content' => 'foobar key' }

rpc 'getbeforeandafternamesabsolute', 'qname' => '6 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => 'x 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => '6 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => '6 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0', 'id' => 3;

rpc 'getbeforeandafternamesabsolute', 'qname' => '', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => 'x nines', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => '0 nines', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => '- nines', 'id' => 3;
rpc 'getbeforeandafternamesabsolute', 'qname' => 'nines 0', 'id' => 3;
}
