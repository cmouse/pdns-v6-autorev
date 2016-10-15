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

my @syms = split //, 'ybcdfghjklmnpqrstvwxz1234567890-';

my %bits2char;
my @char2bits;

for (0..$#syms) {
   my $sym = $syms[$_];
   my $bin = sprintf('%05b', $_);

   $char2bits[ ord(lc($sym)) ] = $bin;
   $char2bits[ ord(uc($sym)) ] = $bin;

   do {
       $bits2char{$bin} = $sym;
   } while $bin =~ s/(.+)0\z/$1/s;
}


sub encode_base32_pre58 {
   my $data = shift;
   length($data) == bytes::length($data)
       or Carp::croak('Data contains non-bytes');

   my $str = unpack('B*', $data);

   if (length($str) < 8*1024) {
       return join '', @bits2char{ $str =~ /.{1,5}/g };
   } else {
       # Slower, but uses less memory
       $str =~ s/(.{5})/$bits2char{$1}/sg;
       return $str;
   }
}


sub encode_base32_perl58 {
   my $data = shift;
   $data =~ tr/\x00-\xFF//c
       and Carp::croak('Data contains non-bytes');

   my $str = unpack('B*', $data);

   if (length($str) < 8*1024) {
       return join '', @bits2char{ unpack '(a5)*', $str };
   } else {
       # Slower, but uses less memory
       $str =~ s/(.{5})/$bits2char{$1}/sg;
       return $str;
   }
}


