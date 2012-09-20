package App::trigger;
use strict;
use warnings;

use Carp ();
use POSIX ();
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use File::Spec ();
use Term::ANSIColor ();

use AnyEvent ();
use AnyEvent::Handle ();

use 5.008_001;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    bless {}, $class;
}

sub _reaper {
    my $sig = shift;

    while (waitpid(-1, &POSIX::WNOHANG) > 0) {
        ;
    }
    $SIG{CHLD} = \&_reaper;
}

sub _wait_children_finished {
    my $self = shift;

    while (1) {
        for my $pid (keys %{$self->{processes}}) {
            if (waitpid($pid, &POSIX::WNOHANG) == -1) {
                delete $self->{processes}->{$pid};
            }
        }

        last if scalar keys %{$self->{processes}} == 0;
    }
}

sub _create_handle {
    my $self = shift;

    return AnyEvent::Handle->new(
        fh => $self->{fh},
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            $handle->destroy;
            undef $handle;
            $self->{cv}->send("$fatal: $message");
        },
        on_eof => sub {
            if ($self->{follow}) {
                $self->{handle}->destroy;
                undef $self->{handle};
                $self->{handle} = $self->_create_handle();
            } else {
                $self->{cv}->send("finish");
            }
        },
        on_read => sub {
            my $handle = shift;
            $handle->push_read(
                line => sub {
                    my ($handle, $line) = @_;

                    my $orig_line = $line;
                    while ( my ($name, $conf) = each %{$self->{config}} ) {
                        $self->_match_line($conf, $orig_line, \$line);
                    }
                    print "$line\n";
                },
            );
        },
    );
}

sub _load_match_options {
    my $self = shift;

    my %config;
    my $index = 0;
    for my $match_opt ( @{$self->{matches}} ) {
        my ($pattern, $color, $action) = split ':', $match_opt, 3;

        unless (defined $color) {
            $color = 'reverse';
        }

        if (defined $action) {
            $action = _wrap_action_around_coderef($action);
        }

        my @color_params = split ',', $color;
        my @valid_colors = _validate_colors(@color_params);

        $config{ "_matchopt_" . $index } = {
            pattern => qr/$pattern/,
            color   => "@valid_colors",
            action  => $action,
        };
        $index++;
    }

    my $old_conf = $self->{config} || {};
    $self->{config} = { (%{$old_conf}, %config) };
}

sub run {
    my $self = shift;

    if ($self->{config_file}) {
        $self->_load_config_file;
    }

    if ($self->{matches}) {
        $self->_load_match_options;
    }

    if (scalar(keys %{$self->{config}}) == 0) {
        die "No pattern specified\n";
    }

    my $fh;
    if ($self->{file}) {
        unless (-e $self->{file}) {
            Carp::croak("'$self->{file}' is not existed");
        }

        open $self->{fh}, '<', $self->{file} or die "Can't open $self->{file}: $!";
    } else {
        $self->{fh} = \*STDIN;
    }

    local $SIG{CHLD} = \&_reaper;

    local $| = 1;

    $self->{cv}     = AnyEvent->condvar;
    $self->{handle} = $self->_create_handle();

    $self->{cv}->recv;
    $self->_wait_children_finished;

    close $self->{fh} if $self->{file};
}

sub _match_line {
    my ($self, $conf, $orig_line, $line_ref) = @_;

    my $pattern = $conf->{pattern};
    my $already_colored;

    while ($orig_line =~ m{$pattern}g) {
        my $matched_string = $&;
        my @captured = $matched_string =~ m{$pattern}g;

        if (!$already_colored && $conf->{color}) {
            my $color = Term::ANSIColor::color($conf->{color});
            my $reset = Term::ANSIColor::color('reset');
            ${$line_ref} =~ s!($pattern)!${color}${1}${reset}!g;
            $already_colored = 1;
        }

        if ($conf->{action}) {
            my $pid = fork;
            Carp::croak "Can't fork: $!" unless defined $pid;

            if ($pid == 0) {
                local %SIG;

                # Child process
                $conf->{action}->($matched_string, @captured);
##                print "finish: $$ \n";
                exit 0;
            } else {
                # Parent process
                $self->{processes}->{$pid} = 1;
            }
        }
    }
}

