package Mosaic;

=head1 CLASS C<Mosaic>

Mosaic - base class for building video mosaic

=head2 METHODS

=cut

use 5.010;
use utf8;
use Moo;
use strictures 2;
use Carp;
use Try::Tiny;
use YAML::XS;
use Log::Log4perl;
use Term::ANSIColor;

our $VERSION = '0.11';

has 'configFile' => (
    is       => 'ro',
    required => 1
);

has 'config' => ( is => 'lazy' );

sub BUILD {
    my ($self) = @_;

    $self->{errorList} = ();
    $self->{source}    = {};    # temporary
    $self->{service}   = {};    # temporary
    $self->{output}    = {
        frameList   => [],
        serviceList => [],
        sourceList  => [],
        cmd         => []
    };

    return;
} ## end sub BUILD

sub _build_config {
    my ($self) = @_;

    my $configFile = $self->configFile;

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

=head3 compileConfig ( )

 Check the configuration file for correctness and build cross configuration.

=cut

sub compileConfig {
    my ($self) = @_;


    my $c = $self->config;
    say YAML::XS::Dump($self);

    # source defined?
    if ( exists $c->{source} ) {
        while ( my ( $sourceId, $value ) = each %{ $c->{source} } ) {
            $self->sourceAdd( $sourceId, $value );
        }
    } else {
        $self->error("no source defined");
    }

    # service defined?
    if ( exists $c->{service} ) {
        while ( my ( $serviceId, $value ) = each %{ $c->{service} } ) {
            $self->serviceAdd( $serviceId, $value );
        }
    } else {
        $self->error("no service defined");
    }

    # output defined?
    if ( exists $c->{output} ) {
        my $o      = $c->{output};
        my $output = $self->{output};

        if ( exists $o->{format} && $o->{format} =~ m/.*(\d+)x(\d).*/ ) {
            $output->{format} = {
                x => $1,
                y => $2
            };
        } else {
            $self->error( "no format defined [" . $o->{format} . "]" );
        }

        if ( exists $o->{size} && $o->{size} =~ m/.*?(\d+)x(\d+).*?/ ) {
            $output->{size} = {
                x => $1,
                y => $2
            };
        } else {
            $self->error("no size defined");
        }

        if ( exists $o->{destination} ) {
            $output->{destination} = $o->{destination};
        } else {
            $self->error("no destination defined");
        }

        if ( exists $o->{layout} ) {
            $output->{layout} = $o->{layout};
        }

    } ## end if ( exists $c->{output...})

    $self->buildScreen( $self->{output} );

    # cleanup the configuration
    $self->fixConfig();

    return scalar $self->{errorList};
} ## end sub compileConfig

=head3 error ( )

 Add message to list of errors.

=cut

sub error {
    my ( $self, $e ) = @_;

    push( @{ $self->{errorList} }, $e );
    say color('bold blue') . $e . color('reset');
} ## end sub error

=head3 sourceAdd ( )

 Add source definition to list

=cut

sub sourceAdd {
    my ( $self, $sourceId, $source ) = @_;

    if ( exists $source->{url} ) {
        $self->{source}{$sourceId}{url} = $source->{url};
    } else {
        $self->error("no url in source [$sourceId]");
    }
} ## end sub sourceAdd

=head3 serviceAdd ( )

 Add service definition to list

=cut

sub serviceAdd {
    my ( $self, $serviceId, $s ) = @_;

    my $service   = {};
    my $errorFlag = 0;

    if ( exists $s->{name} ) {
        $service->{name} = $s->{name};
    } else {
        $self->error("missing name for service [$serviceId]");
        $errorFlag += 1;
    }

    if ( exists $s->{source} ) {
        my $sourceId = $s->{source};
        if ( exists $self->{source}->{$sourceId} ) {
            $service->{source} = $sourceId;
        } else {
            $self->error("source [$sourceId] not found");
            $errorFlag += 1;
        }
    } else {
        $self->error("no source in service [$serviceId]");
        $errorFlag += 1;
    }

    if ( exists $s->{audio} && exists $s->{video} ) {
        $service->{audio} = $s->{audio};
        $service->{video} = $s->{video};
    } else {
        $self->error("no video/audio in service [$serviceId]");
        $errorFlag += 1;
    }

    if ( !$errorFlag ) {
        $self->{service}{$serviceId} = $service;
    }
} ## end sub serviceAdd

=head3 frameAdd ( )

 Add frame to output screen

=cut

sub frameAdd {
    my ( $self, $serviceId, $x, $y, $width, $height ) = @_;

    if ( exists $self->{service}{$serviceId} ) {
        my $frame = {
            serviceId => $serviceId,
            position  => {
                x => $x,
                y => $y
            },
            size => {
                width  => $width,
                height => $height
            }
        };
        push( @{ $self->{output}{frameList} }, $frame );

        # mark used services
        if ( exists $self->{service}{$serviceId}{count} ) {
            $self->{service}{$serviceId}{count} += 1;
        } else {
            $self->{service}{$serviceId}{count} = 1;
        }

        # mark used sources
        my $sourceId = $self->{service}{$serviceId}{source};
        if ( exists $self->{source}{$sourceId}{count} ) {
            $self->{source}{$sourceId}{count} += 1;
        } else {
            $self->{source}{$sourceId}{count} = 1;
        }
    } else {
        $self->error("service [$serviceId] not found");
    }
} ## end sub frameAdd

=head3 fixConfig ( )

 Clean unused sources, services and copy them to output.

=cut

sub fixConfig {
    my ($self) = @_;

    # clean
    while ( my ( $sourceId, $value ) = each %{ $self->{source} } ) {
        delete $self->{source}{$sourceId} if !exists $value->{count};
    }

    # order sources
    my $i = 0;
    foreach my $sourceId ( sort keys %{ $self->{source} } ) {
        $self->{source}{$sourceId}{order} = $i++;
    }

    # clean and fillup service
    while ( my ( $serviceId, $value ) = each %{ $self->{service} } ) {
        delete $self->{service}{$serviceId} if !exists $value->{count};
        delete $value->{count};
        $value->{source} = $self->{source}{ $value->{source} }{order};
    }

    # copy sources to output
    foreach my $sourceId ( sort( { $self->{source}{$a}{order} <=> $self->{source}{$b}{order} } keys %{ $self->{source} } ) ) {
        my $source = $self->{source}{$sourceId};
        push( @{ $self->{output}{sourceList} }, $source );
    }

    # copy service to output
    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( exists $frame->{serviceId} ) {
            say "**";
            my $serviceId = $frame->{serviceId};
            my $service   = $self->{service}{$serviceId};
            push( @{ $self->{output}{serviceList} }, $service );
            $frame->{name} = $service->{name};
        } ## end if ( exists $frame->{serviceId...})
    } ## end foreach my $frame ( @{ $self...})

    delete $self->{source};
    delete $self->{servcie};

} ## end sub fixConfig

