package Promise::XS;

use strict;
use warnings;

=head1 NAME

Promise::XS - Fast promises

=head1 SYNOPSIS

    use Promise::XS ();

=head1 DESCRIPTION

This module exposes a bare-bones Promise interface with its major parts
implemented in XS for speed.

You don’t really need to load this module directly since L<Promise::ES6>
will prefer it to the pure-perl version; the only reason you might load
this module directly is if you want B<only> to use the XS backend (in
which case you’ll need to load it first, as in the SYNOPSIS).

The implementation is a fork and refactor of L<AnyEvent::XSPromises>.
You can achieve similar performance to that module by using this module
in tandem with L<Promise::XS::AnyEvent>.

=head1 INTERFACE

=cut

use Promise::XS::Loader ();
use Promise::XS::Deferred ();

our $DETECT_MEMORY_LEAKS;

sub import {
    my ($class, %args) = @_;

    if (my $deferral = $args{'deferral'}) {

        if ($deferral eq 'AnyEvent') {
            Promise::XS::Deferred::set_deferral_AnyEvent();
        }
        else {
            die( __PACKAGE__ . ": unknown deferral engine: $deferral" );
        }
    }
}

# convenience
*deferred = *Promise::XS::Deferred::create;

1;
