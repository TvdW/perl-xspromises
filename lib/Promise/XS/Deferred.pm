package Promise::XS::Deferred;

use strict;
use warnings;

use AnyEvent ();

sub set_backend_AnyEvent() {
    ___set_deferral_backend_generic(
        AnyEvent->can('postpone'),
    );
}

1;
