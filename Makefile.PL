use inc::Module::Install;
use Module::Install::AuthorTests;
use Module::Install::Repository;

name 'App-trigger';
all_from 'lib/App/trigger.pm';

author_tests('xt');
auto_set_repository();
WriteAll;
