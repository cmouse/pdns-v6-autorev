#!/usr/bin/perl

## (C) Aki Tuomi 2013
## This code is distributed with same license as
## PowerDNS Authoritative Server.

## You are not supposed to edit this script, please
## see README.md for configuration information.

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
### Original code at http://search.cpan.org/~miyagawa/Convert-Base32/

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


### Code for the RemoteBackendHandler

## CTOR for Handler
sub new {
  my $class = shift;
  my $self = {};

  # Create a JSON encoder/decoder object
  $self->{_j} = JSON::Any->new;
  
  # initialize default values
  $self->{_result} = $self->{_j}->false;
  $self->{_log} = [];
  $self->{_prefix} = 'node';

  bless $self, $class;
  return $self;
}

## Main loop for code
sub run {
   my $self = shift;

   while(<>) {
      chomp;
#      print STDERR "$_\n";
      next if $_ eq '';

      # Try to read and decode a json query 
      my $req = $self->{_j}->decode($_);
      # let's see what we got
      if (!defined $req->{method} && !defined $req->{parameters}) {
          die "Invalid request received from upstream";
      }

      # convert method to name and call it with parameters
      my $meth = "do_" . lc($req->{method});

      if ($self->can($meth)) {
        if ($self->{_dsn}) {
          # Use cached connections to avoid problems
          $self->{_d} = DBI->connect_cached($self->{_dsn}, $self->{_username}, $self->{_password}) or die;
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

## Add a line into log
sub log {
   my $self = shift;
   push @{$self->{_log}}, shift;
}

## Set return value to 'true', optionally log
sub success {
   my $self = shift;
   $self->{_result} = $self->{_j}->true;
   my $l = shift;
   $self->log($l) if ($l);
}

## Set result to result, optionally log
sub result {
   my $self = shift;
   my $res = shift;
   $self->{_result} = $res;
   my $l = shift;
   $self->log($l) if ($l);
}

## Set result to 'false', optionally log
sub error {
   my $self = shift;
   $self->{_result} = $self->{_j}->false;
   my $l = shift;
   $self->log($l) if ($l);
}

## Add rr into result rr(name,type,content,prio,ttl)
sub rr {
   my $self = shift;
   my $d_id = shift;
   my $name = shift;
   my $type = shift;
   my $content = shift;

   # set defaults if nothing found
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

## Return database connection
sub d {
   my $self = shift;
   return $self->{_d};
}

## Lookup domain's id and partner id.
sub domain_ids {
   my $self = shift;
   my $name = shift;
   my $d = $self->d;

   # Try to lookup domain id for the name, break once found. 
   # To avoid stealing parent domain, we need to stop once
   # a domain id has been found.
   while($name) {

      my $stmt = $d->prepare("SELECT domains.id FROM domains WHERE name = ?");
      my $ret = $stmt->execute(($name));
      my ($d_id) = $stmt->fetchrow;
      
      if ($d_id) {
        $stmt = $d->prepare("SELECT content FROM domainmetadata WHERE domain_id = ? AND kind = ?");
        $stmt->execute(($d_id, 'AUTODNS'));
        my ($p_id) = $stmt->fetchrow;

        # if p_id is NULL we won't handle the domain
        return ($d_id,$p_id);
      }

      # get next
      ($name) = ($name=~m/^[^.]*\.(.*)$/);
   }

   return 0;
}

## initializes the backend 
sub do_initialize {
   my $self = shift;
   my $p = shift;

   if (!defined $p->{dsn}) {
      $self->error("Missing DSN in parameters!");
      return;
   }

   # setup values where found
   $self->{_dsn} = $p->{dsn};
   $self->{_username} = $p->{username};
   $self->{_password} = $p->{password};
   $self->{_prefix} = $p->{prefix} if ($p->{prefix});

   # test connection, leave it open for further use. 
   my $d = DBI->connect_cached($self->{_dsn}, $self->{_username}, $self->{_password}) or die;

   $self->success("Autoreverse backend initialized");
}

## lookup method 
sub do_lookup {
   my $self = shift;
   my $p = shift;
   my $name = $p->{qname};
   my $type = $p->{qtype};
   my $d = $self->d;
   my $stmt;
   my $ret;

   my ($d_id, $d_id_2) = $self->domain_ids($name);

   ## Domain wasn't found from our database. 
   if (!$d_id) {
     $self->error("not our domain");
     return;
   }

   # Domain has no partner
   if (!$d_id_2) {
     $self->error("missing mapping");
     return;
   }

   # Lookup possible overrides from database
   if ($type eq 'ANY') {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ?');
     $ret = $stmt->execute(($name));
   } else {
     $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ? AND type = ?');
     $ret = $stmt->execute(($name,$type));
   }

   # SQLite3 doesn't know how to tell us number of rows so we just give it a go
   while((my ($d_id,$name,$type,$content,$prio,$ttl,$auth) = $stmt->fetchrow)) {
       $self->rr($d_id,$name,$type,$content,$prio,$ttl,$auth);
   }

   # And if there was no result, we try synthetize one
   unless (ref $self->{_result} eq 'ARRAY') {

      # need to fetch SOA name
      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->bind_param(1, $d_id, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "SOA");
      $stmt->execute;
      my ($dom) = $stmt->fetchrow;

      # we also need partner's domain
      $stmt = $d->prepare('SELECT name FROM records WHERE domain_id = ? AND type = ?');
      $stmt->bind_param(1, $d_id_2, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "SOA");
      $stmt->execute;
      my ($dom2) = $stmt->fetchrow;

      # both are really required
      unless($dom and $dom2) {
          $self->error("Missing SOA record for domain");
          return;
      }

      # do not answer to non-supported queries
      if ($type ne 'ANY' and $type ne 'PTR' and $type ne 'AAAA') {
         $self->error;
         return;
      }

      # check for custom prefix
      $stmt = $d->prepare('SELECT content FROM domainmetadata WHERE domain_id = ? AND kind = ?');
      $stmt->bind_param(1, $d_id, DBI::SQL_INTEGER);
      $stmt->bind_param(2, "AUTOPRE");
      $stmt->execute;

      # use default prefix if none found
      my ($prefix) = $stmt->fetchrow || $self->{_prefix};

      # parse request. reverse first
      if ($dom =~/ip6.arpa$/ && $name=~/(.*)\.\Q$dom\E$/) {

           # this converts 2.8.a.8.c.c.d.4.2.a.1.6.6.7.4.1.0.0.0.0.2.c.1.0.8.e.6.0.1.0.0.2.ip6.arpa into
           # 147661a24dcc8a82 and base32 encodes the bytes. 
           # assuming 0.0.0.0.2.c.1.0.8.e.6.0.1.0.0.2.ip6.arpa is your domain. 

           my $tmp = $1;
           $tmp = join '', reverse split(/\./, $tmp);
           $tmp=~s/^0*//g;
           $tmp = '00' if $tmp eq '';

           # encode $tmp, what if it's uneven? then pad with 0
           $tmp = "0${tmp}" if (length($tmp)%2);

           # perform the base32 encoding on bytes. 
           $tmp = pack('H*',$tmp);
           $tmp = encode_base32($tmp);
 
           # add a result record
           $self->rr($d_id,$name, "PTR", "$prefix-$tmp.$dom2",0,60,1);
           return;
      }

      # well, maybe forward then?
      if ($name=~/\Q$prefix\E-([ybndrfg8ejkmcpqxot1uwisza345h769]+)\.\Q$dom\E$/) {

           # this converts nt5gde1p31fer into 147661a24dcc8a82
           # and then adds domain to it ending up into
           # 2001:6e8:1c2:0:1476:61a2:4dcc:8a82

           my $tmp = $1;

           # prepare domain name
           my $revdom = join '', reverse split /\./, $dom2;
           $revdom =~s/arpaip6//; # we need to remove this

           # decode $tmp, if possible.
           eval '$tmp = decode_base32($tmp);';
           if ($@) {
               $self->error($@);
               return;
           }

           # unpack into hex 
           $tmp = join '', unpack('H*', $tmp);

           # add zeroes until we have a full length value
           while(length($tmp) + length($revdom) < 32) {
              $tmp = "0${tmp}";
           }

           # fix oversized records into 32 bytes. 
           $tmp = substr($tmp,0,32-length($revdom)) if (length($tmp) + length($revdom) > 32);

           # add domain to value
           $tmp = "$revdom$tmp";

           # add few : into the value to turn it into IPv6 address notation
           $tmp =~s/(.{4})/$1:/g;        
           # remove stray : at the end
           chop $tmp;

           # add a result record
           $self->rr($d_id,$name,"AAAA",$tmp,0,60,1);
           return;
      }

      $self->error;
   }
}


# addDomainKey method call 
sub do_adddomainkey {
   my $self = shift;
   my $p = shift;

   my $key = $p->{key};
   my $name = $p->{name};

   my $d = $self->d;
   my $stmt = $d->prepare('INSERT INTO cryptokeys (domain_id,flags,active,content) SELECT id,?,?,? FROM domains WHERE name = ?');

   $stmt->execute(($key->{flags}, $key->{active}, $key->{content}, $name));

   my $kid = $d->last_insert_id("","","","");

   # get the inserted record ID and return it
   $self->{_result} = int($kid);
}

# getDomainKeys method call
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

   # no keys found?
   $self->error unless (@{$self->{_result}});
}

# setDomainMetaData method call
sub do_setdomainmetadata {
   my $self = shift;
   my $p = shift;

   my $d = $self->d;
 
   # clear any existing values
   my $stmt = $d->prepare("DELETE FROM domainmetadata WHERE domain_id=(SELECT id FROM domains WHERE name = ?) and domainmetadata.kind = ?"); 
   $stmt->execute(($p->{name}, $p->{kind}));

   # add replacement values 
   $stmt = $d->prepare('INSERT INTO domainmetadata (domain_id,kind,content) SELECT id,?,? FROM domains WHERE name = ?');

   # there can be multiple values. or none. 
   for my $val (@{$p->{value}}) {
      $stmt->execute(($p->{kind},$val,$p->{name}));
   }

   # it always succeeds
   $self->success;
}

# getDomainMetaData method call 
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

## Start the script and run handler

$|=1;
my $handler = RemoteBackendHandler->new;

$handler->run;
