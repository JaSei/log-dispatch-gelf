use strict;
use Test::More;

use Log::Dispatch;
use JSON;

my $LAST_LOG_MSG;

my $log = Log::Dispatch->new(
    outputs => [ [
        'Gelf',
        min_level         => 'debug',
        additional_fields => { facility => __FILE__ },
        send_sub          => sub { $LAST_LOG_MSG = $_[0] },
    ] ],
);

$log->info("It works\nMore details.");

note "formatted message: $LAST_LOG_MSG";

my $msg = decode_json($LAST_LOG_MSG);
is($msg->{level}, 'info', 'correct level');
is($msg->{short_message}, 'It works', 'short_message correct');
is($msg->{full_message}, "It works\nMore details.", 'full_message correct');
is($msg->{_facility}, __FILE__, 'facility correct');
ok($msg->{host}, 'host is there');
ok($msg->{timestamp}, 'timestamp is there');
ok($msg->{version}, 'version is there');

done_testing();
