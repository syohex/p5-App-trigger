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
    is $app->{config_file}, 'shortconfig', 'short config option';

    $app->parse_options(qw/--config longconfig/);
    is $app->{config_file}, 'longconfig', 'long config option';
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

subtest 'specify file' => sub {
    $app->parse_options(qw/-c myptrigger --tail myapp.log/);
    is $app->{file}, 'myapp.log', 'specify file';

    delete $app->{file};

    $app->parse_options(qw/-c myptrigger --tail/);
    ok !defined($app->{file}), 'not specify file(use STDIN)';
};

done_testing;
