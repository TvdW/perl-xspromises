use 5.010;
use strict;
use warnings;

use Test::More;
use AnyEvent;
use AnyEvent::XSPromises;

my $cv= AE::cv;

my $deferred= AnyEvent::XSPromises::deferred();
my $promise= $deferred->promise;
$deferred->resolve(1, 2, 3);
my ($next_ok, $any, $finally_called, $reached_end);
for (1..1) {
    my $final= $promise->then(
        sub {
            ok(1);
            $any= 1;
            return (123, 456);
        },
        sub {
            fail;
        }
    )->finally(sub {
        $finally_called= 1;
        654;
    })->then(sub {
        is($_[0], 123);
        is($_[1], 456);
        die "Does this work?";
    })->then(
        sub {
            fail;
        },
        sub {
            ok(($_[0] =~ /Does this/) ? 1 : 0);
            next;
        }
    )->then(
        sub {
            fail;
        },
        sub {
            ok(($_[0] =~ /outside a loop block/) ? 1 : 0);
            $next_ok= 1;
        }
    )->then(sub {
        Fakepromise->new
    })->then(
        sub {
            is($_[0], 500);
            $_= 5;
        }, sub {
            fail($_[0]);
        }
    )->then(sub {
        is($_, undef);
        $reached_end= 1;
    })->then($cv)
}
$cv->recv;
ok($any);
ok($next_ok);
ok($reached_end);
ok($finally_called);

done_testing;

package Fakepromise;
sub new { bless {}, 'Fakepromise' }
sub then {
    my ($self, $resolve)= @_;
    $resolve->(500);
}
