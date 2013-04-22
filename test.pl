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

  print $j->encode({method => $meth, parameters => \%p}),"\r\n";
  print $out $j->encode({method => $meth, parameters => \%p}),"\r\n";
  my $res = <$in>;
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

rpc 'lookup', qname => 'dyn.powerdns.com', qtype => 'SOA';
rpc 'lookup', qname => "$prefix-yy.dyn.powerdns.com", qtype => 'ANY';
rpc 'lookup', qname => '6.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.6.0.1.0.0.2.ip6.arpa', qtype => 'ANY';
rpc 'lookup', "qtype"=>"SOA","qname"=>"$prefix-gr5y.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-na.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-nynynynynynynyy.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;
rpc 'lookup', "qtype"=>"ANY","qname"=>"$prefix-nt5gde1p31fernt5gde1p31fer.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1;

}
