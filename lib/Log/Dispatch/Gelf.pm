package Log::Dispatch::Gelf;
use 5.010;
use strict;
use warnings;

our $VERSION = '1.0.0';

use base qw(Log::Dispatch::Output);
use Params::Validate qw(validate SCALAR HASHREF CODEREF BOOLEAN);

use Sys::Hostname;
use JSON;
use Time::HiRes qw(time);
use IO::Compress::Gzip qw(gzip $GzipError);
use Math::Random::MT qw(irand);

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
            compress          => { type => BOOLEAN, optional => 1 },
            chunked           => {
                type => SCALAR,
                optional => 1,
                callbacks => {
                    check_valid_size => sub {
                        my ($chunked) = @_;

                        die 'chunked must be "wan", "lan", or a positive integer'
                            unless $chunked =~ /^(wan|lan|\d+)$/i;

                        if ( lc($1) eq 'wan' ) {
                            $self->{chunked} = 1420;
                        }
                        elsif ( lc($1) eq 'lan' ) {
                            $self->{chunked} = 8154;
                        }
                        else {
                            $self->{chunked} = $1;
                        }
                    },
                },
            },
            socket            => {
                type      => HASHREF,
                optional  => 1,
                callbacks => {
                    protocol_is_tcp_or_udp_or_default => sub {
                        my ($socket) = @_;

                        $socket->{protocol} //= 'udp';
                        die 'socket protocol must be tcp or udp' unless $socket->{protocol} =~ /^(tcp|udp)$/;
                    },
                    host_must_be_set => sub {
                        my ($socket) = @_;

                        die 'socket host must be set' unless exists $socket->{host} && length $socket->{host} > 0;
                    },
                    port_must_be_number_or_default => sub {
                        my ($socket) = @_;

                        $socket->{port} //= 12201;
                        die 'socket port must be integer' unless $socket->{port} =~ /^\d+$/;
                    },
                }
            }
        }
    );

    if (!defined $p{socket} && !defined $p{send_sub}) {
        die 'Must be set socket or send_sub';
    }

    if ( defined $p{socket}
         && defined $p{chunked}
         && $p{socket}{protocol} ne 'udp'
    ) {
        die 'chunked only applicable to udp';
    }

    $self->{host}              = $p{host}              // hostname();
    $self->{additional_fields} = $p{additional_fields} // {};
    $self->{send_sub}          = $p{send_sub};
    $self->{gelf_version}      = '1.1';

    if ($p{socket}) {
        my $socket = $self->_create_socket($p{socket});

        $self->{send_sub} = sub {
            my ($msg) = @_;

            $msg = $self->_compress($msg) if $p{compress};
            $socket->send($_) foreach $self->_chunks($msg);
        };
    }

    my $i = 0;
    $self->{number_of_loglevel}{$_} = $i++ for qw(emergency alert critical error warning notice info debug);

    return;
}

sub _compress {
    my ($self, $msg) = @_;

    my $msgz;
    gzip \$msg => \$msgz
      or die "gzip failed: $GzipError";

    return $msgz;
}

sub _chunks {
    my ($self, $msg) = @_;

    if ( defined $self->{chunked}
         && length $msg > $self->{chunked}
    ) {
        my @chunks;
        while (length $msg) {
            push @chunks, substr $msg, 0, $self->{chunked}, '';
        }

        my $n_chunks = scalar @chunks;
        die 'Message too big' if $n_chunks > 128;

        my $magic          = pack('C*', 0x1e,0x0f); # Chunked GELF magic bytes
        my $message_id     = pack('L*', irand(),irand());
        my $sequence_count = pack('C*', $n_chunks);

        my @chunks_w_header;
        my $sequence_number = 0;
        foreach my $chunk (@chunks) {
           push @chunks_w_header,
              $magic
              . $message_id
              . pack('C*',$sequence_number++)
              . $sequence_count
              . $chunk;
        }

        return @chunks_w_header;
    }
    else {
         return ($msg);
    }
}

sub _create_socket {
    my ($self, $socket_opts) = @_;

    require IO::Socket::INET;
    my $socket = IO::Socket::INET->new(
        PeerAddr => $socket_opts->{host},
        PeerPort => $socket_opts->{port},
        Proto    => $socket_opts->{protocol},
    ) or die "Cannot create socket: $!";

    return $socket;
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

=item chunked

optional scalar. An integer specifying the chunk size or the special
string values 'lan' or 'wan' corresponging to 8154 or 1420 respectively.

Chunking is only applicable to UDP connections.

=item compress

optional scalar. If a true value the message will be gzipped with
IO::Compress::Gzip.

=item send_sub

mandatory sub for sending the message to graylog. It is triggered after the
gelf message is generated.


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
