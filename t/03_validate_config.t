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

subtest 'validate color' => sub {
    my @colors = qw/bo it un rev bli
                    re bl gr ye ma cy wh
                    ore obl ogr oye oma ocy owh/;

    my @validated_colors = qw/bold italic underline reverse blink
                              red blue green yellow magenta cyan white
                              on_red on_blue on_green on_yellow
                              on_magenta on_cyan on_white/;

    my $got = [App::trigger::_validate_colors(@colors)];
    is_deeply($got, \@validated_colors, 'validate colors');

};

done_testing;
