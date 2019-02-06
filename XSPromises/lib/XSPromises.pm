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
        XSPromises::flush();
        $in= 0;
    }
});


1;
