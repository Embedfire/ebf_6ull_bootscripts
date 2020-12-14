#!/bin/sh -e

_do () {
        $@ || ( cp -rf /tmp/boot /; echo "kernel update failed: $@"; exit -1; )
}


if [ ! -f /boot/vmlinuz-$(uname -r) ]; then
	echo "error:fire kernel no exit!"
else
	cp -rf /boot /tmp	
	
	_do apt update -y
	
	_do apt install linux-image-$(uname -r) -y

	if [ -f /boot/vmlinuz-$(uname -r) ]; then
		rm -rf /tmp/boot
	else
		cp -rf /tmp/boot /
	fi
fi
