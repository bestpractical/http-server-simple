# -*- perl -*-

use Socket;
use Test::More tests => 10;
use strict;

# This script assumes that `localhost' will resolve to a local IP
# address that may be bound to,

use constant PORT => 13432;

use HTTP::Server::Simple;

my $DEBUG = 1 if @ARGV;

{
    my $s=HTTP::Server::Simple->new(PORT);
    is($s->port(),PORT,"Constructor set port correctly");

    my $pid=$s->background();

    like($pid, '/^-?\d+$/', 'pid is numeric');
    select(undef,undef,undef,0.2); # wait a sec

    my $content=fetch("GET / HTTP/1.1", "");

    like($content, '/Congratulations/', "Returns a page");
    is(kill(9,$pid),1,'Signaled 1 process successfully');
    wait or die "couldn't wait for sub-process completion";
}

{
    my $s=HTTP::Server::Simple::CGI->new(PORT);
    $s->host("localhost");
    my $pid=$s->background();
    diag("started server on $pid");
    select(undef,undef,undef,0.2); # wait a sec
    like($pid, '/^-?\d+$/', 'pid is numeric');

    my $content=fetch("GET / HTTP/1.1", "");
    like($content, '/Congratulations/', "Returns a page");

    eval {
	like(fetch("GET your mum wet"),  # anything does!
	     '/bad request/i',
	     "knows what a request isn't");
    };
    fail("got exception in client: $@") if $@;

    like(fetch("GET / HTTP/1.1", ""), '/Congratulations/',
	 "HTTP/1.1 request");

    like(fetch("GET /"), '/Congratulations/',
	 "HTTP/0.9 request");

    is(kill(9,$pid),1,'Signaled 1 process successfully');
}

# this function may look excessive, but hopefully will be very useful
# in identifying common problems
sub fetch {

    my @response;
    my $alarm = 0;
    my $stage = "init";

    my %messages =
	( "init" => "inner contemplation",
	  "lookup" => ("lookup of `localhost' - may be caused by a "
		       ."missing hosts entry or broken resolver"),
	  "sockaddr" => "call to sockaddr_in() - ?",
	  "proto" => ("call to getprotobyname() - may be caused by "
		      ."bizarre NSS configurations"),
	  "socket" => "socket creation",
	  "connect" => ("connect() - may be caused by a missing or "
			."broken loopback interface, or firewalling"),
	  "send" => "network send()",
	  "recv" => "collection of response",
	  "close" => "closing socket"
	);

    $SIG{ALRM} = sub {
	@response = "timed out during $messages{$stage}";
	$alarm = 1;
    };

    my ($iaddr, $paddr, $proto, $message);

    $message = join "", map { "$_\015\012" } @_;

    my %states =
	( 'init'     => sub { "lookup"; },
	  "lookup"   => sub { ($iaddr = inet_aton("localhost"))
				  && "sockaddr"			    },
	  "sockaddr" => sub { ($paddr = sockaddr_in(PORT, $iaddr))
				  && "proto"			    },
	  "proto"    => sub { ($proto = getprotobyname('tcp'))
				  && "socket"			    },
	  "socket"   => sub { socket(SOCK, PF_INET, SOCK_STREAM, $proto)
				  && "connect"			    },
	  "connect"  => sub { connect(SOCK, $paddr) && "send"	    },
	  "send"     => sub { (send SOCK, $message, 0) && "recv"    },
	  "recv"     => sub {
	      my $line;
	      while (!$alarm and defined($line = <SOCK>)) {
		  push @response, $line;
	      }
	      ($alarm ? undef : "close");
	  },
	  "close"    => sub { close SOCK; "done"; },
	);

    # this entire cycle should finish way before this timer expires
    alarm(5);

    my $next;
    $stage = $next
	while (!$alarm && $stage ne "done"
	       && ($next = $states{$stage}->()));

    warn "early exit from `$stage' stage; $!" unless $next;

    # bank on the test testing for something in the response.
    return join "", @response;


}

