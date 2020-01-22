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
use Image::Magick;
use Math::Trig;
use POSIX qw(strftime);
use File::Copy;
use Data::Dumper;


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
    $self->{topLayer} = {};

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

        if ( exists $o->{format} && $o->{format} =~ m/.*?(\d+)x(\d).*?/ ) {
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

        if ( exists $o->{error} ) {
            $output->{error} = $o->{error};
        } else {
            $self->error("error no dif");
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
        if ( exists $s->{audio1} ) {
            $service->{audio1} = $s->{audio1};
        }
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

    my $audioWidth  = int( $width * 0.01 );
    my $audioHeight = $height - 30;
    my $audioX      = $x + $width - $audioWidth * 2 - 4;
    my $audioY      = $y;

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
            },
            audioPosition => {
                x => $audioX,
                y => $audioY,
            },
            audioSize => {
                width  => $audioWidth,
                height => $audioHeight
            }
        };
        push( @{ $self->{output}{frameList} }, $frame );

        # mark service in use
        if ( exists $self->{service}{$serviceId}{count} ) {
            $self->{service}{$serviceId}{count} += 1;
        } else {
            $self->{service}{$serviceId}{count} = 1;
        }
    } elsif( $serviceId eq "clock"){

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

    } else {
        $self->error("service [$serviceId] not found");
    }
} ## end sub frameAdd

=head3 fixConfig ( )

 Clean unused sources, services and copy them to output.

=cut

