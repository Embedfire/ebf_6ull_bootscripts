#!/bin/sh -e

fat_media="/lib/firmware/fatboot.img"
boot_dir="/boot"

unset root_drive

root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root=UUID= | awk -F 'root=' '{print $2}' || true)"
if [ ! "x${root_drive}" = "x" ] ; then
	root_drive="$(/sbin/findfs ${root_drive} || true)"
else
	root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root= | awk -F 'root=' '{print $2}' || true)"
fi

if [ "x${root_drive}" = "x/dev/mmcblk0p2" ] || [ "x${root_drive}" = "x/dev/mmcblk1p2" ] ; then
	actual_image_file="${root_drive%?}1"
else
	media_loop=$(losetup -f || true)
    losetup -o1M ${media_loop} "${fat_media}"
	mount ${media_loop} ${boot_dir} -o sync
	actual_image_file=${media_loop}
fi

if [ -f /var/lib/alsa/asound.state ] ; then
	aplay -l && alsactl restore asound.state
fi

modprobe g_multi file=${actual_image_file} removable=1 cdrom=0 ro=0 stall=0 nofua=1 iManufacturer=embedfire iProduct=embedfire iSerialNumber=1234fire5678

$(dirname $0)/autoconfigure_usb0.sh || true