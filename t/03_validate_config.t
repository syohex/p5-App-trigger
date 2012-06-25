use strict;
use warnings;
use Test::More;

use App::trigger;

my $app = App::trigger->new;

subtest 'error test' => sub {
    eval {
        $app->_validate_config({
            test => 'test',
        });
    };
    like $@, qr/should be HashRef/, 'invalid parameter type';

    eval {
        $app->_validate_config({
            test => {
                color => 'red',
            },
        });
    };
    like $@, qr/does not have 'pattern'/, "not spcifiy 'pattern' parameter";
};

done_testing;
