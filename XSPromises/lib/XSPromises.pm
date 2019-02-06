package XSPromises;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load('XSPromises', $VERSION);

XSPromises::_set_conversion_helper(sub {
    my $promise= shift;
    my $deferred= XSPromises::deferred();
    $promise->then(sub {
        $deferred->resolve(@_);
    }, sub {
        $deferred->reject(@_);
    });
    return $deferred->promise;
});

my $in;
XSPromises::_set_backend(sub {
    if (!$in) {
        $in= 1;
        local $_;
        # sort makes perl push a pseudo-block on the stack that prevents callback code from using
        # next/last/redo. Without it, an accidental invocation of one of those could cause serious
        # problems. We have to assign it to @useless_variable or Perl thinks our code is a no-op
        # and optimizes it away.
        my @useless_variable= sort { XSPromises::flush(); 0 } 1, 2;
        $in= 0;
    }
});


1;
