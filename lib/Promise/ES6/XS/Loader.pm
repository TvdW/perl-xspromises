package Promise::ES6::XS::Loader;

use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load('Promise::ES6::XS', $VERSION);

Promise::ES6::XS::Backend::___set_conversion_helper(sub {
    my $thenable = shift;
    my $deferred= Promise::ES6::XS::Backend::deferred();
    my $called;
#warn "====================== helper ($thenable)\n";
    eval {
        $thenable->then(sub {
            return if $called++;
            $deferred->resolve(@_);
        }, sub {
#warn "rejection: [$_[0]]\n";
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
#warn "=============== after thenable destroyed\n";
    return $deferred->promise;
});

1;
