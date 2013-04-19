#!/usr/bin/perl
package RemoteBackendHandler;
use strict;
use warnings;
use 5.005;
use DBI;
use JSON::Any;
use Data::Dumper;

## CTOR for Handler
sub new {
  my $class = shift;
  my $self = {};

  $self->{_j} = JSON::Any->new;
  $self->{_result} = $self->{_j}->false;
  $self->{_log} = [];

  bless $self, $class;
  return $self;
}

sub run {
   my $self = shift;

   while(<>) {
      chomp;
#      print STDERR "$_\n";
      next if $_ eq '';
      my $req = $self->{_j}->decode($_);
      # let's see what we got
      if (!defined $req->{method} && !defined $req->{parameters}) {
          die "Invalid request received from upstream";
      }
      # convert method to name and call it with parameters
      my $meth = "do_" . lc($req->{method});
      if ($self->can($meth)) {
        if ($self->{_dsn}) {
          $self->{_d} = DBI->connect($self->{_dsn}, $self->{_username}, $self->{_password});
        }
        #print STDERR Dumper($req->{parameters});
        $self->$meth($req->{parameters});	
      } else {
        $self->error("Method $meth missing");
      }

      # return result
      my $ret = { result => $self->{_result}, log => $self->{_log} };
      print $self->{_j}->encode($ret),"\r\n";

      $self->{_result} = $self->{_j}->false;
      $self->{_log} = [];
   }
}

sub log {
   my $self = shift;
   push @{$self->{_log}}, shift;
}

sub success {
   my $self = shift;
   $self->{_result} = $self->{_j}->true;
   my $l = shift;
   push @{$self->{_log}}, $l if ($l);
}

sub result {
   my $self = shift;
   my $res = shift;
   $self->{_result} = $res;
   my $l = shift;
   push @{$self->{_log}}, $l if ($l);
}

sub error {
   my $self = shift;
   $self->{_result} = $self->{_j}->false;
   my $l = shift;
   push @{$self->{_log}}, $l if ($l);
}

## rr(name,type,content,prio,ttl)
sub rr {
   my $self = shift;
   my $d_id = shift;
   my $name = shift;
   my $type = shift;
   my $content = shift;
   my $prio = shift || 0;
   my $ttl = shift || 60;
   my $auth = shift || 1;

   $self->{_result} = [] if (ref $self->{_result} ne 'ARRAY');

   push @{$self->{_result}}, { 
      'qname' => $name, 
      'qtype' => $type, 
      'content' => $content, 
      'priority' => int($prio),
      'ttl' => int($ttl),
      'auth' => int($auth),
      'domain_id' => int($d_id)
   };
}

sub d {
   my $self = shift;
   return $self->{_d};
}

sub domain_ids {
   my $self = shift;
   my $name = shift;
   my $d = $self->d;
   
   while($name) { 
      my $stmt = $d->prepare("SELECT domains.id,content FROM domains JOIN domainmetadata ON domains.id = domainmetadata.domain_id WHERE name = ? AND kind = ?");
      $stmt->execute(($name, 'AUTODNS'));

      if ($stmt->rows) {
         return $stmt->fetchrow;
      }
      # get next
      ($name) = ($name=~m/^[^.]*\.(.*)$/);
   }

   return 0;
}

sub do_initialize {
   my $self = shift;
   my $p = shift;
 
   if (!defined $p->{dsn}) {
      $self->error("Missing DSN in parameters!");
      return;
   }

   $self->{_dsn} = $p->{dsn};
   $self->{_username} = $p->{username};
   $self->{_password} = $p->{password};

   # test connection
   my $d = DBI->connect($self->{_dsn}, $self->{_username}, $self->{_password});
   $d->disconnect;

   $self->success("Autoreverse backend initialized");
}

sub do_lookup {
   my $self = shift;
   my $p = shift;
   my $name = $p->{qname};
   my $type = $p->{qtype};
   my $d = $self->d;
   my $stmt;

   my ($d_id, $d_id_2) = $self->domain_ids($name);

   if (!$d_id || !$d_id_2) {
     $self->error("not our domain");
     return;
   }

   if ($type eq 'ANY') {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ?');
     $stmt->execute(($name));
   } else {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ? AND type = ?');
     $stmt->execute(($name,$type));
   }

   if ($stmt->rows) {
      while((my ($d_id,$name,$type,$content,$prio,$ttl,$auth)) = $stmt->fetchrow) {
         $self->rr($d_id,$name,$type,$content,$prio,$ttl,$auth);
      }
   } else {
      # need to fetch SOA name
      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->execute(($d_id,'SOA'));
      # now we know the SOA name, so we can produce the actual beef
      my ($dom) = $stmt->fetchrow;

      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->execute(($d_id_2,'SOA'));
      my ($dom2) = $stmt->fetchrow;
    
      unless($dom and $dom2) {
          $self->error("Missing SOA record for domain");
          return;
      }
    
      if ($type ne 'ANY' and $type ne 'PTR' and $type ne 'AAAA') {
         $self->error;
         return;
      }

      # parse request. reverse first
      if ($dom =~/ip6.arpa$/ && $name=~/(.*)\.\Q$dom\E$/) {
           my $tmp = $1;
           $tmp = join '', reverse split(/\./, $tmp);
           $tmp=~s/^0*//g;
           $tmp = '0' if $tmp eq '';
           $self->rr($d_id,$name, "PTR", "node-$tmp.$dom2",0,60,1);
           return;
      }

      # well, maybe forward then? 
      if ($name=~/node-([^.]*)\.\Q$dom\E$/) {
           my $tmp = $1;
           my $revdom = join '', reverse split /\./, $dom2;
           $revdom =~s/arpaip6//;
           $tmp = join '', split(//,$tmp);
           # check for padding
           while(length($tmp) + length($revdom) < 32) {
              $tmp = "0${tmp}";
           }
           $tmp = "$revdom$tmp";
           $tmp =~s/(.{4})/$1:/g;
           chop $tmp;
           $self->rr($d_id,$name,"AAAA",$tmp,0,60,1);
           return;
      }

      $self->error;
   }
}

package main;
use strict;
use warnings;
use 5.005;

$|=1;
my $handler = RemoteBackendHandler->new;

$handler->run;
