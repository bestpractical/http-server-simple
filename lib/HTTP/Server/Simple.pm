package HTTP::Server::Simple;
use 5.006;
use strict;
use warnings;
use Socket;
use Carp;

our $VERSION = '0.13';

=head1 NAME

HTTP::Server::Simple

=head1 WARNING

This code is still undergoing active development. Particularly, the
API is not yet frozen. Comments about the API would be greatly
appreciated.

=head1 SYNOPSIS

 use warnings;
 use strict;
 
 use HTTP::Server::Simple;
 
 my $server = HTTP::Server::Simple->new();
 $server->run();

However, normally you will sub-class the HTTP::Server::Simple::CGI
module (see L<HTTP::Server::Simple::CGI>);

 package Your::Web::Server;
 use base qw(HTTP::Server::Simple::CGI);
 
 sub handle_request {
     my ($self, $cgi) = @_;

     #... do something, print output to default
     # selected filehandle...

 }
 
 1;

=head1 DESCRIPTION

This is a simple standalone http dameon. It doesn't thread. It doesn't
fork.

It does, however, act as a simple frontend which can turn a CGI into a
standalone web-based application.

=head2 HTTP::Server::Simple->new($port)

API call to start a new server.  Does not actually start listening
until you call C<-E<gt>run()>.

=cut

# Handle SIGHUP

local $SIG{CHLD} = 'IGNORE'; # reap child processes
local $SIG{HUP} = sub {
    # on a "kill -HUP", we first close our socket handles.
    close Remote;
    close HTTPDaemon;

    # and then, on systems implementing fork(), we make sure
    # we are running with a new pid, so another -HUP will still
    # work on the new process.
    require Config;
    if ($Config::Config{d_fork} and my $pid = fork()) {
        # finally, allow ^C on the parent process to terminate
        # the children.
        waitpid($pid, 0); exit;
    }

    # do the exec. if $0 is not executable, try running it with $^X.
    exec { $0 } ( ((-x $0) ? () : ($^X)), $0, @ARGV );
};



