use 5.010;
use strict;
use warnings;

use Test::More;
use Promise::XS (backend => 'AnyEvent');

use AnyEvent;

#Promise::XS::Deferred::___set_deferral_backend_generic( sub {
#    use Data::Dumper;
#    print STDERR Dumper('generic called', 0 + @_);
#    print STDERR Dumper($_[0]);
#use Carp::Always;
#    my @args = @_;
#    &AnyEvent::postpone( $args[0] );
#} );

my $deferred = Promise::XS::deferred();

$deferred->resolve(5);

my $value;

my $cv = AnyEvent->condvar();

$deferred->promise()->then( sub {
    $value = shift;
    $cv->();
} );

is( $value, undef, 'no immediate operation');

$cv->recv();

is( $value, 5, 'deferred operation runs');

done_testing();
