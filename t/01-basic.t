#!perl
use strict;
use warnings;
use Data::Dumper;

use Test::More tests => 1;

use App::grep2mail;

*ARGV = *DATA;
my $rules = [
    { name => 'Error', re => [qr/\berror\b/, qr/\berrors\b/], recipients => ['foo', 'bar'] },
    { name => 'Warning', re => [qr/\bwarning\b/], recipients => ['baz','dev'] },
    { name => 'Empty', re => [], recipients => ['foo', 'dev']},
    { name => 'Unmatched', re => [], unmatched => 1, recipients => ['dev'], category => 'Dev errors' },
    { name => 'Keep Match', re => [qr/\[special-\d+\]/], recipients => ['match'], only_matching => 1 },
];

my $app = App::grep2mail->new(
    rules => $rules
);
my $res = $app->scan($rules);
my $expected = {
    'bar' => {'' => ["[error]     first line\n","[error]     third line\n", "[errors]    fifth line\n"]},
    'baz' => {'' => ["[warning]   second line\n"]},
    'foo' => {'' => ["[error]     first line\n","[error]     third line\n", "[errors]    fifth line\n"]},
    'dev' => {'' => ["[warning]   second line\n"], 'Dev errors' => ["[unmatched] fourth line\n"]},
    'match' => {'' => ["[special-999]"], },
};

is_deeply $res, $expected
    or diag Dumper $res;

__DATA__
[error]     first line
[warning]   second line
[error]     third line
[unmatched] fourth line
[errors]    fifth line
[special-999] sixth line