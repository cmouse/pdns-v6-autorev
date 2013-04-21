use strict;
use warnings;
use 5.005;
use IPC::Open2;
use JSON::Any;
use Data::Dumper;

my $u = "pdnstest";
my $pw = "wWTJ3tbS6L3f9Lsh";
my $db = "pdns_test";
my $dsn = "DBI:mysql:$db";

$|=1;
my $in;
my $out;
my $pid = open2($in,$out,"./rev.pl");

my $j = JSON::Any->new;

sub rpc {
  my $meth = shift;
  my $p = shift;

  print $out $j->encode({method => $meth, parameters => $p}),"\r\n";
  my $res = <$in>;
  chomp $res;
  print $res,"\n";
}

rpc 'initialize', {dsn => $dsn, username => $u, password => $pw};
rpc 'lookup', {qname => 'dyn.powerdns.com', qtype => 'SOA'};
rpc 'lookup', {qname => 'node-yy.dyn.powerdns.com', qtype => 'ANY'};
rpc 'lookup', {qname => '6.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.6.0.1.0.0.2.ip6.arpa', qtype => 'ANY'};
rpc 'lookup', {"qtype"=>"SOA","qname"=>"node-gr5y.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1};
rpc 'lookup', {"qtype"=>"ANY","qname"=>"node-na.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1};
rpc 'lookup', {"qtype"=>"ANY","qname"=>"node-nynynynynynynyy.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1};
rpc 'lookup', {"qtype"=>"ANY","qname"=>"node-nt5gde1p31fernt5gde1p31fer.dyn.powerdns.com","remote"=>"127.0.0.1","local"=>"127.0.0.1","real-remote"=>"127.0.0.1/32","zone-id"=>-1};

