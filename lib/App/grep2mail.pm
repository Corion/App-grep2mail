package App::grep2mail;
use 5.010; # we might use named captures
use strict;
use warnings;
use Moo;

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

This should maybe named C<grepfan> because it implements fanout for grep,
and not just mailout.

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

has 'recipients' => (
    is => 'ro',
    default => sub { +{} },
);

has 'rules' => (
    is => 'ro',
    default => sub { [] },
);

has 'mail_from' => (
    is => 'ro',
);

sub keep_line( $self, $rule, $recipients=$self->recipients ) {
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

sub scan( $self, $rules=$self->rules, $recipients=$self->recipients ) {
    my ($unmatched) = grep { $_->{unmatched} } @$rules;

    while( <> ) {
        my $matched;
        RULE: for my $rule (@$rules) {
            RE: for my $re (@{ $rule->{re}}) {
                if( /$re/ ) {
                    $self->keep_line( $rule, $recipients );
                    $matched++;
                    # last RE
                    # Maybe add a strategy here to try all matches instead of
                    # only using the first match
                    last RULE;
                };
            };
        }
        if( ! $matched && $unmatched ) {
            $self->keep_line( $unmatched, $recipients );
        };
    }
    $recipients
}

sub sendmail( $self, $mail_from, $subject, $recipient, $body) {
    my $msg = MIME::Lite->new(
        From     => $mail_from,
        To       => $recipient,
        #Cc       => 'some@other.com, some@more.com',
        Subject  => $subject,
        Data     => $body,
        #Type     => 'image/gif',
        #Encoding => 'base64',
        #Path     => 'hellonurse.gif'
    );
    $msg->send; # send via default
}

# Call this when the input stream has ended to flush out all the stored
# data
sub flush( $self, $recipients=$self->recipients ) {
    for my $r (sort keys %$recipients) {
        my @body;
        my @subject;
        for my $section (sort keys %{ $recipients->{$r} }) {
            push @subject, $section;
            push @body, $section, "", @{ $recipients->{$r}->{$section} }, "";
        };

        if( $r =~ /^[>|]/ ) {
            # We should signal this while reading the configuration, not when
            # trying to send the results
            die "File / pipe output is not yet supported";
        } else {
            # Send SMPT mail
            my $subject = "grep2mail: extracted lines for " . join ', ', @subject;
            sendmail( $self->mail_from, $subject, $r, \@body );
        };
    }
}

1;