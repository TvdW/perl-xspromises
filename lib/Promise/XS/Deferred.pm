package Promise::XS::Deferred;

use strict;
use warnings;

use AnyEvent ();

sub set_deferral_AnyEvent() {
    ___set_deferral_generic(
        \&AnyEvent::postpone,
    );
}

1;
