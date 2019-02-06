package AnyEvent::XSPromises;

use 5.010;
use strict;
use warnings;

use AnyEvent::XSPromises::Loader;

use Exporter 'import';
our @EXPORT_OK= qw/deferred resolved rejected/;

sub resolved {
    my $d= deferred;
    $d->resolve(@_);
    return $d->promise;
}

sub rejected {
    my $d= deferred;
    $d->reject(@_);
    return $d->promise;
}

# Convenience methods
sub catch { $_[0]->then(undef, @_) }

1;
