use Test::More;
BEGIN {
    if (eval { require LWP::Simple }) {
	plan tests => 4;
    } else {
	Test::More->import(skip_all =>"LWP::Simple not installed: $@");
    }
}

use HTTP::Server::Simple;
my $s=HTTP::Server::Simple->new(13432);
is($s->port(),13432,"Constructor set port correctly");
my $pid=$s->background();
like($pid, qr/^-?\d+$/,'pid is numeric');
my $content=LWP::Simple::get("http://localhost:13432");
like($content,qr/Congratulations/,"Returns a page");
is(kill(9,$pid),1,'Signaled 1 process successfully');

