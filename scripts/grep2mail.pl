#!perl -w
use 5.010; # we might use named captures
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Getopt::Long;
use YAML qw( Load LoadFile );
use Data::Dumper;
use MIME::Lite;

GetOptions(
    'f|config=s' => \my $config_file,
    'from=s'     => \my $mail_from,
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
my $rules = $config->{grep};
$mail_from ||= $config->{from};

my ($unmatched) = grep { $_->{unmatched} } @$rules;

sub keep_line( $rule, $recipients ) {
    my $group = $rule->{category} || '';
    for my $recipient (@{ $rule->{recipient}}) {
        push @{$recipients->{ $recipient }->{ $group }}, $_;
    };
}

# The current implementation loops over each group and each RE for each
# line of input. This is not horrible, but it means that each RE will be
# executed for each line of input and each input line will be scanned multiple
# times.
#
# First optimization stage, put all regular expressions into one large
# regular expression, to stay within the RE engine for each line:
#
# my $combined = join "|", map { my $expr = join "|", map { qr/(?:$_)/ } @{$_->{re}}; qr/(?<$_->{name}>(?=.*?$expr))/ } @rules;
# if( /$combined/ ) {
#     my($leftmost) = keys %+;
# }
#
# This tells us all REs that match this line, and by extension all rules that
# we should handle.
#
# Later, build a regular expression that tells us whether a line matches at all
# my $combined = join "|", map { my $expr = join "|", map { qr/(?:$_)/ } @{$_->{re}}; qr/(?<$_->{name}>$expr)/ } @rules;
# if( /$combined/ ) {
#     my($leftmost) = keys %+;
# }
# If we match that, either we have leftmost-non-overlapping matches and use that
# directly, or we have an indication whether to try the rules up to the matched
# group. This will be a second optimization stage.

# Maybe consider moving this to App::Ack modules
# Especially the file handling over blindly using <> would be nice

sub scan( $rules, $recipients={} ) {
    while( <> ) {
        my $matched;
        RULE: for my $rule (@$rules) {
            RE: for my $re (@{ $rule->{re}}) {
                if( /$re/ ) {
                    keep_line( $rule );
                    $matched++;
                    # last RE
                    # Maybe add a strategy here to try all matches instead of
                    # only using the first match
                    last RULE;
                };
            };
        }
        if( ! $matched && $unmatched ) {
            keep_line( $unmatched, $recipients );
        };
    }
    $recipients
}

sub sendmail($mail_from, $recipient, $body) {
    my $msg = MIME::Lite->new(
        From     => $mail_from,
        To       => $recipient,
        #Cc       => 'some@other.com, some@more.com',
        Subject  => 'Helloooooo, nurse!',
        Data     => $body,
        #Type     => 'image/gif',
        #Encoding => 'base64',
        #Path     => 'hellonurse.gif'
    );
    $msg->send; # send via default
}

sub distribute_results( $recipients ) {
    for my $r (sort keys %$recipients) {
        my $body;
        for my $section (sort keys %{ $recipients->{$r} }) {
            $body .= join "\n", "$section\n", @{ $recipients->{$r}->{$section} }, "";
        };

        if( $r =~ /^[>|]/ ) {
            # We should signal this while reading the configuration, not when
            # trying to send the results
            die "File / pipe output is not yet supported";
        } else {
            # Send SMPT mail
            # my $mail_from = $r;
            sendmail( "Hmmm", $r, $body );
        };
    }
}

my $recipients = scan( $rules );
distribute_results( $recipients );

=head1 SYNOPSIS

=cut

__END__

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