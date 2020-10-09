#!/bin/sh -e

_do () {
        $@ || ( cp -rf /tmp/boot /; echo "kernel update failed: $@"; exit -1; )
}


if [ ! -f /boot/vmlinuz* ]; then
	echo "error:fire kernel no exit!"
else
	cp -rf /boot /tmp	

	rm /boot/*-4.19.71-imx-r1

	rm -rf /boot/dtbs
	
	_do apt update -y
	
	_do apt install linux-image-4.19.71-imx-r1 -y

	if [ -f /boot/vmlinuz* ]; then
		rm -rf /tmp/boot
	else
		cp -rf /tmp/boot /
	fi
fi
