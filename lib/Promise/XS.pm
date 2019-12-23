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
use Data::Dumper;
print STDERR Dumper( \@_, \%args );

    if (my $backend = $args{'backend'}) {

        if ($backend eq 'AnyEvent') {
            Promise::XS::Deferred::set_backend_AnyEvent();
        }
        else {
            die( __PACKAGE__ . ": unknown backend: $backend" );
        }
    }
}

# convenience
*deferred = *Promise::XS::Deferred::create;

#sub new {
#    my ($class, $cr) = @_;
#
#    my $deferred = Promise::ES6::XS::Backend::deferred();
#
#    # 2nd el = warn on unhandled rejection
#    my $self = [ $deferred->promise() ];
#
#    my $soft_reject;
#
#    my $ok = eval {
#        $cr->(
#            sub {
#
#                # As of now, the backend doesn’t check whether the value
#                # given to resolve() is a promise. ES6 handles that case,
#                # though, so we do, too.
#                if (UNIVERSAL::isa($_[0], _BASE_PROMISE_CLASS)) {
#                    $_[0]->then( sub { $deferred->resolve($_[0]) } );
#                }
#                else {
#                    $deferred->resolve($_[0]);
#                }
#            },
#            sub {
#                $deferred->reject($_[0]);
#                $soft_reject = 1;
#            },
#        );
#
#        1;
#    };
#
#    $self->[1] = 1 if $soft_reject;
#
#    if (!$ok) {
#        $deferred->reject(my $err = $@);
#    }
#
#    return bless $self, $class;
#}
#
#sub then {
#    my ($self, $on_res, $on_rej) = @_;
#
#    return bless [ $self->[0]->then( $on_res, $on_rej ) ], ref($self);
#}
#
#sub DESTROY {
#    my ($self) = @_;
#
#    if (!$self->[1]) {
#        my $unhandled_rejection_sr = $self->[0]->_unhandled_rejection_sr();
#
#        if ($unhandled_rejection_sr) {
#            warn "$self: Unhandled rejection: $$unhandled_rejection_sr";
#        }
#    }
#
#    return;
#}

1;
