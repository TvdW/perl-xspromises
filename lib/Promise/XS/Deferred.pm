package Promise::XS::Deferred;

use strict;
use warnings;

sub set_deferral_AnyEvent() {
    require AnyEvent;
    ___set_deferral_generic(
        \&AnyEvent::postpone,
    );
}

sub set_deferral_IOAsync {
    my ($loop) = @_;

    ___set_deferral_generic(
        $loop->can('later'),
        $loop,
    );
}

sub set_deferral_Mojo() {
    require Mojo::IOLoop;
    ___set_deferral_generic(
        Mojo::IOLoop->can('next_tick'),
        'Mojo::IOLoop',
    );
}

1;
