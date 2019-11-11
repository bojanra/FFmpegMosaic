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
use Mosaic::Input;

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

    say "-->", $configFile;

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

    my $c         = $self->config;
    my @errorList = ();
    my $source    = {};

    # source defined?
    if ( exists $c->{source} ) {
        foreach my $input ( sort keys %{ $c->{source} } ) {
            try {
                $source->{$input} = Mosaic::Input->new( $c->{source}{$input} );
            }
            catch {
                if (m/.+"(.+)".+: (.+) at \(.*/) {
                    push( @errorList, "$1 $2" );
                } else {
                    push( @errorList, $_ );
                }
            } ## end catch
        } ## end foreach my $input ( sort keys...)
    } else {
        push( @errorList, "missing specification of source" );
    }

    # service defined?

    # output defined?
    #
    say join( "\n", @errorList);

    return scalar @errorList == 0;
} ## end sub validateConfig

=head3 report ( )

 Build report ...

=cut

sub report {
    my ($self) = @_;

    return YAML::XS::Dump( $self->config );
}

=head3 buildCmd ( )

 Build commandline for starting the ffmpeg. This includes all specified input sources.

=cut

sub buildCmd {
    my ($self) = @_;
}

1;
