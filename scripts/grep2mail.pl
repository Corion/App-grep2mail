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
    'f|config=s' => \my $config,
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
      - "| mailx -s \"Some more data\" nobody@example.com"
  - name: "Send to file"
    recipient:
      - "> log/file1.log"
YAML
my $rules = $config->{grep};
$mail_from ||= $config->{from};

my %recipients;
my ($unmatched) = grep { $_->{unmatched} } @$rules;

sub keep_line( $rule ) {
    my $group = $rule->{category} || '';
    for my $recipient (@{ $rule->{recipient}}) {
        push @{$recipients{ $recipient }->{ $group }}, $_;
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
# Later, build a regular expression that tells us whether a line matches at all
# my $combined = join "|", map { my $expr = join "|", map { qr/(?:$_)/ } @{$_->{re}}; qr/(?<$_->{name}>$expr)/ } @rules;
# if( /$combined/ ) {
#     my($leftmost) = keys %+;
# }
# If we match that, either we have leftmost-non-overlapping matches and use that
# directly, or we have an indication whether to try the rules up to the matched
# group. This will be a second optimization stage.

while( <> ) {
    my $matched;
    RULE: for my $rule (@$rules) {
        RE: for my $re (@{ $rule->{re}}) {
            if( /$re/ ) {
                keep_line( $rule );
                $matched++;
                # last RE
                last RULE;
            };
        };
    }
    if( ! $matched && $unmatched ) {
        keep_line( $unmatched );
    };
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

for my $r (sort keys %recipients) {
    my $body;
    for my $section (sort keys %{ $recipients{$r} }) {
        $body .= join "\n", "$section\n", @{ $recipients{$r}->{$section} }, "";
    };
    
    if( $r =~ /^[>|]/ ) {
        die "File / pipe output is not yet supported";
    } else {
        # Send SMPT mail
        sendmail( $mail_form, $r, $body );
    };
}

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