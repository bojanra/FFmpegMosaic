#!perl
use 5.010;
use warnings;
use strict;
use utf8;
use lib './lib/';
use Test::More tests => 3;
use open ':std', ':encoding(utf8)';

BEGIN {
    use_ok("Mosaic") || print "Bail out!\n";
}

my $m = Mosaic->new( configFile => 't/sample.yaml' );

isa_ok( $m, 'Mosaic' );

ok( !$m->compileConfig(), 'Validate sample.yaml' );

say $m->report();

say $m->buildCmd();
