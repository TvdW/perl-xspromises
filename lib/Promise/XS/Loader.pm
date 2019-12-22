package Promise::XS::Loader;

use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load('Promise::XS', $VERSION);

sub _convert_to_our_promise {
    my $thenable = shift;
    my $deferred= Promise::XS::Deferred::deferred();
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
}

Promise::XS::Deferred::___set_conversion_helper(
    \&_convert_to_our_promise,
);

1;
