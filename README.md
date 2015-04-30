# NAME

Log::Dispatch::Gelf - It's new $module

# SYNOPSIS

    use Log::Dispatch;

    my $sender = ... # e.g. RabbitMQ queue.
    my $log = Log::Dispatch->new(
        outputs => [ [
            'Gelf',
            min_level         => 'debug',
            additional_fields => { facility => __FILE__ },
            send_sub          => sub { $sender->send($_[0]) },
        ] ],
    );
    $log->info('It works');

# DESCRIPTION

Log::Dispatch::Gelf is Log::Dispatch plugin which formats the log message
according to Graylog's GELF Format and sends it using user-provided sender.

# LICENSE

Copyright (C) Avast Software.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Miroslav Tynovsky <tynovsky@avast.com>
