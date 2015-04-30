package Log::Dispatch::Gelf;
use 5.008001;
use strict;
use warnings;

our $VERSION = '0.1.0';

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

    Params::Validate::validation_options( allow_extra => 1 );
    my %p = validate(
        @_,
        {
            send_sub          => { type => CODEREF                },
            additional_fields => { type => HASHREF, optional => 1 },
            host              => { type => SCALAR , optional => 1 },
        }
    );

    $self->{host}               = $p{host} // hostname();
    $self->{additional_fields}  = $p{additional_fields} // {};
    $self->{send_sub}           = $p{send_sub};
    $self->{gelf_version}       = '1.1';

    my $i = 0;
    $self->{number_of_loglevel}{$_} = $i++
        for qw(debug info notice warning error critical alert emergency);

    return
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

    $self->{send_sub}->(encode_json($log_unit));

    return
}

1;
__END__

=encoding utf-8

=head1 NAME

Log::Dispatch::Gelf - It's new $module

=head1 SYNOPSIS

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

=head1 DESCRIPTION

Log::Dispatch::Gelf is Log::Dispatch plugin which formats the log message
according to Graylog's GELF Format and sends it using user-provided sender.

=head1 LICENSE

Copyright (C) Avast Software.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Miroslav Tynovsky E<lt>tynovsky@avast.comE<gt>

=cut

