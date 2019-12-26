package Promise::XS::Loader;

use strict;
use warnings;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Promise::XS', $VERSION);

sub _convert_to_our_promise {
    my $thenable = shift;
    my $deferred= Promise::XS::Deferred::create();
    my $called;
    eval {
        $thenable->then(sub {
            return if $called++;
            $deferred->resolve(@_);
        }, sub {
            return if $called++;
            $deferred->reject(@_);
        });
        1;
    } or do {
        my $error= $@;
        if (!$called++) {
            $deferred->reject($error);
        }
    };

    undef $thenable;
    return $deferred->promise;
}

Promise::XS::Deferred::___set_conversion_helper(
    \&_convert_to_our_promise,
);

1;
