#!/usr/bin/perl

## (C) Aki Tuomi 2013
## This code is distributed with same license as
## PowerDNS Authoritative Server.

package RemoteBackendHandler;
use strict;
use warnings;
use 5.005;
use DBI;
use JSON::Any;
use Data::Dumper;
use Carp ();

### This software uses Base32 code from
### Tatsuhiko Miyagawa <miyagawa@bulknews.net>
### It has been modified to use z-base32 charset

my @syms = split //, 'ybndrfg8ejkmcpqxot1uwisza345h769';

my %bits2char;
my @char2bits;

for (0..$#syms) {
    my $sym = $syms[$_];
    my $bin = sprintf('%05b', $_);

    $char2bits[ ord lc $sym ] = $bin;
    $char2bits[ ord uc $sym ] = $bin;

    do {
        $bits2char{$bin} = $sym;
    } while $bin =~ s/(.+)0\z/$1/s;
}


sub encode_base32_pre58($) {
    length($_[0]) == bytes::length($_[0])
        or Carp::croak('Data contains non-bytes');

    my $str = unpack('B*', $_[0]);

    if (length($str) < 8*1024) {
        return join '', @bits2char{ $str =~ /.{1,5}/g };
    } else {
        # Slower, but uses less memory
        $str =~ s/(.{5})/$bits2char{$1}/sg;
        return $str;
    }
}


sub encode_base32_perl58($) {
    $_[0] =~ tr/\x00-\xFF//c
        and Carp::croak('Data contains non-bytes');

    my $str = unpack('B*', $_[0]);

    if (length($str) < 8*1024) {
        return join '', @bits2char{ unpack '(a5)*', $str };
    } else {
        # Slower, but uses less memory
        $str =~ s/(.{5})/$bits2char{$1}/sg;
        return $str;
    }
}


sub decode_base32_pre58($) {
    ( length($_[0]) != bytes::length($_[0]) || $_[0] =~ tr/ybndrfg8ejkmcpqxot1uwisza345h769//c )
        and Carp::croak('Data contains non-base32 characters');

    my $str;
    if (length($_[0]) < 8*1024) {
        $str = join '', @char2bits[ unpack 'C*', $_[0] ];
    } else {
        # Slower, but uses less memory
        ($str = $_[0]) =~ s/(.)/$char2bits[ord($1)]/sg;
    }

    my $padding = length($str) % 8;
    $padding < 5
        or Carp::croak('Length of data invalid');
    $str =~ s/0{$padding}\z//
        or Carp::croak('Padding bits at the end of output buffer are not all zero');

    return pack('B*', $str);
}


sub decode_base32_perl58($) {
    $_[0] =~ tr/ybndrfg8ejkmcpqxot1uwisza345h769//c
        and Carp::croak('Data contains non-base32 characters');

    my $str;
    if (length($_[0]) < 8*1024) {
        $str = join '', @char2bits[ unpack 'C*', $_[0] ];
    } else {
        # Slower, but uses less memory
        ($str = $_[0]) =~ s/(.)/$char2bits[ord($1)]/sg;
    }

    my $padding = length($str) % 8;
    $padding < 5
        or Carp::croak('Length of data invalid');
    $str =~ s/0{$padding}\z//
        or Carp::croak('Padding bits at the end of output buffer are not all zero');

    return pack('B*', $str);
}


if ($] lt '5.800000') {
    require bytes;
    *encode_base32 = \&encode_base32_pre58;
    *decode_base32 = \&decode_base32_pre58;
} else {
    *encode_base32 = \&encode_base32_perl58;
    *decode_base32 = \&decode_base32_perl58;
}

