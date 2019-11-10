package Mosaic;

=head1 CLASS C<Mosaic>

Mosaic - base class for building video mosaic

=head2 METHODS

=cut

use 5.010;
use utf8;
use Moo;
use strictures 2;
use IO::Socket;
use Carp;
use Try::Tiny;
use YAML::XS;
use Log::Log4perl;

our $VERSION = '0.11';

has 'configFile' => (
    is       => 'ro',
    required => 1
);

has 'config' => ( is => 'lazy' );

sub BUILD {
    my ($self) = @_;

    return;
}

sub _build_config {
    my ($self) = @_;

    my $configFile = $self->configFile;

    say "-->",$configFile;

    $configFile = glob($configFile);

    my $configuration;

    # check if file exists
    if ( $configFile and -e $configFile ) {

        $configuration = YAML::XS::LoadFile($configFile);

        # return only the subtree
        if ( ref $configuration eq 'HASH' ) {

            # add the path of the configuration file to the configuration itself
            $configuration->{configfile} = $configFile;

            return $configuration;
        } else {
            croak("No configuration data found in: $configFile (incorrect format!)");
        }
    } else {
        croak("File not found: $configFile");
    }
} ## end sub _build_config

=head3 validateConfig ( )

 Check the configuration file for correctnes.

=cut

sub validateConfig {
    my ($self) = @_;

    my $configuration = $self->config;

    return 1;
    return 0;
} ## end sub validateConfig

=head3 report ( )

 Build report ...

=cut

sub report {
    my ($self) = @_;
}

=head3 buildCmd ( )

 Build commandline for starting the ffmpeg. This includes all specified input sources.

=cut

sub buildCmd {
    my ($self) = @_;
}

1;
