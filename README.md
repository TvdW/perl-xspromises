# NAME

Promise::XS - Fast promises in Perl

# SYNOPSIS

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

For compatibility with preexisting libraries, `all()` may also be called
as `collect()`.

# STATUS

The basics of this interface—`deferred()`

# DESCRIPTION

This module exposes a Promise interface with its major parts
implemented in XS for speed. It is a fork and refactor of
[AnyEvent::XSPromises](https://metacpan.org/pod/AnyEvent::XSPromises). That module’s interface, a “bare-bones”
subset of that from [Promises](https://metacpan.org/pod/Promises), is retained.

# EVENT LOOPS

This library, by default, uses no event loop. This is a perfectly usable
configuration; however, it’ll be a bit different from how promises usually
work in evented contexts (e.g., JavaScript) because callbacks will execute
immediately rather than at the end of the event loop as the Promises/A+
specification requires.

To achieve full Promises/A+ compliance it’s necessary to integrate with
an event loop interface. This library supports three such interfaces:

- [AnyEvent](https://metacpan.org/pod/AnyEvent):

        Promise::XS::use_event('AnyEvent');

- [IO::Async](https://metacpan.org/pod/IO::Async) - note the need for an [IO::Async::Loop](https://metacpan.org/pod/IO::Async::Loop) instance
as argument:

        Promise::XS::use_event('IO::Async', $loop_object);

- [Mojo::IOLoop](https://metacpan.org/pod/Mojo::IOLoop):

        Promise::XS::use_event('Mojo::IOLoop');

Note that all three of the above are event loop **interfaces**. They
aren’t event loops themselves, but abstractions over various event loops.
See each one’s documentation for details about supported event loops.

**REMINDER:** There’s no reason why promises _need_ an event loop; it
just satisfies the Promises/A+ convention.

# TODO

- `all()` and `race()` should be implemented in XS,
as should `resolved()` and `rejected()`.

# SEE ALSO

Besides [AnyEvent::XSPromises](https://metacpan.org/pod/AnyEvent::XSPromises) and [Promises](https://metacpan.org/pod/Promises), you may like [Promise::ES6](https://metacpan.org/pod/Promise::ES6),
which mimics ECMAScript’s `Promise` class as much as possible. It can even
(experimentally) use this module as a backend, so it’ll be
_almost_—but not quite—as fast as using this module directly.
