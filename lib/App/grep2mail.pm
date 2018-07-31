package App::grep2mail;
use 5.010; # we might use named captures
use strict;
use warnings;

use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

use MIME::Lite;

use Exporter 'import';

our $VERSION = '0.01';
our @EXPORT = qw(scan distribute_results);

=head1 NAME

App::grep2mail - functionality for the grep2mail program

=head1 SYNOPSIS

  use App::grep2mail 'scan', 'distribute_results';

  my $config = {
    { name => 'Error', re => [qr/\berror\b/, qr/\berrors\b/],
      recipients => ['foo@example.com', 'bar@example.com'] },
    { name => 'Unmatched', re => [], unmatched => 1,
      recipients => ['dev@example.com']},
  };

  my $results = scan( $config );
  distribute_results( $results );

=cut

sub keep_line( $rule, $recipients ) {
    my $group = $rule->{category} || '';
    for my $recipient (@{ $rule->{recipients}}) {
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
    my ($unmatched) = grep { $_->{unmatched} } @$rules;

    while( <> ) {
        my $matched;
        RULE: for my $rule (@$rules) {
            RE: for my $re (@{ $rule->{re}}) {
                if( /$re/ ) {
                    keep_line( $rule, $recipients );
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

1;