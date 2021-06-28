#!/bin/sh -e
#. /boot/SOC.sh
#eMMC flasher just exited single user mode via: [exec /sbin/init]
#as we can't shudown properly in single user mode..
unset are_we_flasher
are_we_flasher=$(grep init-eMMC-flasher /proc/cmdline || true)
if [ ! "x${are_we_flasher}" = "x" ] ; then
	#systemctl poweroff || halt
	sudo led_demo
	exit
fi

unset are_we_flasher
are_we_flasher=$(grep init-Nand-flasher /proc/cmdline || true)
if [ ! "x${are_we_flasher}" = "x" ] ; then
	#systemctl poweroff || halt
	sudo led_demo
	exit
fi

#Regenerate ssh host keys
if [ -f /etc/ssh/ssh.regenerate ] ; then
	echo "generic-board-startup: regenerating ssh keys"
	systemctl stop sshd
	rm -rf /etc/ssh/ssh_host_* || true

	if [ -e /dev/hwrng ] ; then
		# Mix in the output of the HWRNG to the kernel before generating ssh keys
		dd if=/dev/hwrng of=/dev/urandom count=1 bs=4096 2>/dev/null
		echo "generic-board-startup: if=/dev/hwrng of=/dev/urandom count=1 bs=4096"
	else
		echo "generic-board-startup: WARNING /dev/hwrng wasn't available"
	fi

	dpkg-reconfigure openssh-server

	# while we're at it, make sure we have unique machine IDs as well
	rm -f /var/lib/dbus/machine-id || true
	rm -f /etc/machine-id || true
	dbus-uuidgen --ensure
	systemd-machine-id-setup

	sync
	if [ -s /etc/ssh/ssh_host_ed25519_key.pub ] ; then
		rm -f /etc/ssh/ssh.regenerate || true
		sync
		systemctl start sshd
	fi
fi

if [ -f /boot/efi/EFI/efi.gen ] ; then
	if [ -f /usr/sbin/grub-install ] ; then
		echo "grub-install --efi-directory=/boot/efi/ --target=arm-efi --no-nvram"
		grub-install --efi-directory=/boot/efi/ --target=arm-efi --no-nvram
		echo "update-grub"
		update-grub
		sync
	fi
	rm -rf /boot/efi/EFI/efi.gen || true
	sync
fi

#Resize drive when requested
do_expand(){
	if [ -d /home/cat/.resizerootfs ] ; then
	depmod -a
		ROOT_DEV=$(cat /proc/cmdline | sed 's/ /\n/g' | grep root= | awk -F 'root=' '{print $2}'| awk -F '/' '{print $3}')
		#${conf_root_device#/dev/}
		ROOT_DEV=${ROOT_DEV%p*}
		ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')

		PART_NUM=${ROOT_PART#${ROOT_DEV}p}
	if [ "$PART_NUM" = "$ROOT_PART" ]; then
		echo "$ROOT_PART is not an SD card. Don't expand"	
	fi

	LAST_PART_NUM=$(parted /dev/${ROOT_DEV} -ms unit s p | tail -n 1 | cut -f 1 -d:)
	if [ $LAST_PART_NUM -ne $PART_NUM ]; then
		echo "$ROOT_PART is not the last partition. Don't know how to expand"
		return 1
	fi

	# Get the starting offset of the root partition
	PART_START=$(parted /dev/${ROOT_DEV} -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
	[ "$PART_START" ] || return 1
	# Return value will likely be error for fdisk as it fails to reload the
	# partition table because the root fs is mounted
	fdisk /dev/${ROOT_DEV} <<EOF
	p
	d
	$PART_NUM
	n
	p
	$PART_NUM
	$PART_START

	p
	w
EOF
	ASK_TO_REBOOT=1

	# now set up an init.d script
	cat <<EOF > /etc/init.d/resize2fs_once &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 3
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "\$1" in
	start)
		log_daemon_msg "Starting resize2fs_once" &&
		resize2fs /dev/$ROOT_PART &&
		update-rc.d resize2fs_once remove &&
		rm /etc/init.d/resize2fs_once &&
		log_end_msg \$?
	;;
	*)
		echo "Usage: \$0 start" >&2
		exit 3
	;;
esac
EOF
	chmod +x /etc/init.d/resize2fs_once &&
	update-rc.d resize2fs_once defaults &&
	echo "Root partition has been resized.\nThe filesystem will be enlarged upon the next reboot"
	rmdir /home/cat/.resizerootfs
	mkdir /boot/dtbs/
	mkdir /boot/dtbs/overlays
	systemctl reboot
	fi
}

do_expand

unset REBOOT
#if [ -n "`find /boot/dtbs/ -maxdepth 1 -name '*.dtb'`" ] ; then
#	sudo mv /boot/dtbs/*.dtb /usr/lib/linux-image-$(uname -r)
#	REBOOT=1
#fi

#if [ -n "`find /boot/dtbs/overlays -maxdepth 1 -name '*.dtbo'`" ] ; then
#	sudo mv /boot/dtbs/overlays/*.dtbo /usr/lib/linux-image-$(uname -r)/overlays
#	REBOOT=1
#fi

if [ "x${REBOOT}" = "x1" ] ; then
	systemctl reboot
fi

if [ -d /sys/class/gpio/ ] ; then
	/bin/chgrp -R gpio /sys/class/gpio/ || true
	/bin/chmod -R g=u /sys/class/gpio/ || true

	/bin/chgrp -R gpio /dev/gpiochip* || true
	/bin/chmod -R g=u /dev/gpiochip* || true
fi

if [ -d /sys/class/leds ] ; then
	/bin/chgrp -R gpio /sys/class/leds/ || true
	/bin/chmod -R g=u /sys/class/leds/ || true

	if [ -d /sys/devices/platform/leds/leds/ ] ; then
		/bin/chgrp -R gpio /sys/devices/platform/leds/leds/ || true
		/bin/chmod -R g=u  /sys/devices/platform/leds/leds/ || true
	fi
fi

if [ -f /proc/device-tree/model ] ; then
	board=$(cat /proc/device-tree/model | sed "s/ /_/g")
	echo "generic-board-startup: [model=${board}]"

	case "${board}" in
	TI_AM335x*|Arrow_BeagleBone_Black_Industrial|SanCloud_BeagleBone_Enhanced|Octavo_Systems*)
		script="am335x_evm.sh"
		;;
	TI_AM5728*)
		script="beagle_x15.sh"
		;;
	TI_OMAP3_Beagle*)
		script="omap3_beagle.sh"
		;;
	TI_OMAP5_uEVM_board)
		script="omap5_uevm.sh"
		;;
	BeagleBoard.org_BeagleBone_AI)
		script="bbai.sh"
		;;
	Embedfire_i\.MX6ULL_Board)
		script="imx6ull_fire.sh"
		;;
	*STM32MP157*)
		script="stm32mp157_fire.sh"
		;;
	*)
		script="generic.sh"
		;;
	esac

	if [ -f "/opt/scripts/boot/${script}" ] ; then
		echo "generic-board-startup: [startup script=/opt/scripts/boot/${script}]"
		/bin/sh /opt/scripts/boot/${script}
	fi
fi
