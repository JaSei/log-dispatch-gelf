requires 'perl', '5.008001';
requires 'Log::Dispatch';
requires 'Time::HiRes';
requires 'JSON';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

