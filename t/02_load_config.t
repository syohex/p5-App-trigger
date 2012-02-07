use strict;
use warnings;
use Test::More;

use App::trigger;

use t::Util qw/create_configfile/;

my $app = App::trigger->new;

subtest 'error test' => sub {
    my $conf = create_configfile(['test', 'error']);
    $app->{config} = $conf->filename;
    eval {
        $app->_load_config_file;
    };
    like $@, qr/should return HashRef/, 'invalid configuration file';


    $app->{config} = 'not_exist.ptrigger';
    eval {
        $app->_load_config_file;
    };
    like $@, qr/is not exist/, 'not exist';
};

done_testing;
