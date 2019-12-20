package Promise::ES6::XS;

use strict;
use warnings;

=head1 NAME

Promise::ES6::XS - Fast ES6 promises

=head1 SYNOPSIS

See L<Promise::ES6>.

=head1 DESCRIPTION

This module implements the same interface as L<Promise::ES6>, but with
its major parts implemented in XS for speed.

The implementation is a refactor of L<AnyEvent::XSPromises>
by Tom van der Woerdt (C<tvdw@cpan.org>).

=cut

use Promise::ES6::XS::Loader ();

sub new {
    my ($class, $cr) = @_;

    my $deferred = Promise::ES6::XS::Backend::deferred();

    my $self = \($deferred->promise());

    my $ok = eval {
        $cr->(
            sub {

                # As of now, the backend doesn’t check whether the value
                # given to resolve() is a promise. ES6 handles that case,
                # though, so we do, too.
                if (UNIVERSAL::isa($_[0], __PACKAGE__)) {
                    $_[0]->then( sub { $deferred->resolve($_[0]) } );
                }
                else {
                    $deferred->resolve($_[0]);
                }
            },
            sub { $deferred->reject($_[0]) },
        );

        1;
    };

    if (!$ok) {
        my $err = $@;
        $$self = Promise::ES6::XS::Backend::rejected($err);
    }

    return bless $self, $class;
}

sub then {
    my ($self, $on_res, $on_rej) = @_;

    return bless \($$self->then( $on_res, $on_rej )), ref($self);
}

1;
