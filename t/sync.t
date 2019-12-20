#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Promise::ES6::XS;

my $val;

Promise::ES6::XS->new( sub { $_[0]->(42) } )->then(
    sub { $val = shift },
);

is( $val, 42, 'simple synchronous execution' );

done_testing;

1;
