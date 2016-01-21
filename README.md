[![Build Status](https://travis-ci.org/avast/log-dispatch-gelf.svg?branch=master)](https://travis-ci.org/avast/log-dispatch-gelf)
# NAME

Log::Dispatch::Gelf - Log::Dispatch plugin for Graylog's GELF format.

# SYNOPSIS

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

# DESCRIPTION

Log::Dispatch::Gelf is Log::Dispatch plugin which formats the log message
according to Graylog's GELF Format version 1.1 and sends it using user-provided
sender.

The constructor takes the following parameters in addition to the standard
parameters documented in [Log::Dispatch::Output](https://metacpan.org/pod/Log::Dispatch::Output):

- additional\_fields

    optional hashref of additional fields of the gelf message (no need to prefix
    them with \_, the prefixing is done automatically).

- send\_sub

    mandatory sub for sending the message to graylog. It is triggered after the
    gelf message is generated.

- socket

    optional hashref create tcp or udp (default behavior) socket and set
    `send_sub` to sending via socket

# LICENSE

Copyright (C) Avast Software.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Miroslav Tynovsky &lt;tynovsky@avast.com>

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 184:

    '=item' outside of any '=over'
