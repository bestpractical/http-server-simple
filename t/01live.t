# -*- perl -*-

use Socket;
use Test::More tests => 14;
use strict;

# This script assumes that `localhost' will resolve to a local IP
# address that may be bound to,

my $PORT = 40000 + int(rand(10000));


use HTTP::Server::Simple;

package SlowServer;
# This test class just waits a while before it starts
# accepting connections. This makes sure that CPAN #28122 is fixed:
# background() shouldn't return prematurely.

use base qw(HTTP::Server::Simple::CGI);
sub setup_listener {
    my $self = shift;
    $self->SUPER::setup_listener();
    sleep 2;
}
1;
package main;

my $DEBUG = 1 if @ARGV;

my @classes = (qw(HTTP::Server::Simple SlowServer));
for my $class (@classes) {
    run_server_tests($class);
    $PORT++; # don't reuse the port incase your bogus os doesn't release in time
}



{
    my $s=HTTP::Server::Simple::CGI->new($PORT);
    $s->host("localhost");
    my $pid=$s->background();
    diag("started server PID=$pid");
    like($pid, '/^-?\d+$/', 'pid is numeric');
    select(undef,undef,undef,0.2); # wait a sec
    my $content=fetch("GET / HTTP/1.1", "");
    like($content, '/Congratulations/', "Returns a page");

    eval {
	like(fetch("GET a bogus request"), 
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
	  "sockaddr" => sub { ($paddr = sockaddr_in($PORT, $iaddr))
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

sub run_server_tests {
    my $class = shift;
    my $s = $class->new($PORT);
    is($s->port(),$PORT,"Constructor set port correctly");

    my $pid=$s->background();
    select(undef,undef,undef,0.2); # wait a sec

    like($pid, '/^-?\d+$/', 'pid is numeric');

    my $content=fetch("GET / HTTP/1.1", "");

    like($content, '/Congratulations/', "Returns a page");
    is(kill(9,$pid),1,'Signaled 1 process successfully');
    wait or die "couldn't wait for sub-process completion";
}
