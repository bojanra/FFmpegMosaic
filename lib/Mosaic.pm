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

#    say $self->report();

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
    my ( $self, $serviceId, $x, $y, $width, $height, $stackX, $stackY, $stackWidth, $stackHeight ) = @_;

    my $audioWidth  = int( $stackWidth * 0.015 );
    my $audioHeight = int( $stackHeight - $self->{output}{size}{y}*0.03 );
    my $audioX      = $stackX + $stackWidth - $audioWidth*2-4;
    my $audioY      = $stackY;

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
            },
            stack => {
                x => $stackX,
                y => $stackY,
                width  => $stackWidth,
                height => $stackHeight,
            }
        };
        push( @{ $self->{output}{frameList} }, $frame );

        # mark service in use
        if ( exists $self->{service}{$serviceId}{count} ) {
            $self->{service}{$serviceId}{count} += 1;
        } else {
            $self->{service}{$serviceId}{count} = 1;
        }
    } elsif ( $serviceId eq "clock" ) {

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
            stack => {
                width    => $stackWidth,
                height   => $stackHeight,
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
        if( exists $value->{count}) {
            my $sourceId = $value->{source};
            $self->{source}{$sourceId}{count} = 1;
        }
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
        if( exists $value->{count}) {
            $value->{source} = $self->{source}{ $value->{source} }{order};
        } else {
            delete $self->{service}{$serviceId};
        }
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
            $line .= sprintf( "   %2i:%s:%s %s\n", $source, $tag, $id, $component );
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

    #my $spacingX = $output->{format}{x} > 1 ? int( $output->{size}{x} * 0.02 / ( $output->{format}{x} - 1 ) ) : 0;
    #my $spacingY = int( $spacingX * 9 / 16 );
    my $edgeX    = int( $output->{size}{x} * 0.05 / ($output->{format}{x} + 1) );
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

        my $width = int( $output->{size}{x} / $output->{format}{x} );
        my $height = int( $width * 9 / 16 );

        my $x = $col * $width;
        my $y = $row * $height;

        my $stackX = $edgeX - $edgeX*$col / ($output->{format}{x});
        my $stackY = $edgeY - $edgeY*$row / ($output->{format}{y});
        my $stackWidth  = int( $output->{size}{x}*0.95 / $output->{format}{x} );
        my $stackHeight = int( $stackWidth * 9 / 16 );


        # add frame to screen
        $self->frameAdd( $serviceId, $x, $y, $width, $height, $stackX, $stackY, $stackWidth, $stackHeight );
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
    my ( $self, $pretty ) = @_;

    my @cmd = ();
    my $firstLevel  = "";
    my @secondLevel = ();
    my @thirdLevel  = ();
    

    push( @cmd, "ffmpegY" );
    push( @cmd, "-y" );

    # sources
    foreach my $source ( @{ $self->{output}{sourceList} } ) {
        push( @cmd, "-i \'" . $source->{url} . "\'" );
    }

    push( @cmd, "-filter_complex" );

    # imput scale
    push( @cmd, "\"" );
    $firstLevel = join( " \\\n", @cmd );
    @cmd = ();

    my $nFrame = 0;
    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} ne "clock" ) {
            my $scale;
            my $service = $frame->{serviceId};
            my $source  = $self->{service}{$service}{source};

            my $id     = $self->{service}{$service}{video};
            my $tag    = 'v';
            my $width  = $frame->{size}{width};
            my $height = $frame->{size}{height};
            my $stackWidth  = $frame->{stack}{width};
            my $stackHeight = $frame->{stack}{height};


            $scale = "nullsrc=" . $width . "x" . $height . ", lutrgb=126:126:126 [$source.$id:base]; [$source:$tag:#$id] setpts=PTS-STARTPTS, scale=" . $stackWidth . "x" . $stackHeight . " [$source.$id:v];";

            push( @cmd, $scale );

            foreach my $component ( 'audio', 'audio1' ) {
                next if !exists $self->{service}{$service}{$component};

                $id  = $self->{service}{$service}{$component};
                $tag = 'a';
                my $audioWidth  = $frame->{audioSize}{width};
                my $audioHeight = $frame->{audioSize}{height};

                $scale =
                    "[$source:$tag:#$id] showvolume=f=0.5:c=0x00ffff:b=4:w=$audioHeight:h=$audioWidth:o=v:ds=log:dm=2:p=1, format=yuv420p [$source.$id:a];";

                push( @cmd, $scale );
            } ## end foreach my $component ( 'audio'...)
        } ## end if ( $frame->{serviceId...})
        $nFrame++;
        if ( $nFrame == $self->{output}{format}{x} ) { 
            push( @secondLevel, join( " \\\n", @cmd ) );
            @cmd = ();
            $nFrame = 0;
        }
        
    } ## end foreach my $frame ( @{ $self...})

    # parameters
    #push( @cmd, "[base]" );

    $nFrame = 0;    #number of frames
    my $stack = "";
    my @stackLayer  = ();
    foreach my $frame ( @{ $self->{output}{frameList} } ) {
        if ( $frame->{serviceId} ne "clock" ) {
            my $parameter;
            my $service       = $frame->{serviceId};
            my $source        = $self->{service}{$service}{source};
            my $id            = $self->{service}{$service}{video};
            my $stackPosition = $frame->{stack}{position};

            my $x = $frame->{stack}{x};
            my $y = $frame->{stack}{y};
            $parameter = "[$source.$id:base][$source.$id:v] overlay=shortest=1: x=$x: y=$y";

            push( @cmd, $parameter );

            foreach my $component ( 'audio1', 'audio' ) {

                next if !exists $self->{service}{$service}{$component};
                my $id = $self->{service}{$service}{$component};

                my $width = $frame->{size}{width};

                my $audioWidth  = $frame->{audioSize}{width};
                my $audioHeight = $frame->{audioSize}{height};

                my $audioX = $frame->{audioPosition}{x};
                my $audioY = $frame->{audioPosition}{y};
                $parameter = "[$source.$id:layer]; [$source.$id:layer][$source.$id:a] overlay=shortest=1:x=$audioX: y=$audioY";

                push( @cmd, $parameter );
            } ## end foreach my $component ( 'audio1'...)
            push( @cmd, "[$source.$id:layer];" );

            $stack .= "[$source.$id:layer]";
            
        } ## end if ( $frame->{serviceId...})
        $nFrame++;
        if ( $nFrame == $self->{output}{format}{x} ) { ## if element last image in row
            push( @thirdLevel, join( " \\\n", @cmd ) );
            push( @stackLayer, $stack);
            $stack = "";
            @cmd = ();
            $nFrame = 0;
        }
         
    } ## end foreach my $frame ( @{ $self...})

    my $nOut = 0;
    my @outLevel = ();

    while ( $nOut < $self->{output}{format}{y} ) {
        push ( @outLevel, $firstLevel );
        push ( @outLevel, $secondLevel[$nOut] );
        push ( @outLevel, $thirdLevel[$nOut]) ;
        push ( @outLevel, $stackLayer[$nOut] . "hstack=inputs=" . $self->{output}{format}{x} . "\"" );
        push ( @outLevel, "-f mpegts udp://172.30.0.91:500".$nOut."?pkt_size=1316" );
        
        my $out = join( " \\\n", @outLevel );
        my $mosaicFFmpeg = "FFmpeg$nOut";
        open( my $fh, '>', $mosaicFFmpeg );
        print( $fh "#!/bin/bash\n" );
        print( $fh $out );
        close($fh);
        @outLevel = ();
        $nOut++;
    }
    
    @cmd = "";
    push( @cmd, "ffmpegY" );
    push( @cmd, "-y" );
    $stack = "";
    # sources
    my $input = 0;
    while ( $input < $self->{output}{format}{y} ) {
        push( @cmd, "-i \'udp://172.30.0.91:500".$input."\'" );
        $stack .= "[$input:v]";
        $input++;
    }

    my $topLayerInput = $self->config->{output}{topLayer};
    push( @cmd, "-loop 1" );
    push( @cmd, "-f image2" );
    push( @cmd, "-r 1" );                    # refresh rate for image
    push( @cmd, "-i \'$topLayerInput\'" );

    push( @cmd, "-filter_complex" );

    # imput scale
    push( @cmd, "\"" );
    push( @cmd, "[" . $input . ":v] setpts=PTS-STARTPTS, scale=" . $self->{output}{size}{x} . "x" . $self->{output}{size}{y} . " [topLayer];" );

    push( @cmd,
              $stack
            . "vstack=inputs="
            . $self->{output}{format}{y}
            . "[v];[v][topLayer] overlay=shortest=1: x=0: y=0 [v1];[v1]split=2[out1][out2]\"" );

    push( @cmd, "-strict experimental" );
    push( @cmd, "-vcodec libx264" );                                                              # choose output codec
    push( @cmd, "-b:v 4M" );
    push( @cmd, "-maxrate 8M" );
    push( @cmd, "-bufsize 6M" );
    push( @cmd, "-preset ultrafast" );
    #push( @cmd, "-profile:v high" );
    #push( @cmd, "-level 4.0" );
    #push( @cmd, "-an" );
    #push( @cmd, "-threads 0" );  
 # allow multithreading
    push( @cmd, "-map '[out1]' -f mpegts udp://" . $self->config->{output}{destination} . "?pkt_size=1316" );
    push( @cmd, "-map '[out2]' -f segment -segment_wrap 10 -segment_list /var/www/html/playlist.m3u8 -segment_list_flags +live -segment_time 1 -g 10 /var/www/html/out%03d.ts");

    if ($pretty) {
        my @list = ();
        my $line = "";
        foreach (@cmd) {
        }
        return join( "\n", @list );
    } else {
        return join( " \\\n", @cmd );
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
    my $font       = "/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf";
    my $fh;

    # Pisanje podatkov na zadnjo plast
    my $topLayer;
    my $input = 0;
    my $t = 0;
    while (1) {
        $topLayer = Image::Magick->new();
        $topLayer->Set( size => "" . $self->{output}{size}{x} . "x" . $self->{output}{size}{y} . "" );
        $topLayer->ReadImage('canvas:transparent');

        foreach my $frame ( @{ $self->{output}{frameList} } ) {
            if ( $frame->{serviceId} ne "clock" ) {

                my $videoFramePositionX = $frame->{position}{x} + $frame->{stack}{x};
                my $videoFramePositionY = $frame->{position}{y} + $frame->{stack}{y};
                my $videoFrameWidth     = $frame->{stack}{width};
                my $videoFrameHeight    = $frame->{stack}{height};

                # Izračun kordinat

                # TITLE
                my $titleName         = $frame->{name};
                my $titleFontSize     = $self->{output}{size}{y}*0.03;
                my $titleRowTopOffset = $self->{output}{size}{y}*0.01;
                my $titleX            = int( $videoFramePositionX + $videoFrameWidth/2 - $self->{output}{size}{x}/2 );
                my $titleY            = $videoFramePositionY + $titleRowTopOffset;

                # MSG
                my $msgFontSize        = $self->{output}{size}{y}*0.03;
                my $msgRowBottomOffset = 0;
                my $msgRowHight        = int( $msgFontSize * $fontScaleY + $msgRowBottomOffset );
                my $BR                 = "2,56 Mb";
                my $MC                 = "239.239.100.100";
                my $CC                 = ">56001";
                my $msgX               = $videoFramePositionX;
                my $msgY               = $videoFramePositionY + $videoFrameHeight - $msgRowHight;
                my $msgX2              = $msgX + $videoFrameWidth;
                my $msgY2              = $msgY + $msgFontSize;

                #ERROR
                my $errorFontSize = $self->{output}{error}{font};
                my $errorX1       = $videoFramePositionX;
                my $errorY1       = $videoFramePositionY;
                my $errorX2       = $videoFramePositionX + $videoFrameWidth;
                my $errorY2       = $videoFramePositionY + $videoFrameHeight;
                my $errorTextX    = int( ( $self->{output}{size}{x} - $videoFrameWidth ) / 2 - $videoFramePositionX );
                my $errorTextY    = int( ( $self->{output}{size}{y} - $videoFrameHeight ) / 2 - $videoFramePositionY );

                # Urejanje ImegeMagic

                # TITLE
                $topLayer->Annotate(
                    undercolor => '#e8ddce',
                    fill       => 'black',
                    font       => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize  => $titleFontSize,
                    geometry   => "+$titleX+$titleY",
                    gravity    => 'north',
                    text       => $titleName
                );

                # MSG
                $topLayer->Draw(
                    fill      => 'white',
                    points    => "$msgX,$msgY $msgX2,$msgY2",
                    gravity   => 'northwest',
                    primitive => 'rectangle'
                );

                $topLayer->Annotate(
                    fill      => 'black',
                    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize => $msgFontSize,
                    geometry  => "+$msgX+$msgY",
                    gravity   => 'northwest',
                    text      => $BR
                );

                $topLayer->Annotate(
                    fill      => 'black',
                    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize => $msgFontSize,
                    geometry  => "+" . int( $videoFramePositionX + $videoFrameWidth/2 - $self->{output}{size}{x}/2 ) . "+$msgY",
                    gravity   => 'north',
                    text      => $MC
                );

                $topLayer->Annotate(
                    fill      => 'black',
                    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                    pointsize => $msgFontSize,
                    geometry  => "+" . int(-$msgX2 + $self->{output}{size}{x}) . "+$msgY",
                    gravity   => 'northeast',
                    text      => $CC
                );

                # ERROR
                if ( $self->{output}{error}{position} == $input ) {
                    $topLayer->Draw(
                        fill      => 'rgba(255, 0, 0, 0.5)',
                        points    => "$errorX1,$errorY1 $errorX2,$errorY2",
                        gravity   => 'northwest',
                        primitive => 'rectangle'
                    );

                    $topLayer->Annotate(
                        fill      => 'black',
                        font      => $font,
                        pointsize => $errorFontSize,
                        geometry  => "-$errorTextX-$errorTextY",
                        gravity   => 'center',
                        text      => "ERROR"
                    );
                } ## end if ( $self->{output}{error...})
                $input++;
                print "Upper layer \n";
            } else {

    ############################################### URA #####################################################

                my $x      = $frame->{position}{x};
                my $y      = $frame->{position}{y};
                my $width  = $frame->{size}{width};
                my $height = $frame->{size}{height};
                my $x2     = $x + $width;
                my $y2     = $y + $height;

                # Barve
                my $circleColor       = '#e8ddce';
                my $circleStrokeColor = '#27284d';
                my $scaleColor        = '#27284d';
                my $kazalecColor      = '#27284d';
                my $secentColor       = '#a53e4f';

                # Urino središče
                my $clockCenterX = int( $x + $width / 2 );
                my $clockCenterY = int( $y + $height / 2 );

                # Krog
                my $circleRadius     = $height * 0.9 / 2;
                my $circleEdgeY      = $clockCenterY - $circleRadius;
                my $smallCircleEdgeY = $clockCenterY - $circleRadius * 0.05;
                my $fontSize         = int( $circleRadius * 0.2 );

                # Izdelava ozadja ure
                $topLayer->Draw(
                    fill        => 'rgb(126,126,126)',
                    points      => "$x,$y $x2,$y2",
                    primitive   => 'rectangle'
                );

                $topLayer->Draw(
                    fill        => $circleColor,
                    stroke      => $circleStrokeColor,
                    strokewidth => int( $circleRadius * 0.04 ),
                    points      => "$clockCenterX,$clockCenterY $clockCenterX,$circleEdgeY",
                    primitive   => 'circle'
                );

                # Pozicija številk
                my $numberOffSet = $circleRadius * 0.85;

                my $number12X = $clockCenterX - $self->{output}{size}{x} / 2;
                my $number12Y = $clockCenterY - $self->{output}{size}{y} / 2 - $numberOffSet;
                $topLayer->Annotate(
                    fill      => $scaleColor,
                    font      => $font,
                    pointsize => $fontSize,
                    geometry  => "+$number12X+$number12Y",
                    gravity   => 'center',
                    text      => "12"
                );

                my $number3X = $clockCenterX - $self->{output}{size}{x} / 2 + $numberOffSet;
                my $number3Y = $clockCenterY - $self->{output}{size}{y} / 2;
                $topLayer->Annotate(
                    fill      => $scaleColor,
                    font      => $font,
                    pointsize => $fontSize,
                    geometry  => "+$number3X+$number3Y",
                    gravity   => 'center',
                    text      => "3"
                );

                my $number6X = $clockCenterX - $self->{output}{size}{x} / 2;
                my $number6Y = $clockCenterY - $self->{output}{size}{y} / 2 + $numberOffSet;
                $topLayer->Annotate(
                    fill      => $scaleColor,
                    font      => $font,
                    pointsize => $fontSize,
                    geometry  => "+$number6X+$number6Y",
                    gravity   => 'center',
                    text      => "6"
                );

                my $number9X = $clockCenterX - $self->{output}{size}{x} / 2 - $numberOffSet;
                my $number9Y = $clockCenterY - $self->{output}{size}{y} / 2;
                $topLayer->Annotate(
                    fill      => $scaleColor,
                    font      => $font,
                    pointsize => $fontSize,
                    geometry  => "+$number9X+$number9Y",
                    gravity   => 'center',
                    text      => "9"
                );


                # črtice med številkami na uri
                my @smallScaleLine  = ( 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 );
                my $scaleLine1      = int( $circleRadius * 0.85 );
                my $scaleLine2      = int( $circleRadius * 0.95 );
                my $smallScaleLine1 = int( $circleRadius * 0.90 );

                for ( my $i = 0 ; $i < 4 ; $i++ ) {

                    for ( my $j = 0 ; $j < 12 ; $j++ ) {

                        my $smallScaleLineN = $smallScaleLine[$j] + $i * 15;

                        if ( $smallScaleLineN % 5 == 0 ) {

                            my $scaleLineY1 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine1 );
                            my $scaleLineX1 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine1 );

                            my $scaleLineY2 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );
                            my $scaleLineX2 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );

                            $topLayer->Draw(
                                fill   => $scaleColor,
                                stroke => $scaleColor,
                                points => "$scaleLineX1,$scaleLineY1 $scaleLineX2,$scaleLineY2",  # kordinate točk x1, y1, x2, y1
                                strokewidth => int( $circleRadius * 0.02 ),
                                primitive   => 'line'
                            );

                        } else {

                            my $smallScaleLineY1 =
                                $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $smallScaleLine1 );
                            my $smallScaleLineX1 =
                                $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $smallScaleLine1 );

                            my $scaleLineY2 = $clockCenterY - int( sin( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );
                            my $scaleLineX2 = $clockCenterX + int( cos( pi / 2 - ( $smallScaleLineN * pi / 30 ) ) * $scaleLine2 );

                            $topLayer->Draw(
                                fill   => $scaleColor,
                                stroke => $scaleColor,
                                points => "$smallScaleLineX1,$smallScaleLineY1 $scaleLineX2,$scaleLineY2"
                                ,    # kordinate točk x1, y1, x2, y1
                                strokewidth => int( $circleRadius * 0.01 ),
                                primitive   => 'line'
                            );
                        } ## end else [ if ( $smallScaleLineN ...)]
                    } ## end for ( my $j = 0 ; $j < ...)
                } ## end for ( my $i = 0 ; $i < ...)

                ##### KAZALCI IN DATUM #####

                # Pozicija datuma
                my $dateOffSetCenter = int( $circleRadius / 2 );
                my $dateX            = $clockCenterX - $self->{output}{size}{x} / 2;
                my $dateY            = $clockCenterY - $self->{output}{size}{y} / 2 + $dateOffSetCenter;

                # Velikost kazalcev
                my $kazalecDolzinaSecond = int( $circleRadius * 0.75 );
                my $kazalecDolzinaMinute = int( $circleRadius * 0.75 );
                my $kazalecDolzinaHour   = int( $circleRadius * 0.6 );

                my $kazalecSecendCircle = $clockCenterY - int( $circleRadius * 0.06 );
                my $thicknessSecond     = int( $circleRadius * 0.02 );
                my $thicknessMinute     = int( $circleRadius * 0.04 );
                my $thicknessHour       = int( $circleRadius * 0.06 );

                # Določanje časovnih spremenljivk
                my $second = strftime "%S", localtime;
                my $minute = strftime "%M", localtime;
                my $hour   = strftime "%I", localtime;
                my $date   = strftime "%F", localtime;

                if ( $hour == 12 ) { $hour = 0; }

                my $SecondY = $clockCenterY - int( sin( pi / 2 - ( $second * pi / 30 ) ) * $kazalecDolzinaSecond );
                my $SecondX = $clockCenterX + int( cos( pi / 2 - ( $second * pi / 30 ) ) * $kazalecDolzinaSecond );

                my $MinuteY = $clockCenterY - int( sin( pi / 2 - ( $minute * pi / 30 ) ) * $kazalecDolzinaMinute );
                my $MinuteX = $clockCenterX + int( cos( pi / 2 - ( $minute * pi / 30 ) ) * $kazalecDolzinaMinute );

                my $HourY = $clockCenterY - int( sin( pi / 2 - ( ( $hour * 60 + $minute ) * pi / 360 ) ) * $kazalecDolzinaHour );
                my $HourX = $clockCenterX + int( cos( pi / 2 - ( ( $hour * 60 + $minute ) * pi / 360 ) ) * $kazalecDolzinaHour );

                # DATUM
                $topLayer->Annotate(
                    fill      => $scaleColor,
                    font      => $font,
                    pointsize => $fontSize,
                    geometry  => "+$dateX+$dateY",
                    gravity   => 'center',
                    text      => "$date"
                );

                # Urni kazalec
                $topLayer->Draw(
                    fill        => $kazalecColor,
                    stroke      => $kazalecColor,
                    points      => "$clockCenterX,$clockCenterY $HourX,$HourY",
                    strokewidth => $thicknessHour,
                    primitive   => 'line'
                );

                # Minutni kazalec
                $topLayer->Draw(
                    fill        => $kazalecColor,
                    stroke      => $kazalecColor,
                    points      => "$clockCenterX,$clockCenterY $MinuteX,$MinuteY",
                    strokewidth => $thicknessMinute,
                    primitive   => 'line'
                );

                # Sekundni kazalec
                $topLayer->Draw(
                    fill        => $secentColor,
                    stroke      => $secentColor,
                    points      => "$clockCenterX,$clockCenterY $SecondX,$SecondY",
                    strokewidth => $thicknessSecond,
                    primitive   => 'line'
                );

                $topLayer->Draw(
                    fill      => $secentColor,
                    points    => "$clockCenterX,$clockCenterY $clockCenterX,$smallCircleEdgeY",
                    primitive => 'circle'
                );
            } ## end else [ if ( $frame->{serviceId...})]
        } ## end foreach my $frame ( @{ $self...})

        $topLayer->Write('top_layer/active_layer1.png');

        # Premaknemo active_layer1.png v active_layer.png
        move( 'top_layer/active_layer1.png', 'top_layer/layer.png' );

        print("ura \n");
        my $t = time();
        while ( time() == $t ) { }
    } ## end while (1)
} ## end sub buildTlay

1;