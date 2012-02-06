use strict;
use warnings;
use Test::More;

use App::trigger;

my $app = App::trigger->new;
ok $app, 'constructor';
isa_ok $app, 'App::trigger';

can_ok $app, 'parse_options';

subtest 'config option' => sub {
    $app->parse_options(qw/-c shortconfig/);
    is $app->{config}, 'shortconfig', 'short config option';

    $app->parse_options(qw/--config longconfig/);
    is $app->{config}, 'longconfig', 'long config option';
};

subtest 'tail option' => sub {
    $app->parse_options(qw/-t/);
    ok $app->{tail}, 'short tail option';

    $app->parse_options(qw/--tail/);
    ok $app->{tail}, 'long tail option';
};

subtest 'help option' => sub {
    eval {
        $app->parse_options(qw/-h/);
    };
    like $@, qr/Usage/, 'short help option';

    eval {
        $app->parse_options(qw/--help/);
    };
    like $@, qr/Usage/, 'long help option';
};

done_testing;
