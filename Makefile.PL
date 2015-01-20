use inc::Module::Install;

all_from('lib/HTTP/Server/Simple.pm');
name('HTTP-Server-Simple');
license('perl');
requires(
    Socket      => 1.94,
    'Test::More'  => 0,
    CGI         => 0,
);

WriteAll( sign => 1);
