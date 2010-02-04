use inc::Module::Install;

version_from('lib/HTTP/Server/Simple.pm');
name('HTTP-Server-Simple');
license('perl');
requires(
    Socket      => 0,
    Test::More  => 0,
    CGI         => 0,
);

WriteAll( sign => 1);