sub parse_options {
    my ($self, @argv) = @_;

    local @ARGV = @argv;

    Getopt::Long::GetOptions(
        "c|config=s" => \$self->{config_file},
        "m|match=s@" => \$self->{matches},
        "f|follow"   => \$self->{follow},
        "h|help"     => \my $help,
    );

    if ($help) {
        die $self->usage;
    }

    if (@ARGV) {
        Carp::carp("$0 treat only one file") if @ARGV >= 2;
        $self->{file} = $ARGV[0];
    }
}

sub usage {
    my $self = shift;

    return <<"..."
Usage: $0 [options]

Options:
  -c,--config        Specify configuration file.
  -f,--follow        Behave like 'tail -f'.
  -h,--help          Show this message.
...
}

sub _load_config_file {
    my $self = shift;

    my $config_file = $self->{config_file};

    unless (-e $config_file) {
        Carp::croak("Config file '$config_file' is not existed");
    }

    my $conf = do $config_file or die "Can't load '$config_file' $!";
    unless (ref $conf && ref $conf eq 'HASH') {
        Carp::croak("Configration file should return HashRef");
    }

    $self->_validate_config($conf);
}

sub _validate_config {
    my ($self, $conf) = @_;

    my %config;
    while ( my ($name, $val) = each %{$conf} ) {
        my $param = {};

        unless (ref $val && ref $val eq 'HASH') {
            Carp::croak("Each parameter should be HashRef");
        }

        my $pattern = $val->{pattern};
        unless (defined $pattern) {
            Carp::croak("'$name' does not have 'pattern' paramter");
        }

        if (ref $pattern eq 'Regexp') {
            $param->{pattern} = $pattern;
        } elsif (!ref $pattern) {
            $param->{pattern} = qr/$pattern/;
        } else {
            Carp::croak("'pattern' should be 'Regexp' or String");
        }

        my $color = $val->{color};
        if (defined $color) {
            my @color_params;
            if (ref $color eq 'ARRAY') {
                @color_params = @{$val->{color}};
            } elsif ( !ref $color ) {
                @color_params = split /\s/, $val->{color};
            } else {
                Carp::croak("'color' paramter should be ArrayRef or String");
            }

            my @valid_colors = _validate_colors(@color_params);
            $param->{color} = "@valid_colors";
        }

        my $action = $val->{action};
        if (defined $action) {
            if ( ref $action eq 'CODE') {
                $param->{action} = $action;
            } elsif ( !ref $action ) {
                $param->{action} = _wrap_action_around_coderef($action);
            } elsif ( ref $action ne 'CODE' ) {
                Carp::croak("'action' paramter should be CodeRef or String");
            }
        }

        unless ($param->{color} || $param->{action}) {
            Carp::carp("'$name' has neither 'color' or 'action' parameter");
        }

        $config{$name} = $param;
    }

    $self->{config} = \%config;
}

sub _wrap_action_around_coderef {
    my @cmd = split /\s/, $_[0];
    return sub {
        exec @cmd;
    };
}

my %color_shortend = (
    bo => 'bold', it => 'italic', un => 'underline', rev => 'reverse',
    bli => 'blink',

    re => 'red', bl => 'blue', gr => 'green', ye => 'yellow',
    ma => 'magenta', cy => 'cyan', wh => 'white',

    ore => 'on_red', obl => 'on_blue', ogr => 'on_green', oye => 'on_yellow',
    oma => 'on_magenta', ocy => 'on_cyan', owh => 'on_white',
);

sub _validate_colors {
    my @color_attrs = @_;

    my @validate_colors;
    for my $attr (@color_attrs) {
        my $formal_attr = exists $color_shortend{$attr}
                                 ? $color_shortend{$attr} : $attr;

        unless (exists $Term::ANSIColor::ATTRIBUTES{$formal_attr}) {
            Carp::croak("'$formal_attr' is invalid color parameter");
        }

        push @validate_colors, $formal_attr;
    }

    return @validate_colors;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

ptrigger - trigger action by reading file or standard input

=head1 DESCRIPTION

See L<ptrigger>

=head1 AUTHOR

Syohei YOSHIDA E<lt>syohex@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2012- Syohei YOSHIDA

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
