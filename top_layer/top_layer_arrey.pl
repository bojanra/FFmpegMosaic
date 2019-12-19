#!/usr/bin/perl
use 5.014;
use strict;
use warnings;
use Image::Magick;
use Math::Trig;
use POSIX qw(strftime);
use File::Copy;
use Data::Dumper;

# default values
my $configFile        = "/home/zaleteljk/projekt/FFmpeg_IM_one_image/mosaicPL.cnf";
my $pictureFormat     = "1920x1080";
my $stream            = "172.30.1.41:5000";
my $fontScaleX        = 0.6;
my $fontScaleY        = 1;
my $fond              = "/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf";
my $clockLineLocation = -1;
my $fh;


open($fh, '<:encoding(UTF-8)', $configFile);
my @lines = <$fh>;

# izločitev vrstic z znakom #
my $j       = 0;
my $row     = @lines;
my @element = "";

for(my $i = 0; $row > $i; $i++){
    my $index = index(Dumper ($lines[$i]), '#');
    if($index < 0){ 
        @element[$j] = $lines[$i];
        chomp @element; 
        $j++;
    }
}

# izdelava osnovne plasti
my $upperLayer;

$upperLayer = Image::Magick->new();
$upperLayer->Set(size=>$pictureFormat);
$upperLayer->ReadImage('canvas:transparent');


# Pisanje podatkov na zadnjo plast

for(my $nInput = 0; $nInput < @element; $nInput++){

    my @parameter = split /,/, $element[$nInput];

    # INPUT
    my $input = $parameter[0];

    # VIDEO
    my $videoFrameWidth  = $parameter[3];
    my $videoFrameHeight = $parameter[4];

    if($videoFrameHeight eq ""){
        $videoFrameHeight = int($videoFrameWidth*9/16);
    }

    if($videoFrameHeight eq ""){
        $videoFrameHeight = int($videoFrameWidth*9/16);
    }
    my $videoFramePositionX = $parameter[1];
    my $videoFramePositionY = $parameter[2];
    my $videoFrameScale     = $videoFrameWidth."x".$videoFrameHeight;

    if($parameter[5] ne "clock"){
# Izračun kordinat

        # TITLE
        my $titleFontSize     = $parameter[8];
        my $titleRowTopOffset = 10;
        my $titleName         = $parameter[9];
        my $titleOffsetX      = int(($videoFrameWidth - (length($titleName)*$titleFontSize*$fontScaleX))/2);
        my $titleX            = $videoFramePositionX + $titleOffsetX;
        my $titleY            = $videoFramePositionY + $titleRowTopOffset;

        # MSG1
        my $msgFontSize        = $parameter[10];
        my $msgRowBottomOffset = 0;
        my $msgRowHight        = int($msgFontSize*$fontScaleY + $msgRowBottomOffset);
            my $BR = "2,56 Mb";
            my $MC = "239.239.100.200";
            my $CC = ">56001";
        my $msgX  = $videoFramePositionX;
        my $msgY  = $videoFramePositionY + $videoFrameHeight - $msgRowHight;
        my $msgX2 = $msgX+$videoFrameWidth;
        my $msgY2 = $msgY+$msgFontSize;

        #ERROR
        my $errorFontSize = 50;
        my $errorX1 = $videoFramePositionX;
        my $errorY1 = $videoFramePositionY;
        my $errorX2 = $videoFramePositionX+$videoFrameWidth;
        my $errorY2 = $videoFramePositionY+$videoFrameHeight;
        my $errorTextX = int((1920-$videoFrameWidth)/2-$videoFramePositionX);
        my $errorTextY = int((1080-$videoFrameHeight)/2-$videoFramePositionY);

# Urejanje ImegeMagic

        # TITLE
        $upperLayer->Annotate(
            undercolor => 'lightblue',
            fill       => 'black',
            font       => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
            pointsize  => $titleFontSize,
            geometry   => "+$titleX+$titleY",
            gravity    => 'northwest',
            text       => $titleName);

        # MSG
        $upperLayer->Draw(
            fill      => 'white',
            points    => "$msgX,$msgY $msgX2,$msgY2",
            gravity   => 'northwest',
            primitive => 'rectangle');

        $upperLayer->Annotate(
            fill      => 'black',
            font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
            pointsize => $msgFontSize,
            geometry  => "+$msgX+$msgY",
            gravity   => 'northwest',
            text      => "$BR");

        $upperLayer->Annotate(
            fill      => 'black',
            font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
            pointsize => $msgFontSize,
            geometry  => "-".int((1920-$videoFrameWidth)/2-$msgX)."+$msgY",
            gravity   => 'north',
            text      => "$MC");

        $upperLayer->Annotate(
            fill      => 'black',
            font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
            pointsize => $msgFontSize,
            geometry  => "+".(1920-$videoFrameWidth-$msgX)."+$msgY",
            gravity   => 'northeast',
            text      => "$CC");

        # ERROR
        if($nInput == -1){
            $upperLayer->Draw(
                fill      => 'rgba(255, 0, 0, 0.5)',
                points    => "$errorX1,$errorY1 $errorX2,$errorY2",
                gravity   => 'northwest',
                primitive => 'rectangle');

            $upperLayer->Annotate(
                fill      => 'black',
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $errorFontSize,
                geometry  => "-$errorTextX-$errorTextY",
                gravity   => 'center',
                text      => "ERROR");       
        }
        print"$nInput\n";

        }else{
            $clockLineLocation = $nInput;
    }
}
$upperLayer->Write('upper_layer.png');

