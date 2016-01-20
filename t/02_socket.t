use strict;
use warnings;

use Test::More;

use Log::Dispatch;
use JSON;
use Test::Exception;
use Mock::Quick;

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf', min_level => 'debug',
            ]
        ],
    );
}
qr/^Must be set socket or send_sub/, 'empty socket';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                'socket'  => {}
            ]
        ],
    );
}
qr/^socket host must be set/, 'undefined socket host';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                'socket'  => {
                    host => ''
                }
            ]
        ],
    );
}
qr/^socket host must be set/, 'empty socket host';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                'socket'  => {
                    host => 'test',
                    port => 'x',
                }
            ]
        ],
    );
}
qr/^socket port must be integer/, 'invalid socket port';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                'socket'  => {
                    host     => 'test',
                    port     => '111111',
                    protocol => 'invalid',
                }
            ]
        ],
    );
}
qr/^socket protocol must be tcp or udp/, 'invalid protocol';

my $LAST_LOG_MSG;
my $class_inet = qclass(
    -implement => 'IO::Socket::INET',
    new        => sub {
        my ($obj, %options) = @_;

        is_deeply(\%options, { PeerAddr => 'test', PeerPort => 12201, Proto => 'udp' }, 'connect opts');

        return bless {}, $obj;
    },
    send => sub {
        my ($self, $msg) = @_;

        $LAST_LOG_MSG = $msg;
    }
);

my $log = Log::Dispatch->new(
    outputs => [
        [
            'Gelf',
            min_level => 'debug',
            socket    => {
                host => 'test',
            }
        ]
    ],
);

$log->info("It works\nMore details.");

note("formatted message: $LAST_LOG_MSG");

my $msg = decode_json($LAST_LOG_MSG);
is($msg->{level},         6,                         'correct level info');
is($msg->{short_message}, 'It works',                'short_message correct');
is($msg->{full_message},  "It works\nMore details.", 'full_message correct');

done_testing(9);
