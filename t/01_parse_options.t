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

subtest 'grep option' => sub {
    $app->parse_options(qw/-g/);
    ok $app->{grep}, 'short grep option';

    $app->parse_options(qw/--grep/);
    ok $app->{grep}, 'long grep option';
};

subtest 'bold option' => sub {
    $app->parse_options(qw/-b/);
    ok $app->{bold}, 'short bold option';

    $app->parse_options(qw/--bold/);
    ok $app->{bold}, 'long bold option';
};

subtest 'random option' => sub {
    $app->parse_options(qw/-r/);
    ok $app->{random}, 'short random option';

    $app->parse_options(qw/--random/);
    ok $app->{random}, 'long random option';
};

subtest 'match option' => sub {
    $app->parse_options(qw/-m shortopt/);
    is_deeply $app->{matches}, ['shortopt'], 'short match option';

    $app->parse_options(qw/--match longopt/);
    is_deeply $app->{matches}, ['longopt'], 'long match option';

    $app->parse_options(qw/-m apple:red -m banana:yellow/);
    is scalar @{$app->{matches}}, 2, 'specify multiple match option';
};

subtest 'follow option' => sub {
    $app->parse_options(qw/-f/);
    ok $app->{follow}, 'short follow option';

    $app->parse_options(qw/--follow/);
    ok $app->{follow}, 'long follow option';
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
    $app->parse_options(qw/-c myptrigger --follow myapp.log/);
    is $app->{file}, 'myapp.log', 'specify file';

    delete $app->{file};

    $app->parse_options(qw/-c myptrigger --follow/);
    ok !defined($app->{file}), 'not specify file(use STDIN)';
};

done_testing;
