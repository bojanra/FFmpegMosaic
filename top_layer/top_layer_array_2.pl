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
my $configFile        = "/home/zaleteljk/Bojan/mosaic/t/sample.yamol";
my $pictureFormat     = "1920x1080";
my $stream            = "172.30.1.41:5000";
my $fontScaleX        = 0.6;
my $fontScaleY        = 1;
my $fond              = "/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf";
my $clockLineLocation = -1;
my $fh;

my $element = 4;
my @title   = ('Koper' , 'TV SLO 1' , 'TV SLO 2');

# izdelava osnovne plasti
my $upperLayer;

$upperLayer = Image::Magick->new();
$upperLayer->Set(size=>$pictureFormat);
$upperLayer->ReadImage('canvas:transparent');


# Pisanje podatkov na zadnjo plast

for(my $nInput = 0; $nInput < @title; $nInput++){

    my $col = $nInput % 2;
    my $row = int( $nInput / 2 );

    # VIDEO dimenzije $ pozicija
    my $videoFrameWidth     = int(1920/2);
    my $videoFrameHeight    = int($videoFrameWidth * 9/16);
    my $videoFramePositionX = $videoFrameWidth*$col;
    my $videoFramePositionY = int($videoFrameWidth * 9/16)*$row;

    # Samodejni izračun višine videa
    if($videoFrameHeight eq ""){ $videoFrameHeight = int($videoFrameWidth*9/16); }

    if($videoFrameHeight eq ""){ $videoFrameHeight = int($videoFrameWidth*9/16); }

    my $videoFrameScale = $videoFrameWidth."x".$videoFrameHeight;

# Izračun kordinat

    # TITLE
    my $titleFontSize     = 30;
    my $titleRowTopOffset = 10;
    my $titleName         = $title[$nInput];
    my $titleOffsetX      = int(($videoFrameWidth - (length($titleName)*$titleFontSize*$fontScaleX))/2);
    my $titleX            = $videoFramePositionX + $titleOffsetX;
    my $titleY            = $videoFramePositionY + $titleRowTopOffset;

    # MSG
    my $msgFontSize        = 30;
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
}
$upperLayer->Write('top_layer/upper_layer.png');

print "Upper layer generated\n";




############################################### URA #####################################################


my $fixedClockLayer = Image::Magick->new();
$fixedClockLayer->Read('top_layer/upper_layer.png');

# Urino središče
my $clockCenterX = 1200;
my $clockCenterY = 800;

# Krog
my $circleRadius = 150;
my $circleX = $clockCenterX ;
my $circleY = $clockCenterY;
my $circleOffSetEdgeX = $clockCenterX;
my $circleOffSetEdgeY = $clockCenterY - $circleRadius;

# Pozicija številk
my $clockCenterFromCenterX = int(1920/2 - $clockCenterX);
my $clockCenterFromCenterY = int(1080/2 - $clockCenterY);

my $numberOffSetCenter = $circleRadius*0.85;

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
my $kazalecDolzinaSecond = int($circleRadius*0.75);
my $kazalecDolzinaMinute = int($circleRadius*0.75);
my $kazalecDolzinaHour   = int($circleRadius*0.6);

my $scaleLine1      = int($circleRadius*0.85);
my $scaleLine2      = int($circleRadius*0.95);
my $smallScaleLine1 = int($circleRadius*0.90);

my $thicknesScaleLine      = int($circleRadius*0.02);
my $thicknesSmallScaleLine = int($circleRadius*0.01);
my $thicknessCircle        = int($circleRadius*0.04);

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
    primitive   => 'circle');


# črtice med številkami na uri
my @smallScaleLine = (2,3,4,5,6,7,8,9,10,11,12,13);

for(my $i=0; $i < 4; $i++){

    for(my $j=0; $j < 12; $j++){

        my $smallScaleLineN = $smallScaleLine[$j] + $i*15; 

        if($smallScaleLineN % 5 == 0){

            my $scaleLineY1 = $clockCenterY - int(sin(pi/2-($smallScaleLineN*pi/30))*$scaleLine1);
            my $scaleLineX1 = $clockCenterX + int(cos(pi/2-($smallScaleLineN*pi/30))*$scaleLine1);

            my $scaleLineY2 = $clockCenterY - int(sin(pi/2-($smallScaleLineN*pi/30))*$scaleLine2);
            my $scaleLineX2 = $clockCenterX + int(cos(pi/2-($smallScaleLineN*pi/30))*$scaleLine2);

            $fixedClockLayer->Draw(
                fill        => $scaleColor,
                stroke      => $scaleColor,
                points      => "$scaleLineX1,$scaleLineY1 $scaleLineX2,$scaleLineY2", # kordinate točk x1, y1, x2, y1
                strokewidth => $thicknesScaleLine,
                primitive   => 'line');

        }else{

            my $smallScaleLineY1 = $clockCenterY - int(sin(pi/2-($smallScaleLineN*pi/30))*$smallScaleLine1);
            my $smallScaleLineX1 = $clockCenterX + int(cos(pi/2-($smallScaleLineN*pi/30))*$smallScaleLine1);
            
            my $scaleLineY2 = $clockCenterY - int(sin(pi/2-($smallScaleLineN*pi/30))*$scaleLine2);
            my $scaleLineX2 = $clockCenterX + int(cos(pi/2-($smallScaleLineN*pi/30))*$scaleLine2);

            $fixedClockLayer->Draw(
                fill        => $scaleColor,
                stroke      => $scaleColor,
                points      => "$smallScaleLineX1,$smallScaleLineY1 $scaleLineX2,$scaleLineY2", # kordinate točk x1, y1, x2, y1
                strokewidth => $thicknesSmallScaleLine,
                primitive   => 'line');
        }
    }
}
# Številke na uri

