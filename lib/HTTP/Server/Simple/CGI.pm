
package HTTP::Server::Simple::CGI;

use base qw(HTTP::Server::Simple);
use strict;
use warnings;

use CGI ();

our $VERSION = $HTTP::Server::Simple::VERSION;

my %clean_env=%ENV;

=head1 NAME

HTTP::Server::Simple::CGI - CGI.pm-style version of HTTP::Server::Simple

=head1 DESCRIPTION

HTTP::Server::Simple was already simple, but some smart-ass pointed
out that there is no CGI in HTTP, and so this module was born to
isolate the CGI.pm-related parts of this handler.


=head2 accept_hook

The accept_hook in this sub-class clears the environment to the
start-up state.

=cut

sub accept_hook {
    %ENV= ( %clean_env,
	    SERVER_SOFTWARE => "HTTP::Server::Simple/$VERSION"
	  );
}

=head2 post_setup_hook



=cut

sub post_setup_hook{

    $ENV{SERVER_URL} ||=
	("http://".$ENV{SERVER_NAME}.":".$ENV{SERVER_PORT}."/");

    CGI::initialize_globals();
}

=head2 setup

This method sets up environment variables based on various
meta-headers, like the protocol, remote host name, request path, etc.

=cut

our %env_mapping =
    ( protocol => "SERVER_PROTOCOL",
      localport => "SERVER_PORT",
      localname => "SERVER_NAME",
      path => "PATH_INFO",
      request_uri => "REQUEST_URI",
      method => "REQUEST_METHOD",
      peeraddr => "REMOTE_ADDR",
      peername => "REMOTE_HOST",
      query_string => "QUERY_STRING",
    );

sub setup {
    no warnings 'uninitialized';
    my $self = shift;

    while ( my ($item, $value) = splice @_, 0, 2 ) {
	if ( $self->can($item) ) {
	    $self->$item($value);
	} elsif ( my $k = $env_mapping{$item} ) {
	    $ENV{$k} = $value;
	}
    }

}

=head2  headers

This method sets up the process environment in icky-CGI style based on
the HTTP input headers.

=cut

sub headers {
    my $self = shift;
    my $headers = shift;

    while ( my ($tag, $value) = splice @_, 0, 2 ) {
	$tag = uc($tag);
	$tag =~ s/^COOKIES$/COOKIE/;
	$tag =~ s/-/_/g;
	$tag = "HTTP_" . $tag
	    unless $tag =~ m/^CONTENT_(?:LENGTH|TYPE)$/;

	if ( exists $ENV{$tag} ) {
	    $ENV{$tag} .= "; $value";
	} else {
	    $ENV{$tag} = $value;
	}
    }
}

=head2 handle_request CGI

This routine is called whenever your server gets a request it can
handle.

It's called with a CGI object that's been pre-initialized.
You want to override this method in your subclass


=cut

our $default_doc;
$default_doc = (join "", <DATA>);

sub handle_request {
    my ( $self, $cgi ) = @_;

    print "HTTP/1.0 200 OK\r\n";    # probably OK by now
    print "Content-Type: text/html\r\nContent-Length: ",
	length($default_doc), "\r\n\r\n", $default_doc;
}

=head2 handler

Handler implemented as part of HTTP::Server::Simple API

=cut

sub handler {
    my $self = shift;
    my $cgi = new CGI();
    $self->handle_request($cgi);
}


1;

__DATA__
<html>
  <head>
    <title>Hello!</title>
  </head>
  <body>
    <h1>Congratulations!</h1>

    <p>You now have a functional HTTP::Server::Simple running.
      </p>

    <p><i>(If you're seeing this page, it means you haven't subclassed
      HTTP::Server::Simple, which you'll need to do to make it
      useful.)</i>
      </p>
  </body>
</html>
