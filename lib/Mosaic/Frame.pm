package Mosaic::Frame;

=head1 CLASS C<Mosaic::Frame>

Mosaic::Frame - frame class for building video mosaic

=head2 METHODS

=cut

use 5.010;
use utf8;
use Moo;
use strictures 2;
use IO::Socket;
use Try::Tiny;
use Log::Log4perl;

sub BUILD {
    my ($self) = @_;

    return;
} ## end sub BUILD

1;