my $font = $circleRadius*0.2;
if($font eq ""){$font = int($circleRadius*0.2)}

$fixedClockLayer->Annotate(
    fill      => $scaleColor,
    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
    pointsize => $font,
    geometry  => "-$number12X-$number12Y",
    gravity   => 'center',
    text      => "12");

$fixedClockLayer->Annotate(
    fill      => $scaleColor,
    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
    pointsize => $font,
    geometry  => "-$number3X-$number3Y",
    gravity   => 'center',
    text      => "3");

$fixedClockLayer->Annotate(
    fill      => $scaleColor,
    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
    pointsize => $font,
    geometry  => "-$number6X-$number6Y",
    gravity   => 'center',
    text      => "6");

$fixedClockLayer->Annotate(
    fill      => $scaleColor,
    font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
    pointsize => $font,
    geometry  => "-$number9X-$number9Y",
    gravity   => 'center',
    text      => "9");


print"fixed clock layer generiran\n";

$fixedClockLayer->Write('top_layer/fixed_clock_layer.png');


##### KAZALCI IN DATUM #####

my $second;
my $minute;
my $minuteL = "0";
my $hour;
my $hourL   = "0";
my $date;
my $dateL   = "0";

my @kazalecSecondY;
my @kazalecSecondX;
my $SecondY;
my $SecondX;
my $thicknessSecond = int($circleRadius*0.02);
my $kazalecSecendCircle = $clockCenterY - int($circleRadius*0.06);

my @kazalecMinuteY;
my @kazalecMinuteX;
my $MinuteY;
my $MinuteX;
my $thicknessMinute = int($circleRadius*0.04);

my @kazalecHourY;
my @kazalecHourX;
my $HourY;
my $HourX;
my $thicknessHour = int($circleRadius*0.06);

my $activeLayer = Image::Magick->new();
$activeLayer->Read("top_layer/fixed_clock_layer.png");

for(my $s=0; $s <= 720; $s++){
    push(@kazalecSecondY, ($clockCenterY  - int(sin(pi/2-($s*pi/30))*$kazalecDolzinaSecond)));
    push(@kazalecSecondX, ($clockCenterX  + int(cos(pi/2-($s*pi/30))*$kazalecDolzinaSecond)));

    push(@kazalecMinuteY, ($clockCenterY  - int(sin(pi/2-($s*pi/30))*$kazalecDolzinaMinute)));
    push(@kazalecMinuteX, ($clockCenterX  + int(cos(pi/2-($s*pi/30))*$kazalecDolzinaMinute)));

    push(@kazalecHourY, ($clockCenterY  - int(sin(pi/2-($s*pi/360))*$kazalecDolzinaHour)));
    push(@kazalecHourX, ($clockCenterX  + int(cos(pi/2-($s*pi/360))*$kazalecDolzinaHour)));
}
my $t = 0;
while(1){

    $activeLayer->Draw(
        fill      => $circleColor,
        points    => "$clockCenterX,$clockCenterY $circleOffSetEdgeX,$smallCircleOffSetEdgeY",
        primitive => 'circle');    

    # Določanje časovnih spremenljivk
    $second = strftime "%S", localtime;
    $minute = strftime "%M", localtime;
    $hour   = strftime "%I", localtime;
    $date   = strftime "%F", localtime;

    if($hour==12){$hour=0;}

    $SecondY = $kazalecSecondY[$second];
    $SecondX = $kazalecSecondX[$second];

    $MinuteY = $kazalecMinuteY[$minute];
    $MinuteX = $kazalecMinuteX[$minute];

    $HourY   = $kazalecHourY[$hour*60+$minute];
    $HourX   = $kazalecHourX[$hour*60+$minute];

    # DATUM
    $activeLayer->Annotate(
        fill      => $scaleColor,
        font      => '/usr/share/fonts/truetype/noto/NotoMono-Regular.ttf',
        pointsize => $font,
        geometry  => "-$dateX-$dateY",
        gravity   => 'center',
        text      => "$date");

    # Urni kazalec
    $activeLayer->Draw(
        fill        => $kazalecColor,
        stroke      => $kazalecColor,
        points      => "$clockCenterX,$clockCenterY $HourX,$HourY",
        strokewidth => $thicknessHour,
        primitive   => 'line');

    # Minutni kazalec
    $activeLayer->Draw(
        fill        => $kazalecColor,
        stroke      => $kazalecColor,
        points      => "$clockCenterX,$clockCenterY $MinuteX,$MinuteY",
        strokewidth => $thicknessMinute,
        primitive   => 'line');
    

    # Sekundni kazalec
    $activeLayer->Draw(
        fill        => $secentColor,
        stroke      => $secentColor,
        points      => "$clockCenterX,$clockCenterY $SecondX,$SecondY",
        strokewidth => $thicknessSecond,
        primitive   => 'line');

    $activeLayer->Draw(
        fill      => $secentColor,
        points    => "$clockCenterX,$clockCenterY $clockCenterX,$kazalecSecendCircle",
        primitive => 'circle');


    $activeLayer->Write('top_layer/active_layer1.png');

# Premaknemo active_layer1.png v active_layer.png
    move('top_layer/active_layer1.png', 'top_layer/active_layer.png');
    
    $t = time();
    while(time() == $t){}
    
}