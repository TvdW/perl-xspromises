package Promise::ES6::XS::Loader;

use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load('Promise::ES6::XS', $VERSION);

Promise::ES6::XS::Backend::___set_conversion_helper(sub {
    my $promise= shift;
    my $deferred= Promise::ES6::XS::Backend::deferred();
    my $called;
    eval {
        $promise->then(sub {
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
    return $deferred->promise;
});

1;