sub decode_base32_pre58 {
   my $data = shift;
   ( length($data) != bytes::length($data) || $data =~ tr/ybcdfghjklmnpqrstvwxz1234567890-//c )
       and Carp::croak('Data contains non-base32 characters');

   my $str;
   if (length($data) < 8*1024) {
       $str = join '', @char2bits[ unpack 'C*', $data ];
   } else {
       # Slower, but uses less memory
       ($str = $data) =~ s/(.)/$char2bits[ord($1)]/sg;
   }

   my $padding = length($str) % 8;
   $padding < 5
       or Carp::croak('Length of data invalid');
   $str =~ s/0{$padding}\z//
       or Carp::croak('Padding bits at the end of output buffer are not all zero');

   return pack('B*', $str);
}


sub decode_base32_perl58 {
   my $data = shift;
   $data =~ tr/ybcdfghjklmnpqrstvwxz1234567890-//c
       and Carp::croak('Data contains non-base32 characters');

   my $str;
   if (length($data) < 8*1024) {
       $str = join '', @char2bits[ unpack 'C*', $data ];
   } else {
       # Slower, but uses less memory
       ($str = $data) =~ s/(.)/$char2bits[ord($1)]/sg;
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
     #print STDERR "$_\n";
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
  return;
}

## Add a line into log
sub rlog {
  my $self = shift;
  push @{$self->{_log}}, shift;
  return;
}

## Set return value to 'true', optionally log
sub success {
  my $self = shift;
  $self->{_result} = $self->{_j}->true;
  my $l = shift;
  $self->rlog($l) if ($l);
  return;
}

## Set result to result, optionally log
sub result {
  my $self = shift;
  my $res = shift;
  $self->{_result} = $res;
  my $l = shift;
  $self->rlog($l) if ($l);
  return;
}

## Set result to 'false', optionally log
sub error {
  my $self = shift;
  $self->{_result} = $self->{_j}->false;
  my $l = shift;
  $self->rlog($l) if ($l);
  return;
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
  return;
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
  return;
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
    $ret = $stmt->execute(($p->{qname}));
  } else {
    $stmt = $d->prepare('SELECT domain_id,name,type,content,prio,ttl,auth FROM records WHERE name = ? AND type = ?');
    $ret = $stmt->execute(($p->{qname},$type));
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

     if ($type eq 'SOA') {
        $self->error;
        return;
     }

     # do not answer to non-supported queries
     if ($type ne 'ANY' and $type ne 'PTR' and $type ne 'AAAA') {
        $self->error("Unsupported qtype");
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
     if ($dom =~/ip6.arpa$/ && $name=~/^([a-fA-F0-9.]+)\.\Q$dom\E$/) {
          # this converts 2.8.a.8.c.c.d.4.2.a.1.6.6.7.4.1.0.0.0.0.2.c.1.0.8.e.6.0.1.0.0.2.ip6.arpa into
          # 147661a24dcc8a82 and base32 encodes the bytes.
          # assuming 0.0.0.0.2.c.1.0.8.e.6.0.1.0.0.2.ip6.arpa is your domain.
          my $tmp = $1;

          # make sure the name complies with rules..
          if ($name!~/^(?:[a-fA-F0-9][.]){32}ip6\.arpa/) {
            $self->error;
            return;
          }

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
     if ($name=~/\Q$prefix\E-([ybcdfghjklmnpqrstvwxz1234567890-]+)\.\Q$dom\E$/) {
          # this converts nt5gde1p31fer into 147661a24dcc8a82
          # and then adds domain to it ending up into
          # 2001:6e8:1c2:0:1476:61a2:4dcc:8a82

          my $tmp = $1;

          # prepare domain name
          my $revdom = join '', reverse split /\./, $dom2;
          $revdom =~s/arpaip6//; # we need to remove this

          # decode $tmp, if possible.
          eval { $tmp = decode_base32($tmp); };
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

     $self->error("Non-matching qname");
  }
  return;
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

  my $kid = $d->last_insert_id("","","cryptokeys","");

  # get the inserted record ID and return it
  $self->{_result} = int($kid);
  return;
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
  return;
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
  return;
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
    push @{$self->{_result}},$val;
  }

  $self->error unless (@{$self->{_result}});
  return;
}

sub do_getalldomainmetadata {
  my $self = shift;
  my $p = shift;

  my $name = $p->{name};
  my $d = $self->d;
  my $stmt = $d->prepare('SELECT kind,content FROM domainmetadata JOIN domains ON domainmetadata.domain_id = domains.id WHERE domains.name = ?');
  $stmt->execute(($name));
  $self->{_result} = {};
  while((my ($kind,$val) = $stmt->fetchrow)) {
    if ($self->{_result}->{$kind}) {
      push @{$self->{_result}->{$kind}},$val;
    } else {
      $self->{_result}->{$kind} = [$val];
    }
  }

  $self->error unless scalar(%{$self->{_result}});
  return;
}

sub incrRevIP {
  my $self = shift;
  my $name = shift;
  my $newname = "";

  while((my $let = chop $name) ne '') {
    if ($let eq " ") {
      $newname = "$let$newname";
    } elsif ($let ne 'f') {
      $let = hex($let)+1;
      $newname = $name . sprintf("%x",$let) . $newname;
      last;
    } else {
      $newname = "0$newname";
    }
  }

  return $newname;
}

sub decrRevIP {
  my $self = shift;
  my $name = shift;
  my $newname = "";

  while((my $let = chop $name) ne '') {
    if ($let eq " ") {
      $newname = "$let$newname";
    } elsif ($let ne '0') {
      $let = hex($let)-1;
      $newname = $name . sprintf("%x",$let) . $newname;
      last;
    } else {
      $newname = "f$newname";
    }
  }

  return $newname;
}

sub isinvalid {
  my $self = shift;
  my $name = shift;
  for my $let (split / /, $name) {
    unless ($let=~/^[0-9a-f]$/i) {
      # problematic.
      return 1;
    }
  }
  return 0;
}

sub getbeforeandafternamesabsolute {
  my $self = shift;
  my $p = shift;

  my $stmt = $self->d->prepare('SELECT name FROM domains WHERE id = ?');
  $stmt->execute(($p->{id}));
  my ($dom) = $stmt->fetchrow;

  unless($dom and $dom=~/ip6\.arpa.?$/) {
    return;
  }

  my $revdom = join ' ', reverse split /\./, $dom;
  $revdom =~s/arpa ip6//; # we need to remove this

  my $dnibbles = length($revdom)/2; # domain bit
  my $nnibbles = 32-$dnibbles;      # name bit
  my $qnibbles = scalar(split(/ /, $p->{qname}));
  my $first = "0 " x $nnibbles;
  my $last = "f " x $nnibbles;

  chop $first;
  chop $last;

  if ($p->{qname} eq "") {
    # empty qname full result
    return ("",$first);
  }

  if ($self->isinvalid($p->{qname})==1 || $dnibbles + $qnibbles > 32) {
    my @qarr = split / /, $p->{qname};
    my $prefix = '';
    my $prev = '';
    my $cur = $p->{qname};
    my $next = '';
    my $i;
    my $plen=0;

    for(my $i=0;$i<scalar(@qarr) && $i<$nnibbles;$i++) {
      my $tmpprefix = join ' ', @qarr[0..$i];
      if ($self->isinvalid($tmpprefix)==0) {
        $prefix = $tmpprefix;
      } else { last; }
    }

    if ($prefix ne "") {
      $plen = length(" $prefix")/2;
      $prefix = "$prefix ";
    };

    $prev = $prefix . ("f " x ($nnibbles-$plen));
    chop $prev;
    $next = $self->incrRevIP($prefix);
    $next = $next . ("0 " x ($nnibbles-$plen));
    # need to generate suitable thing with prefix
    chop $next;

    my ($a,$b,$c,$d) = sort(("",$prev,$cur,$next));

#print STDERR "start\n$a\n$b\n$c\n$d\nstop\n";

    return ($prev,$next) if ($cur eq $c);
    return ("",$first) if ($cur eq $b);
    return ($last, "") if ($cur eq $d);
  }

  if ($dnibbles + $qnibbles < 32) {
    # expand until it has correct number of nibbles
    my $name = $p->{qname} . " " . ( "0 " x ($nnibbles-$qnibbles));
    chop $name;
    return ($name, $self->incrRevIP($name));
  }

  if ($dnibbles + $qnibbles == 32) {
    my $prev = $p->{qname};
    my $next = $self->incrRevIP($p->{qname});

    if ($p->{qname} eq $first) {
      return ("", $next);
    } elsif ($p->{qname} eq $last) {
      return ($prev, "");
    } else {
      return ($prev,$next);
    }
  }
}

sub do_getbeforeandafternamesabsolute {
  my $self = shift;

  my @result = $self->getbeforeandafternamesabsolute(shift);
 
  if (scalar(@result)>0) {
    my ($before,$after) = @result;
    $self->{_result} = {"before" => $before, "after" => $after};
    return;
  }

  $self->error;
}

package main;
use strict;
use warnings;
use 5.005;

## Start the script and run handler

$|=1;
my $handler = RemoteBackendHandler->new;

$handler->run;
