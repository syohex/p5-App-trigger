use inc::Module::Install;
use Module::Install::AuthorTests;
use Module::Install::Repository;

name 'App-trigger';
all_from 'lib/App/trigger.pm';

test_requires 'Test::More' => '0.98';

requires 'Term::ANSIColor';
requires 'AnyEvent';

install_script 'bin/ptrigger';

author_tests('xt');
auto_set_repository();
WriteAll;