print "Upper layer generated\n";




############################################### URA #####################################################



# Pogoj preveri ali je potrebno izdelovati uro

if($clockLineLocation >= 0){

    my $fixedClockLayer = Image::Magick->new();
    $fixedClockLayer->Read('upper_layer.png');

    my $clockLine = $element[$clockLineLocation];
    chomp $clockLine;
    print Dumper($clockLine);

    my @parameter = split /,/, $clockLine;
    my $circleRadius = $parameter[3];
    
    # Urino središče
    my $clockCenterX = $parameter[1];
    my $clockCenterY = $parameter[2];
    
    # Circle
    my $circleX = $clockCenterX ;
    my $circleY = $clockCenterY;
    my $circleOffSetEdgeX = $clockCenterX;
    my $circleOffSetEdgeY = $clockCenterY - $circleRadius;
    

    # Pozicija številk
    my $clockCenterFromCenterX = int(1920/2 - $clockCenterX);
    my $clockCenterFromCenterY = int(1080/2 - $clockCenterY);

    my $numberOffSetCenter = $circleRadius - 15;

    my $number12X = $clockCenterFromCenterX;
    my $number12Y = $clockCenterFromCenterY + $numberOffSetCenter;
    my $number3X  = $clockCenterFromCenterX - $numberOffSetCenter;
    my $number3Y  = $clockCenterFromCenterY;
    my $number6X  = $clockCenterFromCenterX;
    my $number6Y  = $clockCenterFromCenterY - $numberOffSetCenter;
    my $number9X  = $clockCenterFromCenterX + $numberOffSetCenter;
    my $number9Y  = $clockCenterFromCenterY;

    # Pozicija datuma
    my $dateOffSetCenter = int($circleRadius/2);
    my $dateX = $clockCenterFromCenterX;
    my $dateY = $clockCenterFromCenterY - $dateOffSetCenter;

    # Velikost kazalcev
    my $kazalecDolzinaSecond = $circleRadius-30;
    my $kazalecDolzinaMinute = $circleRadius-30;
    my $kazalecDolzinaHour   = $circleRadius-45;
    my $scaleLine1 = $circleRadius - 15;
    my $scaleLine2 = $circleRadius - 5;

    my $smallCircleOffSetEdgeY = $clockCenterY - $kazalecDolzinaSecond;

    ##### Izdelava ozadja ure #####

    $fixedClockLayer->Draw(
        fill      => 'skyblue',
        stroke    => 'black',
        points    => "$clockCenterX,$clockCenterY $circleOffSetEdgeX,$circleOffSetEdgeY",
        primitive => 'circle');


    # črtice med številkami na uri
    for(my $i=1; $i < 12; $i++){

        if($i % 3 != 0){
            my $kazalecY1 = $clockCenterY - int(sin(pi/2-($i*pi/6))*$scaleLine1);
            my $kazalecX1 = $clockCenterX + int(cos(pi/2-($i*pi/6))*$scaleLine1);

            my $kazalecY2 = $clockCenterY - int(sin(pi/2-($i*pi/6))*$scaleLine2);
            my $kazalecX2 = $clockCenterX + int(cos(pi/2-($i*pi/6))*$scaleLine2);
            
            $fixedClockLayer->Draw(
                fill      => 'red',
                stroke    => 'black',
                points    => "$kazalecX1,$kazalecY1 $kazalecX2,$kazalecY2", # kordinate točk x1, y1, x2, y1
                primitive => 'line');
        }
    }

    # Številke na uri

    my $font = $parameter[4];
    my $colorNumber = 'black';
    $fixedClockLayer->Annotate(
        fill      => $colorNumber,
        font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
        pointsize => $font,
        geometry  => "-$number12X-$number12Y",
        gravity   => 'center',
        text      => "12");

    $fixedClockLayer->Annotate(
        fill      => $colorNumber,
        font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
        pointsize => $font,
        geometry  => "-$number3X-$number3Y",
        gravity   => 'center',
        text      => "3");

    $fixedClockLayer->Annotate(
        fill      => $colorNumber,
        font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
        pointsize => $font,
        geometry  => "-$number6X-$number6Y",
        gravity   => 'center',
        text      => "6");

    $fixedClockLayer->Annotate(
        fill      => $colorNumber,
        font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
        pointsize => $font,
        geometry  => "-$number9X-$number9Y",
        gravity   => 'center',
        text      => "9");


    print"fixed clock layer generiran\n";

    $fixedClockLayer->Write('fixed_clock_layer.png');


    ##### KAZALCI IN DATUM #####

    my $second;
    my $minute;
    my $minuteL = "0";
    my $hour;
    my $hourL   = "0";
    my $date;
    my $dateL   = "0";

    my @kazalecSY;
    my @kazalecSX;

    my $kazalecSecondY;
    my $kazalecSecondX;

    my $kazalecMinuteY;
    my $kazalecMinuteX;

    my $kazalecHourY;
    my $kazalecHourX;

    for(my $s=0; $s <= 61; $s++){
        push(@kazalecSY, ($clockCenterY  - int(sin(pi/2-($s*pi/30))*$kazalecDolzinaSecond)));
        push(@kazalecSX, ($clockCenterX  + int(cos(pi/2-($s*pi/30))*$kazalecDolzinaSecond)));
    }

    my $activeLayer = Image::Magick->new();
    $activeLayer->Read("fixed_clock_layer.png");

    while(1){
        
        $activeLayer->Draw(
            fill      => 'skyblue',
            points    => "$clockCenterX,$clockCenterY $circleOffSetEdgeX,$smallCircleOffSetEdgeY",
            primitive => 'circle');

    # Določanje časovnih spremenljivk
        $second = strftime "%S", localtime;
        $minute = strftime "%M", localtime;

    # SEKUNDA
        $kazalecSecondY = $kazalecSY[$second];
        $kazalecSecondX = $kazalecSX[$second];

        # Sekundni kazalec
        $activeLayer->Draw(
            fill        => 'red',
            stroke      => 'red',
            points      => "$clockCenterX,$clockCenterY $kazalecSecondX,$kazalecSecondY",
            strokewidth => 3,
            primitive   => 'line');

        if($minute ge $minuteL){
            $date   = strftime "%F", localtime;
            $hour   = strftime "%I", localtime;

        # MINUTA
            $kazalecMinuteY = $clockCenterY  - int(sin(pi/2-($minute*pi/30))*$kazalecDolzinaMinute);
            $kazalecMinuteX = $clockCenterX  + int(cos(pi/2-($minute*pi/30))*$kazalecDolzinaMinute);
        # URA
            $kazalecHourY = $clockCenterY  - int(sin(pi/2-($hour*pi/6 + $minute*pi/360))*$kazalecDolzinaHour);
            $kazalecHourX = $clockCenterX  + int(cos(pi/2-($hour*pi/6 + $minute*pi/360))*$kazalecDolzinaHour);

            # Minutni kazalec
            $activeLayer->Draw(
                fill        => 'black',
                stroke      => 'black',
                points      => "$clockCenterX,$clockCenterY $kazalecMinuteX,$kazalecMinuteY",
                strokewidth => 3,
                primitive   => 'line');
            $minuteL = $minute;
        
            # Urni kazalec
            $activeLayer->Draw(
                fill        => 'black',
                stroke      => 'black',
                points      => "$clockCenterX,$clockCenterY $kazalecHourX,$kazalecHourY",
                strokewidth => 4,
                primitive   => 'line');
            
            # Datum
            $activeLayer->Annotate(
                fill      => 'black',
                font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
                pointsize => $font,
                geometry  => "-$dateX-$dateY",
                gravity   => 'center',
                text      => "$date");
        }

        $activeLayer->Write('active_layer1.png');

    # Premaknemo active_layer1.png v active_layer.png
        move('active_layer1.png', 'active_layer.png');
        
    # Premor 1s
        my $t = time();
        while(time() < $t + 1){}
    }
}
