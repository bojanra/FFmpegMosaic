package Mosaic::Input;

=head1 CLASS C<Mosaic::Input>

Input - mosaic input class

=head2 METHODS

=cut

use 5.010;
use utf8;
use Moo;
use strictures 2;
use IO::Socket;
use Carp;
use Try::Tiny;
use Log::Log4perl;

has 'source' => (
    is       => 'ro',
    required => 1,
    isa => sub {
        croak "must be file or udp" unless $_[0] =~ m!^(udp|file)://!;
    }
);

sub BUILD {
    my ($self) = @_;


    return;
} ## end sub BUILD



1;
