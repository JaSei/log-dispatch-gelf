use strict;
use warnings;

use Test::More;

use Log::Dispatch;
use JSON;
use Test::Exception;
use Mock::Quick;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

my $CHUNKED_MESSAGE;
my $class_inet = qclass(
    -implement => 'IO::Socket::INET',
    new        => sub {
        my ($obj, %options) = @_;
        $CHUNKED_MESSAGE = undef;
        return bless {}, $obj;
    },
    send => sub {
        my ($self, $msg) = @_;
        
        my $magic = pack('C*', 0x1e, 0x0f);
        
        my @msg = split //, $msg;
        
        my $msg_magic   = join '', splice @msg, 0, 2;
        my $msg_id      = unpack('LL', join '', splice @msg, 0, 8);
        my $msg_seq_no  = unpack('C', shift @msg);
        my $msg_seq_cnt = unpack('C', shift @msg);

        if ( $msg_magic eq $magic ) {
            die "sequence_number > sequence count - should not happen"
              if $msg_seq_no > $msg_seq_cnt;

            die "message_id <> last message_id - should not happen"
              if defined $self->{last_msg_id} && $self->{last_msg_id} ne $msg_id;

            $self->{last_msg_id} = $msg_id;

            $CHUNKED_MESSAGE .= join '', @msg;

        }
        else {
            die "message not chunked";
        }
    }
);

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                chunked  => 'WAN',
                'socket'  => {
                    host     => 'test',
                    protocol => 'tcp',
                }
            ]
        ],
    );
}
qr/chunked only applicable to udp/, 'invalid protocol for chunking';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                chunked   => 'xxx',
                'socket'  => {
                    host     => 'test',
                    protocol => 'udp',
                }
            ]
        ],
    );
}
qr/chunk size must be "lan", "wan", a positve integer, or 0 \(no chunking\)/, 'invalid chunked value';

throws_ok {
    Log::Dispatch->new(
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                chunked   => '-1',
                'socket'  => {
                    host     => 'test',
                    protocol => 'udp',
                }
            ]
        ],
    );
}
qr/chunk size must be "lan", "wan", a positve integer, or 0 \(no chunking\)/, 'invalid integer';

new_ok ( 'Log::Dispatch', [
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                chunked  => 'WAN',
                socket    => {
                    host => 'test',
                }
            ]
        ]
    ]
);

new_ok ( 'Log::Dispatch', [
        outputs => [
            [
                'Gelf',
                min_level => 'debug',
                chunked  => 'lan',
                socket    => {
                    host => 'test',
                }
            ]
        ]
    ]
);

my $log = Log::Dispatch->new(
    outputs => [
        [
            'Gelf',
            min_level => 'debug',
            chunked  => 4,
            socket    => {
                host => 'test',
            }
        ]
    ],
);

$log->info("Uncompressed - chunked\nMore details.");

note("formatted message: $CHUNKED_MESSAGE");

my $msg = decode_json($CHUNKED_MESSAGE);

is($msg->{level},         6,                                       'correct level info');
is($msg->{short_message}, 'Uncompressed - chunked',                'short_message correct');
is($msg->{full_message},  "Uncompressed - chunked\nMore details.", 'full_message correct');

$log = Log::Dispatch->new(
    outputs => [
        [
            'Gelf',
            min_level  => 'debug',
            compress => 1,
            chunked  => 4,
            socket    => {
                host => 'test',
            }
        ]
    ],
);

$log->info("Compressed - chunked\nMore details.");

my $output;
gunzip \$CHUNKED_MESSAGE => \$output
    or die "gunzip failed: $GunzipError\n";
note("formatted message: $output");

$msg = decode_json($output);

is($msg->{level},         6,                                     'correct level info');
is($msg->{short_message}, 'Compressed - chunked',                'short_message correct');
is($msg->{full_message},  "Compressed - chunked\nMore details.", 'full_message correct');

done_testing(11);
