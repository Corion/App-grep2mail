#!perl
use 5.010; # we might use named captures
use strict;
use warnings;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Getopt::Long;
use YAML qw( Load LoadFile );
use Data::Dumper;

use App::grep2mail;

GetOptions(
    'f|config=s' => \my $config_file,
    'from=s'     => \my $mail_from,
    'set=s'      => \my @values,
);

my $config = Load(<<'YAML');
---
from: cron@example.com
grep:
  - name: "errors"
    re:
      - "error"
      - "fatal"
    recipient:
      - developer@example.com
      - admin@example.com
    category: "Errors"
  - name: "warnings"
    re:
      - "warning"
    recipient:
      - developer@example.com
  - name: "Unknown input"
    unmatched: 1
    recipient:
      - developer@example.com
  - name: "Send to other process"
    recipient:
      - "| irc-post --channel #cat-pictures"
      - "| slack-post --channel #cat-pictures"
      - "| twitter-post --channel #cat-pictures"
    re:
      - "\\bcat.*?\.jpg\b"
  - name: "Send to file"
    recipient:
      - ">> log/file1.log"
YAML

$mail_from ||= $config->{from};

my $app = App::grep2mail->new(
    rules     => $config->{grep},
    mail_from => $mail_from,
);

# XXX Update config from @values
$app->scan();
$app->flush();

=head1 SYNOPSIS

=cut

__END__

=head1 CONFIGURATION ENTRIES

=over 4

=item C<name>

    name: "Cats"

The name of the rule, highly convenient for debugging and documentation

=item C<re>

    re:
      - "\\bcats?\\b"
      - "\\bdogs?\\b"

A single regular expression or a list of regular expressions used for matching.
Note that backslashes need to be escaped for YAML.

=item C<recipient>

    recipient:
        - me@example.com

A list of recipients. A recipient can be either an email address or a string
conforming to the specification of L<open>. If it is the latter, Perl will
launch the process or file and pipe all matching output to that handle.

Send output to a specific file:

    recipient:
        - ">> matches.txt"

Launch a process with the output from this rule:

    recipient:
        - "| send-to-twitter"

=back

=head1 CONFIG FILE

  - name: "errors"
    re:
      - "error"
      - "fatal"
    recipient:
      - developer@example.com
      - admin@example.com
    group: "Errors"
  - name: "warnings"
    re:
      - "warning"
    recipient:
      - developer@example.com
  - unmatched: 1
    recipient:
      - developer@example.com
  # Not yet supported
  - name: "output summary"
    section_start:
      - "OUTPUT SUMMARY"
    section_end:
      - "^$"
    recipient:
      - operations@example.com
  - name: "Weird log entry"
    match:
      - re: "error happened"
        context-before: 5
        context-after: 2
    recipient:
      - pager@example.com

=cut