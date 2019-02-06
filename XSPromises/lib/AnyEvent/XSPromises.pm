package AnyEvent::XSPromises;

use 5.010;
use strict;
use warnings;

use AnyEvent::XSPromises::Loader;

use Exporter 'import';
our @EXPORT_OK= qw/collect deferred resolved rejected/;

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

# XXX This is pure-perl, not XS like we promise our users.
sub collect {
    my $remaining= 0+@_;
    my @values;
    my $failed= 0;
    my $then_what= deferred;
    my $pending= 1;
    my $i= 0;
    for my $p (@_) {
        my $i= $i++;
        $p->then(sub {
            $values[$i]= [@_];
            if ((--$remaining) == 0) {
                $pending= 0;
                $then_what->resolve(@values);
            }
        }, sub {
            if (!$failed++) {
                $pending= 0;
                $then_what->reject(@_);
            }
        });
    }
    if (!$remaining && $pending) {
        $then_what->resolve(@values);
    }
    return $then_what->promise;
}

1;
