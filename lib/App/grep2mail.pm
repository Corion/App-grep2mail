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

Currently, it separates out each section instead of mixing all the sections
together as they are encountered in the input streams.

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
# Keys for the rules are
# name
# recipients
# re
# only_matching

has 'mail_from' => (
    is => 'ro',
);

sub keep_line( $self, $rule, $recipients=$self->recipients ) {
    my $group = $rule->{category} || '';
    for my $recipient (@{ $rule->{recipients}}) {
        my $value = $rule->{ only_matching } ? $& : $_;
        if( ! $recipients->{ $recipient }) {
            if( $recipient =~ /^[|>]/ ) {
                # Something that Perl can treat as filehandle:
                open $recipients->{ $recipient }, $recipient
                    or die "Couldn't open '$recipient': $!";
            } else {
                # Otherwise, it's a mail address and we accumulate in a hash
                # per section
                $recipients->{ $recipient } = { $group => [] };
            };
        };
        if( 'HASH' eq ref($recipients->{ $recipient }) ) {
            # mail
            push @{$recipients->{ $recipient }->{ $group }}, $value;
        } else {
            # a filehandle
            print { $recipients->{ $recipient } } $value;
        }
    };
}

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

        if( ref $recipients->{ $r } eq 'HASH' ) {
            # Send SMPT mail
            my $subject = "grep2mail: extracted lines for " . join ', ', @subject;
            sendmail( $self->mail_from, $subject, $r, \@body );
        } else {
            # Close our filehandle
            close { $recipients->{ $r } };
        };
    }
}

1;