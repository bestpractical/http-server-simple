package HTTP::Server::Simple;

use strict;
use warnings;
use Socket;
use CGI;

our $VERSION = '0.00_01';


=head1 NAME

HTTP::Server::Simple

=head1 WARNING

This code is still undergoing active development. Particularly, the API is not
yet frozen. Comments about the API would be greatly appreciated.

=head1 SYNOPSIS

 use warnings;
 use strict;
 
 use HTTP::Server::Simple;
 
 my $server = HTTP::Server::Simple->new();
 $server->run();

=head1 DESCRIPTION

This is a simple standalone http dameon. It doesn't thread. It doesn't fork.
It does, however, act as a simple frontend which can turn a CGI into a standalone web-based application.


=cut


=head2 new


=cut


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );
    $self->port('8080');
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

=head2 run

Run the server. If all goes well, this won't ever return, but it will start listening for http requests


=cut

sub run {
    my $self = shift;

    $self->setup_listener;

    $self->print_banner;

    while (1) {

        for ( ; accept( Remote, HTTPDaemon ) ; close Remote ) {

            *STDIN  = *Remote;
            *STDOUT = *Remote;

            my $remote_sockaddr = getpeername(STDIN);
            my ( undef, $iaddr ) = sockaddr_in($remote_sockaddr);
            my $peername = gethostbyaddr( $iaddr, AF_INET ) || "localhost";
            my $peeraddr = inet_ntoa($iaddr) || "127.0.0.1";

            my $local_sockaddr = getsockname(STDIN);
            my ( undef, $localiaddr ) = sockaddr_in($local_sockaddr);
            my $localname = gethostbyaddr( $localiaddr, AF_INET )
              || "localhost";
            my $localaddr = inet_ntoa($localiaddr) || "127.0.0.1";

            chomp( $_ = <STDIN> );
            my ( $method, $request_uri, $proto, undef ) = split;

            my ( $file, undef, $query_string ) =
              ( $request_uri =~ /([^?]*)(\?(.*))?/ );    # split at ?

            last if ( $method !~ /^(GET|POST|HEAD)$/ );

            $self->build_cgi_env(
                method       => $method,
                protocol     => $proto,
                query_string => ( $query_string || '' ),
                path         => $file,
                method       => $method,
                port         => $self->port,
                peername     => $peername,
                peeraddr     => $peeraddr,
                localname    => $localname,
                request_uri  => $request_uri
            );

            print "HTTP/1.0 200 OK\n";    # probably OK by now

            my $cgi = CGI->new();

            $self->handle_request($cgi);

        }

    }

}


=head2 handle_request CGI

This routine is called whenever your server gets a request it can handle. It's called with a CGI object that's been pre-initialized.  You want to override this method in your subclass


=cut


sub handle_request {
    my $self = shift;
    my $cgi  = shift;

    print <<EOF;

          <html><head><title>Hello!</title></head>
          <h1>Congratulations!</h1>

<body>
<p>You now have a functional HTTP::Server::Simple running.</p>
<p><i>(If you're seeing this page, it means you haven't subclassed HTTP::Server::Simple, which you'll need to do to make it useful.)</i></p>
   </body>
</html>

EOF

}


=head2 setup_listener

This routine binds the server to a port and interface


=cut


sub setup_listener {
    my $self = shift;

    my $tcp = getprotobyname('tcp');

    socket( HTTPDaemon, PF_INET, SOCK_STREAM, $tcp ) or die "socket: $!";
    setsockopt( HTTPDaemon, SOL_SOCKET, SO_REUSEADDR, pack( "l", 1 ) )
      or warn "setsockopt: $!";
    bind( HTTPDaemon, sockaddr_in( $self->port(), INADDR_ANY ) )
      or die "bind: $!";
    listen( HTTPDaemon, SOMAXCONN ) or die "listen: $!";

}

=head2  build_cgi_env

build up a CGI object out of a param hash

=cut

sub build_cgi_env {
    my $self = shift;
    my %args = (
        query_string => '',
        path         => '',
        port         => undef,
        protocol     => undef,
        localname    => undef,
        method       => undef,
        remote_name  => undef,
        @_
    );

    foreach my $var qw(USER_AGENT CONTENT_LENGTH CONTENT_TYPE
      COOKIE SERVER_PORT SERVER_PROTOCOL SERVER_NAME
      PATH_INFO REQUEST_URI REQUEST_METHOD REMOTE_ADDR
      REMOTE_HOST QUERY_STRING SERVER_SOFTWARE) {
        delete $ENV{$var};
      } while (<STDIN>) {
        s/[\r\l\n\s]+$//;
        if (/^([\w\-]+): (.+)/i) {
            my $tag = uc($1);
            $tag =~ s/^COOKIES$/COOKIE/;
            my $val = $2;
            $tag =~ s/-/_/g;
            $tag = "HTTP_" . $tag
              unless ( grep /^$tag$/, qw(CONTENT_LENGTH CONTENT_TYPE COOKIE) );
            if ( $ENV{$tag} ) {
                $ENV{$tag} .= "; $val";
            }
            else {
                $ENV{$tag} = $val;
            }
        }
        last if (/^$/);
    }

    $ENV{SERVER_PROTOCOL} = $args{protocol};
    $ENV{SERVER_PORT}     = $args{port};
    $ENV{SERVER_NAME}     = $args{'localname'};
    $ENV{SERVER_URL}      =
      "http://" . $args{'localname'} . ":" . $args{'port'} . "/";
    $ENV{PATH_INFO}      = $args{'path'};
    $ENV{REQUEST_URI}    = $args{'request_uri'};
    $ENV{REQUEST_METHOD} = $args{method};
    $ENV{REMOTE_ADDR}    = $args{'peeraddr'};
    $ENV{REMOTE_HOST}    = $args{'peername'};
    $ENV{QUERY_STRING}   = $args{'query_string'};
    $ENV{SERVER_SOFTWARE} ||= "HTTP::Server::Simple/$VERSION";

    CGI::initialize_globals();
}


=head2  print_banner

This routine prints a banner before the server request-handling loop starts.


=cut

sub print_banner {
    my $self = shift;

    print(  "You can connect to your server at http://localhost:"
          . $self->port
          . "/\n" );

}

=head1 AUTHOR

Copyright (c) 2001-2004 Jesse Vincent, jesse@bestpractical.com.

All rights reserved.


=head1 BUGS

There certainly are some. Please report them via rt.cpan.org

=head1 LICENSE

This library is free software; you can redistribute it
   and/or modify it under the same terms as Perl itself.

=cut

1;