sub fixConfig {
    my ($self) = @_;

    # mark sources in use
    while ( my ( $serviceId, $value ) = each %{ $self->{service} } ) {
        my $sourceId = $value->{source};
        $self->{source}{$sourceId}{count} = 1;
    }

    # delete unused sources
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
        next if !exists $service->{name};
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
        if ( $frame->{serviceId} ne "clock" ) {
            $line .= "    " . $frame->{name} . "\n";
            $line .= sprintf(
                "     v:%4ix%4i-%4ix%4i\n     a:%4ix%4i-%4ix%4i\n",
                $frame->{position}{x},      $frame->{position}{y},      $frame->{size}{width},
                $frame->{size}{height},     $frame->{audioPosition}{x}, $frame->{audioPosition}{y},
                $frame->{audioSize}{width}, $frame->{audioSize}{height}
            );
        } ## end if ( $frame->{serviceId...})
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

    my $i         = 0;
    my $maxFrames = $output->{format}{x} * $output->{format}{y};

    my $line = "";

    my $spacingX = $output->{format}{x} > 1 ? int( $output->{size}{x} * 0.02 / ( $output->{format}{x} - 1 ) ) : 0;
    my $spacingY = int( $spacingX * 9 / 16 );
    my $edgeX    = int( $output->{size}{x} * 0.01 / 2 );
    my $edgeY    = int( $edgeX * 9 / 16 );

    while ( $i < $maxFrames and $i < scalar( @{ $output->{layout} } ) ) {

        # get service from list
        my $serviceId = $output->{layout}[$i];

        # calculate column x row from $i
        my $col = $i % $output->{format}{x};
        my $row = int( $i / $output->{format}{y} );
        $line .= "\n" if $col == 0;
        $line .= sprintf( "[%7s    %2ix%2i] ", $serviceId // 'undef', $col, $row );

        # and coordinates/width

        my $width = int( $output->{size}{x} * ( 1 - 0.02 - 0.01 ) / $output->{format}{x} );
        my $height = int( $width * 9 / 16 );

        my $x = $col * ( $width + $spacingX ) + $edgeX;
        my $y = $row * ( $height + $spacingY ) + $edgeY;

        # add frame to screen
        if ( $serviceId !~ /clock/i ) {
            $self->frameAdd( $serviceId, $x, $y, $width, $height );
        }
    } continue {
        $i += 1;
    }

    return $line;
} ## end sub buildScreen

=head3 buildCmd( $pretty)

 Build commandline for starting the ffmpeg . This includes all specified input sources .
 Prettyprint if set $pretty.

=cut

sub buildCmd {
    my ($self, $pretty) = @_;

    my @cmd = ();

    push( @cmd, "ffmpegX" );
    push( @cmd, "-y" );
    push( @cmd, "-re" );

    # sources
    foreach my $source ( @{ $self->{output}{sourceList} } ) {
        push( @cmd, "-i \'" . $source->{url} . "\'" );
    }

    my $topLayerInput = $self->config->{output}{topLayer};
    push( @cmd, "-loop 1" );
    push( @cmd, "-f image2" );
    push( @cmd, "-r 25" );
    push( @cmd, "-i \'$topLayerInput\'" );

    # map
    my $input = 0;
    foreach my $service ( @{ $self->{output}{serviceList} } ) {
        next if !exists $service->{name};
        foreach my $component ( 'video', 'audio', 'audio1' ) {
            next if !exists $service->{$component};
            my $source = $service->{source};
            my $id     = $service->{$component};
            my $tag    = $component =~ /video/ ? 'v' : 'a';

            push( @cmd, "-map $source:$tag:$id" );
        } ## end foreach my $component ( 'video'...)
        $input++;
    } ## end foreach my $service ( @{ $self...})

    push( @cmd, "-map " . $input . ":v" );
    push( @cmd, "-filter_complex" );

    # imput scale
    push( @cmd, "\"nullsrc=1920x1080, lutrgb=126:126:126 [base];" );

    $input = 0;

    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} ne "clock" ) {
            my $scale;
            my $service = $frame->{serviceId};
            my $source  = $self->{service}{$service}{source};

            my $id     = $self->{service}{$service}{video};
            my $tag    = 'v';
            my $width  = $frame->{size}{width};
            my $height = $frame->{size}{height};

            $scale = "[$source:$tag:$id] setpts=PTS-STARTPTS, scale=" . $width . "x" . $height . " [$source:v];";

            push( @cmd, $scale );

            foreach my $component ( 'audio', 'audio1' ) {
                next if !exists $self->{service}{$service}{$component};

                $id  = $self->{service}{$service}{$component};
                $tag = 'a';
                my $audioWidth  = $frame->{audioSize}{width};
                my $audioHeight = $frame->{audioSize}{height};

                $scale =
                    "[$source:$tag:$id] showvolume=f=0.5:c=0x00ffff:b=4:w=$audioHeight:h=$audioWidth:o=v:ds=log:dm=2:p=1, format=yuv420p [$source.$id:a];";

                push( @cmd, $scale );
            } ## end foreach my $component ( 'audio'...)
            $input++;
        } ## end if ( $frame->{serviceId...})
    } ## end foreach my $frame ( @{ $self...})
    push( @cmd, "[" . $input . ":v] setpts=PTS-STARTPTS, scale=1920x1080 [topLayer];" );

    # parameters
    push( @cmd, "[base]" );

    $input = 0;
    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} ne "clock" ) {
            my $parameter;
            my $service = $frame->{serviceId};
            my $source  = $self->{service}{$service}{source};

            my $x = $frame->{position}{x};
            my $y = $frame->{position}{y};
            $parameter = "[$source:v] overlay=shortest=1: x=$x: y=$y";

            push( @cmd, $parameter );

            my $audioN = 0;
            foreach my $component ( 'audio1', 'audio' ) {

                next if !exists $self->{service}{$service}{$component};
                my $id          = $self->{service}{$service}{$component};
                my $audioWidth  = $frame->{audioSize}{width};
                my $audioHeight = $frame->{audioSize}{height};

                my $audioX = $frame->{audioPosition}{x} - ( $audioWidth * 2 + 6 ) * $audioN;
                my $audioY = $frame->{audioPosition}{y};
                $parameter = "[$source.$id:layer]; [$source.$id:layer][$source.$id:a] overlay=shortest=1:x=$audioX: y=$audioY ";

                push( @cmd, $parameter );
                $audioN++;
            } ## end foreach my $component ( 'audio1'...)
            push( @cmd, "[$source:layer]; [$source:layer]" );
        } ## end if ( $frame->{serviceId...})
    } ## end foreach my $frame ( @{ $self...})

    push( @cmd, "[topLayer] overlay=shortest=1: x=0: y=0\"" );

    push( @cmd, "-strict experimental" );
    push( @cmd, "-vcodec libx264" );      # choose output codec
    push( @cmd, "-b:v 4M" );
    push( @cmd, "-minrate 3M" );
    push( @cmd, "-maxrate 3M" );
    push( @cmd, "-bufsize 6M" );
    push( @cmd, "-preset ultrafast" );
    push( @cmd, "-profile:v high" );
    push( @cmd, "-level 4.0" );
    push( @cmd, "-an" );
    push( @cmd, "-threads 0" );           # allow multithreading
    push( @cmd, "-f mpegts udp://".$self->config->{output}{destination}."?pkt_size=1316");

