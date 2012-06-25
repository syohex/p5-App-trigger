package App::trigger;
use strict;
use warnings;

use Carp ();
use POSIX ();
use Getopt::Long ();
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
    while (waitpid(-1, &POSIX::WNOHANG) > 0) {
        ;
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

sub run {
    my $self = shift;

    $self->_load_config_file;

    my $fh;
    if ($self->{file}) {
        unless (-e $self->{file}) {
            Carp::croak("$self->{file} is not exist.");
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
    _wait_children_finished();
}

sub _match_line {
    my ($self, $conf, $orig_line, $line_ref) = @_;

    my $regexp = $conf->{regexp};
    if ($orig_line =~ $regexp) {
        if ($conf->{color}) {
            my $color = Term::ANSIColor::color($conf->{color});
            my $reset = Term::ANSIColor::color('reset');
            ${$line_ref} =~ s{($regexp)}{${color}${1}${reset}};
        }

        if ($conf->{action}) {
            my $pid = fork;
            Carp::croak "Can't fork: $!" unless defined $pid;

            if ($pid == 0) {
                local %SIG;

                # Child process
                $conf->{action}->();
                exit 0;
            } else {
                # Parent process
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

    my $default_config = File::Spec->catfile($ENV{HOME}, ".ptrigger");
    my $config_file = $self->{config} || $default_config;

    unless (-e $config_file) {
        Carp::croak("Configuration files '$config_file' is not exist");
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

        my $regexp = $val->{regexp};
        unless (defined $regexp) {
            Carp::croak("'$name' does not have 'regexp' paramter");
        }

        if (ref $regexp eq 'Regexp') {
            $param->{regexp} = $regexp;
        } elsif (!ref $regexp) {
            $param->{regexp} = qr/$regexp/;
        } else {
            Carp::croak("'regexp' should be 'Regexp' or String");
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

            for my $color_param (@color_params) {
                unless (exists $Term::ANSIColor::ATTRIBUTES{$color_param}) {
                    Carp::croak("'$color_param' is invalid color parameter");
                }
            }

            $param->{color} = "@color_params";
        }

        my $action = $val->{action};
        if (defined $action) {
            if ( ref $action eq 'CODE') {
                $param->{action} = $action
            } elsif ( !ref $action ) {
                my @cmd = split /\s/, $action;
                $param->{action} = sub {
                    exec @cmd;
                };
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