## CTOR for Handler
sub new {
  my $class = shift;
  my $self = {};

  $self->{_j} = JSON::Any->new;
  $self->{_result} = $self->{_j}->false;
  $self->{_log} = [];
  $self->{_prefix} = 'node';

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
        # unsupported request
        $self->error;
      }

      # return result
      my $ret = { result => $self->{_result}, log => $self->{_log} };
      #print STDERR $self->{_j}->encode($ret),"\r\n";
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
      my $ret = $stmt->execute(($name, 'AUTODNS'));
      my @val = $stmt->fetchrow;
      return @val if (@val);

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

   $self->{_prefix} = $p->{prefix} if ($p->{prefix});

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
   my $ret;

   my ($d_id, $d_id_2) = $self->domain_ids($name);

   if (!$d_id) {
     $self->error("not our domain");
     return;
   }

   if (!$d_id_2) {
     $self->error("missing mapping");
     return;
   }

   if ($type eq 'ANY') {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ?');
     $ret = $stmt->execute(($name));
   } else {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ? AND type = ?');
     $ret = $stmt->execute(($name,$type));
   }

   while((my ($d_id,$name,$type,$content,$prio,$ttl,$auth) = $stmt->fetchrow)) {
       $self->rr($d_id,$name,$type,$content,$prio,$ttl,$auth);
   }
   unless (ref $self->{_result} eq 'ARRAY') {
      # need to fetch SOA name
      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->bind_param(1, $d_id, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "SOA");
      $stmt->execute;
      # now we know the SOA name, so we can produce the actual beef
      my ($dom) = $stmt->fetchrow;

      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->bind_param(1, $d_id_2, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "SOA");
      $stmt->execute;
      my ($dom2) = $stmt->fetchrow;

      unless($dom and $dom2) {
          $self->error("Missing SOA record for domain");
          return;
      }

      if ($type ne 'ANY' and $type ne 'PTR' and $type ne 'AAAA') {
         $self->error;
         return;
      }

      # check for custom prefix
      $stmt = $d->prepare('SELECT content FROM domainmetadata WHERE domain_id = ? AND kind = ?');
      $stmt->bind_param(1, $d_id, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "AUTOPRE");
      $stmt->execute;

      my ($prefix) = $stmt->fetchrow || $self->{_prefix};

      # parse request. reverse first
      if ($dom =~/ip6.arpa$/ && $name=~/(.*)\.\Q$dom\E$/) {
           my $tmp = $1;
           $tmp = join '', reverse split(/\./, $tmp);
           $tmp=~s/^0*//g;
           $tmp = '00' if $tmp eq '';
           # encode $tmp, what if it's uneven? then pad with 0
           $tmp = "${tmp}0" if (length($tmp)%2);
           $tmp = pack('H*',$tmp);
           $tmp = encode_base32($tmp);
           $self->rr($d_id,$name, "PTR", "$prefix-$tmp.$dom2",0,60,1);
           return;
      }

      # well, maybe forward then?
      if ($name=~/\Q$prefix\E-([ybndrfg8ejkmcpqxot1uwisza345h769]+)\.\Q$dom\E$/) {
           my $tmp = $1;
           my $revdom = join '', reverse split /\./, $dom2;
           $revdom =~s/arpaip6//;
           # decode $tmp
           eval '$tmp = decode_base32($tmp);';
           if ($@) {
               $self->error($@);
               return;
           }
           $tmp = join '', unpack('H*', $tmp);
           # make sure it turns out to be a proper value
           if ($tmp=~tr/a-f0-9//c) {
              $self->error("not valid record");
              return;
          }
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

sub do_adddomainkey {
   my $self = shift;
   my $p = shift;

   my $key = $p->{key};
   my $name = $p->{name};

   my $d = $self->d;
   my $stmt = $d->prepare('INSERT INTO cryptokeys (domain_id,flags,active,content) SELECT id,?,?,? FROM domains WHERE name = ?');

   $stmt->execute(($key->{flags}, $key->{active}, $key->{content}, $name));

   my $kid = $d->last_insert_id("","","","");

   $self->{_result} = int($kid);
}

sub do_getdomainkeys {
   my $self = shift;
   my $p = shift;

   my $d = $self->d;
   my $stmt = $d->prepare('SELECT cryptokeys.id,flags,active,content FROM cryptokeys JOIN domains ON cryptokeys.domain_id = domains.id WHERE name = ?');
   $stmt->execute(($p->{name}));

   $self->{_result} = [];
   while((my ($id,$flags,$active,$content) = $stmt->fetchrow)) {
      if ($active) {
        $active = $self->{_j}->true;
      } else {
        $active = $self->{_j}->false;
      }
      push @{$self->{_result}}, { id => int($id), flags => int($flags), active => $active, content => $content };
   }

   $self->error unless (@{$self->{_result}});
}

sub do_setdomainmetadata {
   my $self = shift;
   my $p = shift;

   my $d = $self->d;
   my $stmt = $d->prepare('INSERT INTO domainmetadata (domain_id,kind,content) SELECT id,?,? FROM domains WHERE name = ?');

   for my $val (@{$p->{value}}) {
      $stmt->execute(($p->{kind},$val,$p->{name}));
   }

   $self->success;
}

sub do_getdomainmetadata {
   my $self = shift;
   my $p = shift;

   my $name = $p->{name};
   my $kind = $p->{kind};

   my $d = $self->d;

   my $stmt = $d->prepare('SELECT content FROM domainmetadata JOIN domains ON domainmetadata.domain_id = domains.id WHERE domains.name = ? AND kind = ?');
   $stmt->execute(($name,$kind));

   $self->{_result} = [];
   while((my ($val) = $stmt->fetchrow)) {
     $self->{_result} = [];
     push @{$self->{_result}},$val;
   }

   $self->error unless (@{$self->{_result}});
}

package main;
use strict;
use warnings;
use 5.005;

$|=1;
my $handler = RemoteBackendHandler->new;

$handler->run;
