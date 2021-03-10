#!/bin/bash -e

fat_media="/lib/firmware/fatboot.img"
boot_dir="/boot"

unset root_drive

#root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root=UUID= | awk -F 'root=' '{print $2}' || true)"
#if [ ! "x${root_drive}" = "x" ] ; then
#	root_drive="$(/sbin/findfs ${root_drive} || true)"
#else
root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root= | awk -F 'root=' '{print $2}' || true)"
#fi

media_device=${root_drive%p*}

# mount boot partation
boot_drive=$(sfdisk -ld ${media_device} | grep boot | awk -F ':' '{print $1}')


mount ${boot_drive} /boot

res=$(echo ${root_drive} | grep "mmcblk")
if [ "$res" = "$root_drive" ]; then
	actual_image_file=/dev/$(mount | sed -n 's|^/dev/\(.*\) on /boot .*|\1|p')
else
	media_loop=$(losetup -f || true)
    losetup -o1M ${media_loop} "${fat_media}"
	mount ${media_loop} ${boot_dir} -o sync
	actual_image_file=${media_loop}
fi

if [ -f /var/lib/alsa/asound.state ] ; then
	aplay -l && alsactl restore asound.state
fi


# save the random mac address if unexist
wfile="/boot/uEnv.txt"
keth0addr=$(sed -nre 's/^ *ethaddr=([0-9a-fA-F:]+) *$/\1/p' $wfile)
if [ "x${keth0addr}" = "x" ] ; then
	rndaddr=$(ip address show dev eth0 | sed -nre 's/ *link\/ether ([0-9a-fA-F:]+) .*/\1/p')
	echo "# specify kernel eth0 mac address" >> $wfile
	echo "ethaddr=$rndaddr" >> $wfile
	echo "" >> $wfile
	sync
fi

is_empty_dir(){
    return `ls -A $1|wc -w`
}

storage_media=$(cat $wfile | grep "storage_media=" | awk -F '=' '{print $3}')
if [ "x${storage_media}" = "x" ]; then
	if is_empty_dir /sys/kernel/debug/mtd/
	then
		storage_media="init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh"
		echo "# specify storage_media" >> $wfile
		echo "storage_media=$storage_media" >> $wfile
		echo "" >> $wfile
	else
		storage_media="init=/opt/scripts/tools/Nand/init-Nand-flasher-v1.sh"
		echo "# specify storage_media" >> $wfile
		echo "storage_media=$storage_media" >> $wfile
		echo "" >> $wfile		
	fi	
fi


modprobe g_multi file=${actual_image_file} removable=1 cdrom=0 ro=0 stall=0 nofua=1 iManufacturer=embedfire iProduct=embedfire iSerialNumber=1234fire5678

$(dirname $0)/autoconfigure_usb0.sh || true