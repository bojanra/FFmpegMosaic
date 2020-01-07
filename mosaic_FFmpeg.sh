#!/bin/bash 

 ffmpegX -y -re -i 'video/tsm_sample_kratek.ts' -i 'video/ts_kratek.ts' -i 'video/tsm_sample_kratek.ts' -loop 1 -f image2 -r 25 -i 'top_layer/active_layer.png' \
 -map 2:v:0 -map 2:a:0 -map 2:a:1 -map 1:v:0 -map 1:a:0 -map 0:v:0 -map 0:a:0 -map 0:a:1 -map 3:v \
-filter_complex " \
nullsrc=1920x1080, lutrgb=126:126:126 [base]; \
[2:v:0] setpts=PTS-STARTPTS, scale=931x523 [2:v];  \
[2:a:0] showvolume=f=0.5:c=0x00ffff:b=4:w=493:h=9:o=v:ds=log:dm=2:p=1, format=yuv420p [2.0:a]; \
[2:a:1] showvolume=f=0.5:c=0x00ffff:b=4:w=493:h=9:o=v:ds=log:dm=2:p=1, format=yuv420p [2.1:a]; \
[1:v:0] setpts=PTS-STARTPTS, scale=931x523 [1:v];  \
[1:a:0] showvolume=f=0.5:c=0x00ffff:b=4:w=493:h=9:o=v:ds=log:dm=2:p=1, format=yuv420p [1.0:a]; \
[0:v:0] setpts=PTS-STARTPTS, scale=931x523 [0:v];  \
[0:a:0] showvolume=f=0.5:c=0x00ffff:b=4:w=493:h=9:o=v:ds=log:dm=2:p=1, format=yuv420p [0.0:a]; \
[0:a:1] showvolume=f=0.5:c=0x00ffff:b=4:w=493:h=9:o=v:ds=log:dm=2:p=1, format=yuv420p [0.1:a]; \
[3:v] setpts=PTS-STARTPTS, scale=1920x1080 [topLayer];  \
[base] \
[2:v] overlay=shortest=1: x=9: y=5 [2.1:layer]; [2.1:layer][2.1:a] overlay=shortest=1:x=918: y=5  [2.0:layer]; [2.0:layer][2.0:a] overlay=shortest=1:x=894: y=5  [2:layer]; [2:layer] \
[1:v] overlay=shortest=1: x=978: y=5 [1.0:layer]; [1.0:layer][1.0:a] overlay=shortest=1:x=1887: y=5  [1:layer]; [1:layer] \
[0:v] overlay=shortest=1: x=978: y=549 [0.1:layer]; [0.1:layer][0.1:a] overlay=shortest=1:x=1887: y=549  [0.0:layer]; [0.0:layer][0.0:a] overlay=shortest=1:x=1863: y=549  [0:layer]; [0:layer] \
[topLayer] overlay=shortest=1: x=0: y=0"  \
-strict experimental -vcodec libx264 -b:v 4M -minrate 3M -maxrate 3M -bufsize 6M -preset ultrafast  -profile:v high -level 4.0 -an -threads 0 \
-f mpegts udp://172.30.1.41:5000?pkt_size=1316