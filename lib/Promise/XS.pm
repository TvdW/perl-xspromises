package Promise::XS;

use strict;
use warnings;

=head1 NAME

Promise::XS - Fast promises

=head1 SYNOPSIS

    use Promise::XS ();

    my $deferred = Promise::XS::deferred();

    # Do one of these once you have the result of your operation:
    $deferred->resolve( 'foo', 'bar' );
    $deferred->reject( 'oh', 'no!' );

    # Give this to your caller:
    my $promise = $deferred->promise();

The following aggregator functions are exposed:

    # Resolves with a list of arrayrefs, one per promise.
    # Rejects with the results from the first rejected promise.
    my $all_p = Promise::XS::all( $promise1, $promise2, .. );

    # Resolves/rejects with the results from the first
    # resolved or rejected promise.
    my $race_p = Promise::XS::race( $promise3, $promise4, .. );

For compatibility with preexisting libraries, C<all()> may also be called
as C<collect()>.

=head1 DESCRIPTION

This module exposes a Promise interface with its major parts
implemented in XS for speed. It intends to be (mostly) a drop-in replacement
for L<Promises> or L<AnyEvent::XSPromises>.

The implementation is a fork and refactor of L<AnyEvent::XSPromises>.
You can achieve similar performance to that module by doing:

    use Promise::XS (deferral => 'AnyEvent');

You can alternatively use a different deferral backend if that suits
your application better. The ones provided are:

=over

=item * L<AnyEvent>

=item * L<IO::Async>

=item * L<Mojo::IOLoop>

=back

=cut

use Promise::XS::Loader ();
use Promise::XS::Deferred ();

our $DETECT_MEMORY_LEAKS;

use constant DEFERRAL_CR => {
    AnyEvent => \&Promise::XS::Deferred::set_deferral_AnyEvent,
    'IO::Async' => \&Promise::XS::Deferred::set_deferral_IOAsync,
    'Mojo::IOLoop' => \&Promise::XS::Deferred::set_deferral_Mojo,
};

sub use_event {
    my ($name, @args) = @_;

    if (my $cr = DEFERRAL_CR()->{$name}) {
        $cr->(@args);
    }
    else {
        die( __PACKAGE__ . ": unknown event engine: $name" );
    }
}

# convenience
*deferred = *Promise::XS::Deferred::create;

1;
