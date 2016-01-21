package Log::Dispatch::Gelf;
use 5.010;
use strict;
use warnings;

our $VERSION = '1.0.0';

use base qw(Log::Dispatch::Output);
use Params::Validate qw(validate SCALAR HASHREF CODEREF);

use Sys::Hostname;
use JSON;
use Time::HiRes qw(time);

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    $self->_basic_init(@_);
    $self->_init(@_);

    return $self;
}

sub _init {
    my $self = shift;

    Params::Validate::validation_options(allow_extra => 1);
    my %p = validate(
        @_,
        {
            send_sub          => { type => CODEREF, optional => 1 },
            additional_fields => { type => HASHREF, optional => 1 },
            host              => { type => SCALAR,  optional => 1 },
            socket            => {
                type      => HASHREF,
                optional  => 1,
                callbacks => {
                    protocol_is_tcp_or_udp_or_default => sub {
                        my ($socket) = @_;

                        $socket->{protocol} //= 'udp';
                        die 'socket protocol must be tcp or udp' unless $socket->{protocol} =~ /^tcp|udp$/;
                    },
                    host_must_be_set => sub {
                        my ($socket) = @_;

                        die 'socket host must be set' unless exists $socket->{host} && length $socket->{host} > 0;
                    },
                    port_must_be_number_or_default => sub {
                        my ($socket) = @_;

                        $socket->{port} //= 12201;
                        die 'socket port must be integer' unless $socket->{port} =~ /^\d+$/;
                    }
                }
            }
        }
    );

    if (!defined $p{socket} && !defined $p{send_sub}) {
        die 'Must be set socket or send_sub';
    }

    $self->{host}              = $p{host}              // hostname();
    $self->{additional_fields} = $p{additional_fields} // {};
    $self->{send_sub}          = $p{send_sub};
    $self->{gelf_version}      = '1.1';

    if ($p{socket}) {
        $self->_create_socket($p{socket});
    }

    my $i = 0;
    $self->{number_of_loglevel}{$_} = $i++ for qw(emergency alert critical error warning notice info debug);

    return;
}

sub _create_socket {
    my ($self, $socket_opts) = @_;

    require IO::Socket::INET;
    my $socket = IO::Socket::INET->new(
        PeerAddr => $socket_opts->{host},
        PeerPort => $socket_opts->{port},
        Proto    => $socket_opts->{protocol},
    ) or die "Cannot create socket: $!";

    $self->{send_sub} = sub {
        my ($msg) = @_;

        $socket->send($msg);
    };
}

sub log_message {
    my ($self, %p) = @_;
    (my $short_message = $p{message}) =~ s/\n.*//s;

    my %additional_fields;
    while (my ($key, $value) = each %{ $self->{additional_fields} }) {
        $additional_fields{"_$key"} = $value;
    }

    my $log_unit = {
        version       => $self->{gelf_version},
        host          => $self->{host},
        short_message => $short_message,
        timestamp     => time(),
        level         => $self->{number_of_loglevel}{ $p{level} },
        full_message  => $p{message},
        %additional_fields,
    };

    $self->{send_sub}->(to_json($log_unit, { canonical => 1 }) . "\n");

    return;
}

1;
__END__

=encoding utf-8

=head1 NAME

Log::Dispatch::Gelf - Log::Dispatch plugin for Graylog's GELF format.

=head1 SYNOPSIS

    use Log::Dispatch;

    my $sender = ... # e.g. RabbitMQ queue.
    my $log = Log::Dispatch->new(
        outputs => [ 
            #some custom sender
            [
                'Gelf',
                min_level         => 'debug',
                additional_fields => { facility => __FILE__ },
                send_sub          => sub { $sender->send($_[0]) },
            ],
            #or send to graylog via TCP/UDP socket
            [
                'Gelf',
                min_level         => 'debug',
                additional_fields => { facility => __FILE__ },
                socket            => {
                    host     => 'graylog.server',
                    port     => 21234,
                    protocol => 'tcp',
                }
            ]
        ],
    );
    $log->info('It works');

=head1 DESCRIPTION

Log::Dispatch::Gelf is Log::Dispatch plugin which formats the log message
according to Graylog's GELF Format version 1.1 and sends it using user-provided
sender.

The constructor takes the following parameters in addition to the standard
parameters documented in L<Log::Dispatch::Output>:

=over

=item additional_fields

optional hashref of additional fields of the gelf message (no need to prefix
them with _, the prefixing is done automatically).

=item send_sub

mandatory sub for sending the message to graylog. It is triggered after the
gelf message is generated.

=back

=item socket

optional hashref create tcp or udp (default behavior) socket and set
C<send_sub> to sending via socket

=back

=head1 LICENSE

Copyright (C) Avast Software.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Miroslav Tynovsky E<lt>tynovsky@avast.comE<gt>

=cut

