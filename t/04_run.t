use strict;
use warnings;
use Test::More;

use Fcntl qw/:flock/;
use File::Temp qw/tempfile/;

use App::trigger;
use t::Util qw/create_configfile/;

subtest 'exec callback' => sub {
    my $app = App::trigger->new;
    my $conf = create_configfile([qw/hello world hello/]);

    $app->parse_options($conf->filename);

    my (undef, $tmpname) = tempfile();

    # modify internal data
    $app->{config} = {
        test => {
            pattern => qr/hello/,
            action  => sub {
                open my $fh, ">>", $tmpname or die "Can't open file: $!";
                flock $fh, LOCK_EX;
                print {$fh} "called\n";
                flock $fh, LOCK_UN;
                close $fh;
            },
        }
    };
    $app->run;

    my $content = do {
        local $/;
        open my $fh, "<", $tmpname;
        <$fh>;
    };

    my $called_count = 0;
    $called_count++ while $content =~ m{called}g;
    is $called_count, 2, 'called action callback';

    unlink $tmpname if -f $tmpname;
};

subtest 'callback argument' => sub {
    my $app = App::trigger->new;
    my $conf = create_configfile("a12cdef b99z");

    $app->parse_options($conf->filename);

    my (undef, $tmpname) = tempfile();

    # modify internal data
    $app->{config} = {
        test1 => {
            pattern => qr/a(\d{2})([a-zA-Z]+)/,
            action  => sub {
                my ($matched, $cap1, $cap2) = @_;
                open my $fh, ">>", $tmpname or die "Can't open file: $!";
                flock $fh, LOCK_EX or die "Can't flock file: $!";
                if ($matched eq "a12cdef" && $cap1 eq "12" && $cap2 eq "cdef") {
                    print {$fh} "argument_ok\n";
                }
                flock $fh, LOCK_UN;
                close $fh;
            },
        },

        test2 => {
            pattern => qr/99(\w)/,
            action  => sub {
                my ($matched, $cap1) = @_;

                open my $fh, ">>", $tmpname or die "Can't open file: $!";
                flock $fh, LOCK_EX or die "Can't flock file: $!";
                if ($matched eq "99z" && $cap1 eq "z") {
                    print {$fh} "argument_ok\n";
                }
                flock $fh, LOCK_UN;
                close $fh;
            },
        },
    };

    $app->run;

    my $content = do {
        local $/;
        open my $fh, "<", $tmpname;
        <$fh>;
    };

    my $called_count = 0;
    $called_count++ while $content =~ m{argument_ok}g;
    is $called_count, 2, 'passing callback arguments';

    unlink $tmpname if -f $tmpname;
};

subtest 'no pattern' => sub {
    my $app = App::trigger->new;
    $app->parse_options(qw/not_found_file/);
    eval {
        $app->run;
    };
    like $@, qr/No pattern specified/, 'not specified pattern';
};

subtest 'no target file' => sub {
    my $app = App::trigger->new;
    $app->parse_options(qw/-m pattern not_found_file/);
    eval {
        $app->run;
    };
    like $@, qr/is not existed/, 'target file is not found';
};

subtest 'valid color attribute' => sub {
    my $app = App::trigger->new;
    $app->parse_options(qw/-m pattern:greeen/);
    eval {
        $app->run;
    };
    like $@, qr/is invalid color parameter/, 'using invalid color parameter';
};

done_testing;