sub new {
    my ($proto,$port) = @_;
    my $class = ref($proto) || $proto;

    if ( $class eq __PACKAGE__ ) {
        warn "HTTP::Server::Simple is an abstract base class\n";
        warn "Direct use of this module is deprecated\n";
        warn "Upgrading this object to an HTTP::Server::Simple::CGI object\n";
	require HTTP::Server::Simple::CGI;
	return HTTP::Server::Simple::CGI->new(@_[1..$#_]);
    }

    my $self  = {};
    bless( $self, $class );
    $self->port( $port || '8080');
    return $self;
}

=head2 port [NUMBER]

Takes an optional port number for this server to listen on.

Returns this server's port. (Defaults to 8080)

=cut

sub port {
    my $self = shift;
    $self->{'port'} = shift if (@_);
    return ( $self->{'port'} );

}

=head2 host [address]

Takes an optional host address for this server to bind to.

Returns this server's bound address (if any).  Defaults to C<undef>
(bind to all interfaces).

=cut

sub host {
    my $self = shift;
    $self->{'host'} = shift if (@_);
    return ( $self->{'host'} );

}

=head2 background

Run the server in the background. returns pid.

=cut

sub background {
    my $self  = shift;
    my $child = fork;
    die "Can't fork: $!" unless defined($child);
    return $child if $child;
    use POSIX;

    if ( $^O !~ /MSWin32/ ) {
        POSIX::setsid()
          or die "Can't start a new session: $!";
    }
    $self->run();
}


=head2 run

Run the server.  If all goes well, this won't ever return, but it will
start listening for http requests.

=cut

my $server_class_id = 0;
sub run {
    my $self    = shift;
    my $server  = $self->net_server;

    # $pkg is generated anew for each invocation to "run"
    # Just so we can use different net_server() implementations
    # in different runs.
    my $pkg     = join '::', ref($self), "NetServer".$server_class_id++;

    no strict 'refs';
    *{"$pkg\::process_request"} = $self->_process_request;

    if ($server) {
        require join('/', split /::/, $server).'.pm';
        *{"$pkg\::ISA"} = [$server];
        $self->print_banner;
    }
    else {
        $self->setup_listener;
        *{"$pkg\::run"} = $self->_default_run;
    }

    $pkg->run(port => $self->port);
}

=head2 net_server

User-overridable method. If you set it to a C<Net::Server> subclass,
that subclass is used for the C<run> method.  Otherwise, a minimal 
implementation is used as default.

=cut

sub net_server { undef }

sub _default_run {
    my $self = shift;

    # Default "run" closure method for a stub, minimal Net::Server instance.
    sub {
        my $pkg = shift;

        $self->print_banner;

        while (1) {
            for ( ; accept( Remote, HTTPDaemon ) ; close Remote ) {
                $self->stdio_handle(\*Remote);
                $self->accept_hook if $self->can("accept_hook");

                *STDIN  = $self->stdin_handle();
                *STDOUT = $self->stdout_handle();
		select STDOUT; # required for Recorder
                $pkg->process_request;
            }
        }    
    }
}

sub _process_request {
    my $self = shift;

    # Create a callback closure that is invoked for each incoming request;
    # the $self above is bound into the closure.
    sub {
        $self->stdio_handle(*STDIN) unless $self->stdio_handle;

        # Default to unencoded, raw data out.
        # if you're sending utf8 and latin1 data mixed, you may need to override this
        binmode STDIN, ':raw';
        binmode STDOUT, ':raw';

        my $remote_sockaddr = getpeername($self->stdio_handle);
        my ( undef, $iaddr ) = sockaddr_in($remote_sockaddr);
        my $peername = gethostbyaddr( $iaddr, AF_INET ) || "localhost";

        my $peeraddr = inet_ntoa($iaddr) || "127.0.0.1";

        my $local_sockaddr = getsockname($self->stdio_handle);
        my ( undef, $localiaddr ) = sockaddr_in($local_sockaddr);
        my $localname = gethostbyaddr( $localiaddr, AF_INET )
            || "localhost";
        my $localaddr = inet_ntoa($localiaddr) || "127.0.0.1";

        my ( $method, $request_uri, $proto ) =
            $self->parse_request
                or do {$self->bad_request; return};

        $proto ||= "HTTP/0.9";

        my ( $file, $query_string ) =
            ( $request_uri =~ /([^?]*)(?:\?(.*))?/ );    # split at ?

        if ( $method !~ /^(?:GET|POST|HEAD)$/ ) {
            $self->bad_request;
            return;
        }

        $self->setup(
            method       => $method,
            protocol     => $proto,
            query_string => ( $query_string || '' ),
            request_uri  => $request_uri,
            path         => $file,
            localname    => $localname,
            localport    => $self->port,
            peername     => $peername,
            peeraddr     => $peeraddr,
        );

        # HTTP/0.9 didn't have any headers (I think)
        if ( $proto =~ m{HTTP/(\d(\.\d)?)$} and $1 >= 1 ) {

            my $headers = $self->parse_headers
                or do{$self->bad_request; return};

            $self->headers( $headers) ;

        }

        $self->post_setup_hook if $self->can("post_setup_hook");

        $self->handler;
    }
}


=head2 stdio_handle [FILEHANDLE]

When called with an argument, sets the socket to the server to that arg.

Returns the socket to the server; you should only use this for actual socket-related
calls like C<getsockname>.  If all you want is to read or write to the socket,
you should use C<stdin_handle> and C<stdout_handle> to get the in and out filehandles
explicitly.

=cut

sub stdio_handle {
    my $self = shift;
    $self->{'_stdio_handle'} = shift if (@_);
    return $self->{'_stdio_handle'};
}

=head2 stdin_handle

Returns a filehandle used for input from the client.  By default, 
returns whatever was set with C<stdio_handle>, but a subclass
could do something interesting here (see L<HTTP::Server::Simple::Logger>).

=cut

sub stdin_handle {
    my $self = shift;
    return $self->stdio_handle;
} 

=head2 stdout_handle

Returns a filehandle used for output to the client.  By default, 
returns whatever was set with C<stdio_handle>, but a subclass
could do something interesting here (see L<HTTP::Server::Simple::Logger>).

=cut

sub stdout_handle {
    my $self = shift;
    return $self->stdio_handle;
} 


=head1 IMPORTANT SUB-CLASS METHODS

A selection of these methods should be provided by sub-classes of this
module.

=head2 handler

This method is called after setup, with no parameters.  It should
print a valid, I<full> HTTP response to the default selected
filehandle.

=cut

sub handler {
    my ( $self ) = @_;
    if ( ref ($self) ne __PACKAGE__ ) {
	croak "do not call ".ref($self)."::SUPER->handler";
    } else {
	die "handler called out of context";
    }
}

=head2 setup(name =E<gt> $value, ...)

This method is called with a name =E<gt> value list of various things
to do with the request.  This list is given below.

The default setup handler simply tries to call methods with the names
of keys of this list.

  ITEM/METHOD   Set to                Example
  -----------  ------------------    ------------------------
  method       Request Method        "GET", "POST", "HEAD"
  protocol     HTTP version          "HTTP/1.1"
  request_uri  Complete Request URI  "/foobar/baz?foo=bar"
  path         Path part of URI      "/foobar/baz"
  query_string Query String          undef, "foo=bar"
  port         Received Port         80, 8080
  peername     Remote name           "200.2.4.5", "foo.com"
  peeraddr     Remote address        "200.2.4.5", "::1"
  localname    Local interface       "localhost", "myhost.com"

=cut

sub setup {
    my ( $self ) = @_;
    while ( my ($item, $value) = splice @_, 0, 2 ) {
	$self->$item($value) if $self->can($item);
    }
}

=head2 headers([Header =E<gt> $value, ...])

Receives HTTP headers and does something useful with them.  This is
called by the default C<setup()> method.

You have lots of options when it comes to how you receive headers.

You can, if you really want, define C<parse_headers()> and parse them
raw yourself.

Secondly, you can intercept them very slightly cooked via the
C<setup()> method, above.

Thirdly, you can leave the C<setup()> header as-is (or calling the
superclass C<setup()> for unknown request items).  Then you can define
C<headers()> in your sub-class and receive them all at once.

Finally, you can define handlers to receive individual HTTP headers.
This can be useful for very simple SOAP servers (to name a
crack-fueled standard that defines its own special HTTP headers). 

To do so, you'll want to define the C<header()> method in your subclass.
That method will be handed a (key,value) pair of the header name and the value.


=cut

sub headers {
    my $self = shift;
    my $headers = shift;

    my $can_header = $self->can("header");
    while ( my ($header, $value) = splice @$headers, 0, 2 ) {
	if ( $can_header ) {
	    $self->header($header => $value)
	}
    }
}

=head2 accept_hook

If defined by a sub-class, this method is called directly after an
accept happens.

=head2 post_setup_hook

If defined by a sub-class, this method is called after all setup has
finished, before the handler method.

=head2  print_banner

This routine prints a banner before the server request-handling loop
starts.

Methods below this point are probably not terribly useful to define
yourself in subclasses.

=cut

sub print_banner {
    my $self = shift;

    print(  __PACKAGE__.": You can connect to your server at "
	    ."http://localhost:" . $self->port
          . "/\n" );

}

=head2 parse_request

Parse the HTTP request line.

Returns three values, the request method, request URI and the protocol
Sub-classed versions of this should return three values - request
method, request URI and proto

=cut

sub parse_request {
    my $self = shift;
    my $chunk;
    while ( sysread( STDIN, my $buff, 1 ) ) {
        last if $buff eq "\n";
        $chunk .= $buff;
    }
    defined($chunk) or return undef;
    $_ = $chunk;

    m/^(\w+)\s+(\S+)(?:\s+(\S+))?\r?$/;
    my $method = $1 || '';
    my $uri = $2 || '';
    my $protocol = $3 || '';

    return($method, $uri, $protocol);
}

=head2 parse_headers

Parse incoming HTTP headers from STDIN.

Remember, this is a B<simple> HTTP server, so nothing intelligent is
done with them C<:-)>.

This should return an ARRAY ref of C<(header =E<gt> value)> pairs
inside the array.

=cut

sub parse_headers {
    my $self = shift;

    my @headers;

    my $chunk = '';
    while ( sysread( STDIN, my $buff, 1 ) ) {
        if ( $buff eq "\n" ) {
            $chunk =~ s/[\r\l\n\s]+$//;
            if ( $chunk =~ /^([\w\-]+): (.+)/i ) {
                push @headers, $1 => $2;
            }
            last if ( $chunk =~ /^$/ );
            $chunk = '';
        }
        else { $chunk .= $buff }
    }

    return(\@headers);
}


=head2 setup_listener

This routine binds the server to a port and interface.

=cut

sub setup_listener {
    my $self = shift;

    my $tcp = getprotobyname('tcp');

    socket( HTTPDaemon, PF_INET, SOCK_STREAM, $tcp ) or die "socket: $!";
    setsockopt( HTTPDaemon, SOL_SOCKET, SO_REUSEADDR, pack( "l", 1 ) )
      or warn "setsockopt: $!";
    bind( HTTPDaemon,
        sockaddr_in(
            $self->port(),
            (
                $self->host
                ? inet_aton( $self->host )
                : INADDR_ANY
            )
        )
      )
      or die "bind: $!";
    listen( HTTPDaemon, SOMAXCONN ) or die "listen: $!";

}

=head2 bad_request

This method should print a valid HTTP response that says that the
request was invalid.

=cut

our $bad_request_doc = join "", <DATA>;

sub bad_request {
    my $self = shift;

    print "HTTP/1.0 400 Bad request\r\n";    # probably OK by now
    print "Content-Type: text/html\r\nContent-Length: ",
	length($bad_request_doc), "\r\n\r\n", $bad_request_doc;
}

=head1 AUTHOR

Copyright (c) 2004-2005 Jesse Vincent, <jesse@bestpractical.com>.
All rights reserved.

Marcus Ramberg <drave@thefeed.no> contributed tests, cleanup, etc

Sam Vilain, <samv@cpan.org> contributed the CGI.pm split-out and
header/setup API.

=head1 BUGS

There certainly are some. Please report them via rt.cpan.org

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

__DATA__
<html>
  <head>
    <title>Bad Request</title>
  </head>
  <body>
    <h1>Bad Request</h1>

    <p>Your browser sent a request which this web server could not
      grok.</p>
  </body>
</html>