# -f segment -segment_list /var/www/html/playlist.m3u8 -segment_list_flags +live -segment_time 10 /var/www/html/out%03d.ts");

    if( $pretty) {
        my @list = ();
        my $line = "";
        foreach (@cmd) {
        }
        return join( "\n", @list);
    } else {
        return join( " ", @cmd );
    }
} ## end sub buildCmd


##################################### TOP LAYER #############################

=head3 buildTlay()

Build commandline top layer .

=cut

sub buildTlay {
    my ($self) = @_;

    # default values
    my $fontScaleX = 0.6;
    my $fontScaleY = 1;
    my $fond       = "/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf";
    my $fh;

    # izdelava osnovne plasti
    my $upperLayer;
    my $pictureFormat = "1920x1080";

    $upperLayer = Image::Magick->new();
    $upperLayer->Set( size => $pictureFormat );
    $upperLayer->ReadImage('canvas:transparent');


    # Pisanje podatkov na zadnjo plast

    my $input = 0;

    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} ne "clock" ) {

            my $titleName           = $frame->{name};
            my $videoFramePositionX = $frame->{position}{x};
            my $videoFramePositionY = $frame->{position}{y};
            my $videoFrameWidth     = $frame->{size}{width};
            my $videoFrameHeight    = $frame->{size}{height};

            # Izračun kordinat

            # TITLE
            my $titleFontSize     = 30;
            my $titleRowTopOffset = 10;
            my $titleOffsetX      = int( ( $videoFrameWidth - ( length($titleName) * $titleFontSize * $fontScaleX ) ) / 2 );
            my $titleX            = $videoFramePositionX + $titleOffsetX;
            my $titleY            = $videoFramePositionY + $titleRowTopOffset;

            # MSG
            my $msgFontSize        = 30;
            my $msgRowBottomOffset = 0;
            my $msgRowHight        = int( $msgFontSize * $fontScaleY + $msgRowBottomOffset );
            my @BR                 = ( "2,56 Mb", "2,56 Mb", "2,56 Mb", "2,56 Mb", "2,56 Mb" );
            my @MC    = ( "239.239.100.100", "239.239.100.200", "239.239.100.300", "239.239.100.200", "239.239.100.300" );
            my @CC    = ( ">56001", ">56002", ">56003", ">56002", ">56003" );
            my $msgX  = $videoFramePositionX;
            my $msgY  = $videoFramePositionY + $videoFrameHeight - $msgRowHight;
            my $msgX2 = $msgX + $videoFrameWidth;
            my $msgY2 = $msgY + $msgFontSize;

            #ERROR
            my $errorFontSize = $self->{output}{error}{font};
            my $errorX1       = $videoFramePositionX;
            my $errorY1       = $videoFramePositionY;
            my $errorX2       = $videoFramePositionX + $videoFrameWidth;
            my $errorY2       = $videoFramePositionY + $videoFrameHeight;
            my $errorTextX    = int( ( 1920 - $videoFrameWidth ) / 2 - $videoFramePositionX );
            my $errorTextY    = int( ( 1080 - $videoFrameHeight ) / 2 - $videoFramePositionY );

            # Urejanje ImegeMagic

            # TITLE
            $upperLayer->Annotate(
                undercolor => '#e8ddce',
                fill       => 'black',
                font       => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize  => $titleFontSize,
                geometry   => "+$titleX+$titleY",
                gravity    => 'northwest',
                text       => $titleName
            );

            # MSG
            $upperLayer->Draw(
                fill      => 'white',
                points    => "$msgX,$msgY $msgX2,$msgY2",
                gravity   => 'northwest',
                primitive => 'rectangle'
            );

            $upperLayer->Annotate(
                fill      => 'black',
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $msgFontSize,
                geometry  => "+$msgX+$msgY",
                gravity   => 'northwest',
                text      => $BR[$input]
            );

            $upperLayer->Annotate(
                fill      => 'black',
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $msgFontSize,
                geometry  => "-" . int( ( 1920 - $videoFrameWidth ) / 2 - $msgX ) . "+$msgY",
                gravity   => 'north',
                text      => $MC[$input]
            );

            $upperLayer->Annotate(
                fill      => 'black',
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $msgFontSize,
                geometry  => "+" . ( 1920 - $videoFrameWidth - $msgX ) . "+$msgY",
                gravity   => 'northeast',
                text      => $CC[$input]
            );

            # ERROR
            if ( $self->{output}{error}{position} == $input ) {
                $upperLayer->Draw(
                    fill      => 'rgba(255, 0, 0, 0.5)',
                    points    => "$errorX1,$errorY1 $errorX2,$errorY2",
                    gravity   => 'northwest',
                    primitive => 'rectangle'
                );

                $upperLayer->Annotate(
                    fill      => 'black',
                    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize => $errorFontSize,
                    geometry  => "-$errorTextX-$errorTextY",
                    gravity   => 'center',
                    text      => "ERROR"
                );
            } ## end if ( $self->{output}{error...})
            $input++;
        } ## end if ( $frame->{serviceId...})
    } ## end foreach my $frame ( @{ $self...})


    $upperLayer->Write('top_layer/upper_layer.png');

    print "Upper layer generated\n";


    ############################################### URA #####################################################


    my $fixedClockLayer = Image::Magick->new();
    $fixedClockLayer->Read('top_layer/upper_layer.png');

    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} eq "clock" ) {
            my $x      = $frame->{position}{x};
            my $y      = $frame->{position}{y};
            my $width  = $frame->{size}{width};
            my $height = $frame->{size}{height};


            print "$x, $y, $width, $height\n";

            # Urino središče
            my $clockCenterX = int( $x + $width / 2 );
            my $clockCenterY = int( $y + $height / 2 );

            # Krog
            my $circleRadius      = $height * 0.9 / 2;
            my $circleX           = $clockCenterX;
            my $circleY           = $clockCenterY;
            my $circleOffSetEdgeX = $clockCenterX;
            my $circleOffSetEdgeY = $clockCenterY - $circleRadius;

            # Pozicija številk
            my $clockCenterFromCenterX = int( 1920 / 2 - $clockCenterX );
            my $clockCenterFromCenterY = int( 1080 / 2 - $clockCenterY );

            my $numberOffSetCenter = $circleRadius * 0.85;

            my $number12X = $clockCenterFromCenterX;
            my $number12Y = $clockCenterFromCenterY + $numberOffSetCenter;
            my $number3X  = $clockCenterFromCenterX - $numberOffSetCenter;
            my $number3Y  = $clockCenterFromCenterY;
            my $number6X  = $clockCenterFromCenterX;
            my $number6Y  = $clockCenterFromCenterY - $numberOffSetCenter;
            my $number9X  = $clockCenterFromCenterX + $numberOffSetCenter;
            my $number9Y  = $clockCenterFromCenterY;

            # Pozicija datuma
            my $dateOffSetCenter = int( $circleRadius / 2 );
            my $dateX            = $clockCenterFromCenterX;
            my $dateY            = $clockCenterFromCenterY - $dateOffSetCenter;

            # Velikost kazalcev
            my $kazalecDolzinaSecond = int( $circleRadius * 0.75 );
            my $kazalecDolzinaMinute = int( $circleRadius * 0.75 );
            my $kazalecDolzinaHour   = int( $circleRadius * 0.6 );

            my $scaleLine1      = int( $circleRadius * 0.85 );
            my $scaleLine2      = int( $circleRadius * 0.95 );
            my $smallScaleLine1 = int( $circleRadius * 0.90 );

            my $thicknesScaleLine      = int( $circleRadius * 0.02 );
            my $thicknesSmallScaleLine = int( $circleRadius * 0.01 );
            my $thicknessCircle        = int( $circleRadius * 0.04 );

            my $smallCircleOffSetEdgeY = $clockCenterY - $kazalecDolzinaSecond;

            # Barve

            my $circleColor       = '#e8ddce';
            my $circleStrokeColor = '#27284d';
            my $scaleColor        = '#27284d';
            my $kazalecColor      = '#27284d';
            my $secentColor       = '#a53e4f';

            ##### Izdelava ozadja ure #####

            $fixedClockLayer->Draw(
                fill        => $circleColor,
                stroke      => $circleStrokeColor,
                strokewidth => $thicknessCircle,
                points      => "$clockCenterX,$clockCenterY $circleOffSetEdgeX,$circleOffSetEdgeY",
                primitive   => 'circle'
            );


            # črtice med številkami na uri
            my @smallScaleLine = ( 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 );

            for ( my $i = 0 ; $i < 4 ; $i++ ) {

                for ( my $j = 0 ; $j < 12 ; $j++ ) {

                    my $smallScaleLineN = $smallScaleLine[$j] + $i * 15;

                    if ( $smallScaleLineN % 5 == 0 ) {

                        my $scaleLineY1 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine1 );
                        my $scaleLineX1 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine1 );

                        my $scaleLineY2 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );
                        my $scaleLineX2 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );

                        $fixedClockLayer->Draw(
                            fill        => $scaleColor,
                            stroke      => $scaleColor,
                            points      => "$scaleLineX1,$scaleLineY1 $scaleLineX2,$scaleLineY2", # kordinate točk x1, y1, x2, y1
                            strokewidth => $thicknesScaleLine,
                            primitive   => 'line'
                        );

                    } else {

                        my $smallScaleLineY1 =
                            $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $smallScaleLine1 );
                        my $smallScaleLineX1 =
                            $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $smallScaleLine1 );

                        my $scaleLineY2 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );
                        my $scaleLineX2 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );

                        $fixedClockLayer->Draw(
                            fill   => $scaleColor,
                            stroke => $scaleColor,
                            points =>
                                "$smallScaleLineX1,$smallScaleLineY1 $scaleLineX2,$scaleLineY2",  # kordinate točk x1, y1, x2, y1
                            strokewidth => $thicknesSmallScaleLine,
                            primitive   => 'line'
                        );
                    } ## end else [ if ( $smallScaleLineN ...)]
                } ## end for ( my $j = 0 ; $j < ...)
            } ## end for ( my $i = 0 ; $i < ...)

            # Številke na uri

            my $font = $circleRadius * 0.2;
            if ( $font eq "" ) { $font = int( $circleRadius * 0.2 ) }

            $fixedClockLayer->Annotate(
                fill      => $scaleColor,
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $font,
                geometry  => "-$number12X-$number12Y",
                gravity   => 'center',
                text      => "12"
            );

            $fixedClockLayer->Annotate(
                fill      => $scaleColor,
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $font,
                geometry  => "-$number3X-$number3Y",
                gravity   => 'center',
                text      => "3"
            );

            $fixedClockLayer->Annotate(
                fill      => $scaleColor,
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $font,
                geometry  => "-$number6X-$number6Y",
                gravity   => 'center',
                text      => "6"
            );

            $fixedClockLayer->Annotate(
                fill      => $scaleColor,
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $font,
                geometry  => "-$number9X-$number9Y",
                gravity   => 'center',
                text      => "9"
            );


            print "fixed clock layer generiran\n";

            $fixedClockLayer->Write('top_layer/fixed_clock_layer.png');


            ##### KAZALCI IN DATUM #####

            my $second;
            my $minute;
            my $minuteL = "0";
            my $hour;
            my $hourL = "0";
            my $date;
            my $dateL = "0";

            my @kazalecSecondY;
            my @kazalecSecondX;
            my $SecondY;
            my $SecondX;
            my $thicknessSecond     = int( $circleRadius * 0.02 );
            my $kazalecSecendCircle = $clockCenterY - int( $circleRadius * 0.06 );

            my @kazalecMinuteY;
            my @kazalecMinuteX;
            my $MinuteY;
            my $MinuteX;
            my $thicknessMinute = int( $circleRadius * 0.04 );

            my @kazalecHourY;
            my @kazalecHourX;
            my $HourY;
            my $HourX;
            my $thicknessHour = int( $circleRadius * 0.06 );

            my $activeLayer = Image::Magick->new();
            $activeLayer->Read("top_layer/fixed_clock_layer.png");

            for ( my $s = 0 ; $s <= 720 ; $s++ ) {
                push( @kazalecSecondY, ( $clockCenterY - int( sin( pi / 2 - ( $s * pi / 30 ) ) * $kazalecDolzinaSecond ) ) );
                push( @kazalecSecondX, ( $clockCenterX + int( cos( pi / 2 - ( $s * pi / 30 ) ) * $kazalecDolzinaSecond ) ) );

                push( @kazalecMinuteY, ( $clockCenterY - int( sin( pi / 2 - ( $s * pi / 30 ) ) * $kazalecDolzinaMinute ) ) );
                push( @kazalecMinuteX, ( $clockCenterX + int( cos( pi / 2 - ( $s * pi / 30 ) ) * $kazalecDolzinaMinute ) ) );

                push( @kazalecHourY, ( $clockCenterY - int( sin( pi / 2 - ( $s * pi / 360 ) ) * $kazalecDolzinaHour ) ) );
                push( @kazalecHourX, ( $clockCenterX + int( cos( pi / 2 - ( $s * pi / 360 ) ) * $kazalecDolzinaHour ) ) );
            } ## end for ( my $s = 0 ; $s <=...)
            my $t = 0;
            while (1) {

                $activeLayer->Draw(
                    fill      => $circleColor,
                    points    => "$clockCenterX,$clockCenterY $circleOffSetEdgeX,$smallCircleOffSetEdgeY",
                    primitive => 'circle'
                );

                # Določanje časovnih spremenljivk
                $second = strftime "%S", localtime;
                $minute = strftime "%M", localtime;
                $hour   = strftime "%I", localtime;
                $date   = strftime "%F", localtime;

                if ( $hour == 12 ) { $hour = 0; }

                $SecondY = $kazalecSecondY[$second];
                $SecondX = $kazalecSecondX[$second];

                $MinuteY = $kazalecMinuteY[$minute];
                $MinuteX = $kazalecMinuteX[$minute];

                $HourY = $kazalecHourY[ $hour * 60 + $minute ];
                $HourX = $kazalecHourX[ $hour * 60 + $minute ];

                # DATUM
                $activeLayer->Annotate(
                    fill      => $scaleColor,
                    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize => $font,
                    geometry  => "-$dateX-$dateY",
                    gravity   => 'center',
                    text      => "$date"
                );

                # Urni kazalec
                $activeLayer->Draw(
                    fill        => $kazalecColor,
                    stroke      => $kazalecColor,
                    points      => "$clockCenterX,$clockCenterY $HourX,$HourY",
                    strokewidth => $thicknessHour,
                    primitive   => 'line'
                );

                # Minutni kazalec
                $activeLayer->Draw(
                    fill        => $kazalecColor,
                    stroke      => $kazalecColor,
                    points      => "$clockCenterX,$clockCenterY $MinuteX,$MinuteY",
                    strokewidth => $thicknessMinute,
                    primitive   => 'line'
                );


                # Sekundni kazalec
                $activeLayer->Draw(
                    fill        => $secentColor,
                    stroke      => $secentColor,
                    points      => "$clockCenterX,$clockCenterY $SecondX,$SecondY",
                    strokewidth => $thicknessSecond,
                    primitive   => 'line'
                );

                $activeLayer->Draw(
                    fill      => $secentColor,
                    points    => "$clockCenterX,$clockCenterY $clockCenterX,$kazalecSecendCircle",
                    primitive => 'circle'
                );


                $activeLayer->Write('top_layer/active_layer1.png');

                # Premaknemo active_layer1.png v active_layer.png
                move( 'top_layer/active_layer1.png', 'top_layer/active_layer.png' );

                my $t = time();
                while ( time() == $t ) { }
            } ## end while (1)
        } else {
            $fixedClockLayer->Write('top_layer/active_layer1.png');
            move( 'top_layer/active_layer1.png', 'top_layer/active_layer.png' );
        }

    } ## end foreach my $frame ( @{ $self...})
} ## end sub buildTlay

1;
