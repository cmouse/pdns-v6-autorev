use strict;
use warnings;
use 5.005;
use IPC::Open3;
use Symbol 'gensym'; 

my($wr, $rd, $err);
$err = gensym;

my $pid;

$|=1;
sub speak {
	my $out = shift;
        print $wr "$out\n";
}

sub expect  {
        my $in = shift;
	my $data = <$rd>;
        chomp($data);
        return $data=~m/$in/;
}

sub speak_and_expect {
	my $out = shift;
	my $in  = shift;
	speak $out;
	return expect $in;
}

sub result {
	my $text = shift;
	my $result = shift;
	
	$result and print "$text OK\n";
	$result or print "$text FAIL\n";
}

sub harness {
	$pid = open3($wr, $rd, $err, "./rev.pl");
}

sub finish {
	close $wr;
	close $rd;
	waitpid($pid,0);
}

harness;

result "Open", speak_and_expect "HELO\t1","^OK.*";

speak "Q\t4.a.9.7.b.9.e.f.0.0.0.0.0.0.0.0.f.f.6.5.0.5.2.0.0.0.0.0.0.8.e.f.ip6.arpa\tIN\tANY\t-1\t127.0.0.1";
result "Reverse ",expect "DATA\t4.a.9.7.b.9.e.f.0.0.0.0.0.0.0.0.f.f.6.5.0.5.2.0.0.0.0.0.0.8.e.f.ip6.arpa\tIN\tPTR\t300\t-1\tnode-86uph4e.dyn.test";
expect "END";
speak "Q\tnode-86uph4e.dyn.test\tIN\tANY\t-1\t127.0.0.1";
result "Forward ",expect "DATA\tnode-86uph4e.dyn.test\tIN\tAAAA\t300\t-1\tfe80:0000:0250:56ff:0000:0000:fe9b:79a4";
expect "END";

my @list;

map {
	push @list, (join '.', split //, sprintf("%04x",$_));
} (0 .. 0xffff);

# speed test
print "Testing speed for 0000 to ffff (this will take some time)";
my $t0 = time;
map { 
	print $wr "Q\t$_.b.9.e.f.0.0.0.0.0.0.0.0.f.f.6.5.0.5.2.0.0.0.0.0.0.8.e.f.ip6.arpa\tIN\tANY\t-1\t127.0.0.1\n";
	my $scrap = <$rd>;
	$scrap = <$rd>;
} @list;
my $t = time - $t0;

print "OK\n";
my $qps = 65535/$t;

print "Performance was $qps q/s\n";

finish;
