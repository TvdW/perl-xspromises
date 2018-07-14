use v5.18;
use warnings;

use Test::More tests => 1;
use Data::Dumper;
use Carp;
use Benchmark qw/timethese/;
use Devel::Peek;
BEGIN { use_ok('XSPromises') };
use Promises;

my $deferred= XSPromises::deferred();
my $promise= $deferred->promise;
$deferred->resolve(1, 2, 3);
my ($next_ok, $any);
for (1..1) {
    my $final= $promise->then(
        sub {
            print STDERR "SUCCESS\n";
            $any= 1;
            return (123, 456);
        },
        sub {
            print STDERR "Wait what?!\n";
        }
    )->then(sub {
        print STDERR "123: $_[0]; 456: $_[1]\n";
        die "Does this work?";
    })->then(
        sub {
            print STDERR "FAIL\n";
        },
        sub {
            print STDERR "Error: @_\n";
            next;
        }
    )->then(
        sub {
            print STDERR "FAIL\n";
        },
        sub {
            print STDERR "next via reject: @_\n";
            warn "Test, 123";
            warn(Carp::longmess());
            $next_ok= 1;
        }
    )->then(sub {
        Fakepromise->new
    })->then(
        sub {
            print STDERR "500 = $_[0]\n";
        }, sub {
            print STDERR "FAIL: @_\n";
        }
    );
    print STDERR Dumper($deferred, $promise, $final);
}
die "callbacks weren't handled" unless $any;
die "our next; prevention code really broke" unless $next_ok;

sub a_promise {
    my $deferred= XSPromises::deferred;
    $deferred->resolve(1,2,3,4,5);
    return $deferred->promise;
}
sub b_promise {
    my $deferred= Promises::deferred;
    $deferred->resolve(1,2,3,4,5);
    return $deferred->promise;
}

timethese(-10, {
    new_one => sub {
        my $have_result;
        a_promise()->then(sub { a_promise(); })->then(sub { $have_result= 1; });
        die unless $have_result;
    },
    new_two => sub {
        my $i;
        a_promise()->then(sub {
            if (++$i == 5) {
                return;
            } else {
                a_promise()->then(__SUB__);
            }
        });
        die unless $i == 5;
    },
    old_one => sub {
        my $have_result;
        b_promise()->then(sub { b_promise(); })->then(sub { $have_result= 1; });
        die unless $have_result;
    },
    old_two => sub {
        my $i;
        b_promise()->then(sub {
            if (++$i == 5) {
                return;
            } else {
                b_promise()->then(__SUB__);
            }
        });
        die unless $i == 5;
    },
});

package Fakepromise;
sub new { bless {}, 'Fakepromise' }
sub then {
    my ($self, $resolve)= @_;
    $resolve->(500);
}