=head3 report ( )

 Print configuration.

=cut

sub report {
    my ($self) = @_;
    my $line = "";

    $line .= "Sources:\n";
    foreach my $source ( @{ $self->{output}{sourceList} } ) {
        $line .= sprintf( "  %2i  %s\n", $source->{order}, $source->{url} );
    }

    $line .= "Components:\n";
    foreach my $service ( @{ $self->{output}{serviceList} } ) {
        $line .= sprintf( "  %s\n", $service->{name} );
        foreach my $component ( 'video', 'audio' ) {
            my $source = $service->{source};
            my $id     = $service->{$component};
            my $tag    = $component =~ /video/ ? 'v' : 'a';
            $line .= sprintf( "   %2i:%s:%i %s\n", $source, $tag, $id, $component );
        } ## end foreach my $component ( 'video'...)
    } ## end foreach my $service ( @{ $self...})

    $line .= "Output:\n";
    $line .= "  " . $self->{output}{format}{x} . "x" . $self->{output}{format}{y} . "\n";
    $line .= "  " . $self->{output}{size}{x} . "x" . $self->{output}{size}{y} . "\n";
    $line .= "  " . $self->{output}{destination} . "\n";

    $line .= "  Frames:\n";
    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        $line .= "    " . $frame->{name} . "\n";
        $line .= sprintf(
            "      %4ix%4i-%4ix%4i\n",
            $frame->{position}{x},
            $frame->{position}{y},
            $frame->{size}{width},
            $frame->{size}{height}
        );
    } ## end foreach my $frame ( @{ $self...})

    #   say YAML::XS::Dump( $self->{output});
    return $line;

} ## end sub report

=head3 buildScreen()

 Build the output screen from frames.

=cut

sub buildScreen {
    my ( $self, $output ) = @_;

    if ( ref $output->{layout} ne 'ARRAY' ) {
        die "unsupported layout configuration";
    }

    say( "Output pixel size: ", $output->{size}{x},   "x", $output->{size}{y} );
    say( "Output layout    : ", $output->{format}{x}, "x", $output->{format}{y} );

    my $i         = 0;
    my $maxFrames = $output->{format}{x} * $output->{format}{y};

    my $line = "";

    while ( $i < $maxFrames ) {

        # get service from list
        my $serviceId = $output->{layout}[$i];

        # calculate column x row from $i
        my $col = $i % $output->{format}{x};
        my $row = int( $i / $output->{format}{x} );
        $line .= "\n" if $col == 0;
        $line .= sprintf( "[%7s    %2ix%2i] ", $serviceId // 'undef', $col, $row );

        # and coordinates/width
        my $x      = 0;
        my $y      = 0;
        my $width  = 0;
        my $height = 0;

        # add frame to screen
        $self->frameAdd( $serviceId, $x, $y, $width, $height ) if $serviceId;

#        $self->frameClockAdd( $x, $y, $width, $height);

    } continue {
        $i += 1;
    }

    say $line;
} ## end sub buildScreen

=head3 buildCmd()

 Build commandline for starting the ffmpeg . This includes all specified input sources .

=cut

sub buildCmd {
    my ($self) = @_;

    my @cmd = ();

    push( @cmd, "ffmpeg -y -re" );

    # sources
    foreach my $source ( @{ $self->{output}{sourceList} } ) {
        push( @cmd, "-i " . $source->{url} );
    }

    # map
    foreach my $service ( @{ $self->{output}{serviceList} } ) {
        foreach my $component ( 'video', 'audio' ) {
            my $source = $service->{source};
            my $id     = $service->{$component};
            my $tag    = $component =~ /video/ ? 'v' : 'a';
            push( @cmd, "-map " . $source . ":" . $tag . ":" . $id );
        } ## end foreach my $component ( 'video'...)
    } ## end foreach my $service ( @{ $self...})

    return join( " ", @cmd );
} ## end sub buildCmd

1;
