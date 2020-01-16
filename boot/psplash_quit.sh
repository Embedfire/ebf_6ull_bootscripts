#!/bin/bash 

urandom=2500
AVAIL=0
sec=5

starttime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);

while [ $AVAIL -le $urandom ]
 do
    read AVAIL < /proc/sys/kernel/random/entropy_avail
    echo $AVAIL
    progress=$(($AVAIL*100 / $urandom))
    echo $progress  
    sudo psplash-write  "PROGRESS $progress"
    endtime=`date +'%Y-%m-%d %H:%M:%S'`
    end_seconds=$(date --date="$endtime" +%s);
   
    if [ $((end_seconds-start_seconds)) -ge $sec ]
    then
	break;	
    fi
done

sudo psplash-write  "PROGRESS 95"
#sudo psplash-write QUIT
sudo /home/debian/qt-app-static/run.sh