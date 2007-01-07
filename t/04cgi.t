use Test::More;
use Socket;
use strict;

plan tests => 21;

use constant PORT => 13432;
my $host = gethostbyaddr(inet_aton('localhost'), AF_INET);

my %methods=(
              url => "url: http://$host:".PORT,
              path_info => 'path_info: /cgitest/path_info',
              server_name => "server_name: $host",
              server_port => 'server_port: '.PORT,
              server_software => 'server_software: HTTP::Server::Simple/\d+.\d+',
              request_method => 'request_method: GET',
            );

my %envvars=(
              SERVER_URL => "SERVER_URL: http://$host:".PORT.'/',
              SERVER_PORT => 'SERVER_PORT: '.PORT,
              REQUEST_METHOD => 'REQUEST_METHOD: GET',
              REQUEST_URI => 'REQUEST_URI: /cgitest/REQUEST_URI',
              SERVER_PROTOCOL => 'SERVER_PROTOCOL: HTTP/1.1',
              SERVER_NAME => "SERVER_NAME: $host",
              SERVER_SOFTWARE => 'SERVER_SOFTWARE: HTTP::Server::Simple/\d+.\d+',
              REMOTE_ADDR => 'REMOTE_ADDR: 127.0.0.1',
              QUERY_STRING => 'QUERY_STRING: ',
              PATH_INFO => 'PATH_INFO: /cgitest/PATH_INFO',
            );

{
  my $server=CGIServer->new(PORT);
  is($server->port(),PORT,'Constructor set port correctly');
  select(undef,undef,undef,0.2); # wait a sec

  my $pid=$server->background;

  like($pid, '/^-?\d+$/', 'pid is numeric');

  select(undef,undef,undef,0.2); # wait a sec
  like(fetch("GET / HTTP/1.1",""), '/NOFILE/', 'no file');

  foreach my $method (keys(%methods)) {
    like(
          fetch("GET /cgitest/$method HTTP/1.1",""),
          "/$methods{$method}/",
          "method - $method"
        );
    select(undef,undef,undef,0.2); # wait a sec
  }

  foreach my $envvar (keys(%envvars)) {
    like(
          fetch("GET /cgitest/$envvar HTTP/1.1",""),
          "/$envvars{$envvar}/",
          "Environment - $envvar"
        );
    select(undef,undef,undef,0.2); # wait a sec
  }

  like(
       fetch("GET /cgitest/REQUEST_URI?foo%3Fbar",""),
       "/foo%3Fbar/",
       "Didn't decode already"
      );

  is(kill(9,$pid),1,'Signaled 1 process successfully');
  wait or die "counldn't wait for sub-process completion";
}


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

{
  package CGIServer;
  use base qw(HTTP::Server::Simple::CGI);
  use Env;

  sub handle_request {
    my $self=shift;
    my $cgi=shift;


    my $file=(split('/',$cgi->path_info))[-1]||'NOFILE';
    $file=~s/\s+//g;
    $file||='NOFILE';
    print "HTTP/1.0 200 OK\r\n";    # probably OK by now
    print "Content-Type: text/html\r\nContent-Length: ";
    my $response;
    if($methods{$file}) {
      $response = "$file: ".$cgi->$file();
    } elsif($envvars{$file}) {
      $response="$file: $ENV{$file}";
    } else {
      $response=$file;
    }
    print length($response), "\r\n\r\n", $response;
  }
}

