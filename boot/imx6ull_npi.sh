#!/bin/sh -e
#
# Copyright (c) 2013-2017 Robert Nelson <robertcnelson@gmail.com>
# Copyright (c) 2019      turmary <turmary@126.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#Based off:
#https://github.com/RobertCNelson/boot-scripts/blob/master/boot/am335x_evm.sh

disable_connman_dnsproxy () {
	if [ -f /lib/systemd/system/connman.service ] ; then
		#netstat -tapnd
		unset check_connman
		check_connman=$(cat /lib/systemd/system/connman.service | grep ExecStart | grep nodnsproxy || true)
		if [ "x${check_connman}" = "x" ] ; then
			systemctl stop connman.service || true
			sed -i -e 's:connmand -n:connmand -n --nodnsproxy:g' /lib/systemd/system/connman.service || true
			systemctl daemon-reload || true
			systemctl start connman.service || true
		fi
	fi
}

if [ -f /etc/default/platform ] ; then
        unset USB_NETWORK_DISABLED
        . /etc/default/platform
fi

log="imx6ull_npi:"

usb_gadget="/sys/kernel/config/usb_gadget"

#  idVendor           0x1d6b Linux Foundation
#  idProduct          0x0104 Multifunction Composite Gadget
#  bcdDevice            4.04
#  bcdUSB               2.00

usb_idVendor="0x1d6b"
usb_idProduct="0x0104"
usb_bcdDevice="0x0404"
usb_bcdUSB="0x0200"
usb_serialnr="000000"
usb_product="USB Device"

#usb0 mass_storage
usb_ms_cdrom=0
usb_ms_ro=1
usb_ms_stall=0
usb_ms_removable=1
usb_ms_nofua=1

#original user:
usb_image_file="/var/local/usb_mass_storage.img"

if [ ! "x${usb_image_file}" = "x" ] ; then
	echo "${log} usb_image_file=[`readlink -f ${usb_image_file}`]"
fi

usb_imanufacturer="Seeed"
usb_iproduct="npi"

#mac address:
#usb_0_mac = usb0 (USB device side)
#usb_1_mac = usb0 (USB host, pc side)
usb_0_mac="1C:BA:8C:A2:ED:68"

echo "${usb_0_mac}" > /etc/usb_0_mac || true

usb_1_mac="1C:BA:8C:A2:ED:70"
echo "${usb_1_mac}" > /etc/usb_1_mac || true

echo "${log} usb_0_mac/device: [${usb_0_mac}]"
echo "${log} usb_1_mac/host  : [${usb_1_mac}]"

#udhcpd gets started at bootup, but we need to wait till g_multi is loaded, and we run it manually...
if [ -f /var/run/udhcpd.pid ] ; then
	echo "${log} [/etc/init.d/udhcpd stop]"
	/etc/init.d/udhcpd stop || true
fi

run_libcomposite () {
	udc=$(ls -1 /sys/class/udc/ | head -n 1)
	if [ -z "$udc" ]; then
		echo "No UDC driver registered"
		return 1
	fi

	# if [ ! -d /sys/kernel/config/usb_gadget/g_multi/ ] ; then
		echo "${log} Creating g_multi"
		mkdir -p /sys/kernel/config/usb_gadget/g_multi || true
		cd /sys/kernel/config/usb_gadget/g_multi

		echo "" > UDC || true
		sleep 1

		echo ${usb_bcdUSB} > bcdUSB
		echo ${usb_idVendor} > idVendor # Linux Foundation
		echo ${usb_idProduct} > idProduct # Multifunction Composite Gadget
		echo ${usb_bcdDevice} > bcdDevice

		#0x409 = english strings...
		mkdir -p strings/0x409

		echo ${usb_iserialnumber} > strings/0x409/serialnumber
		echo ${usb_imanufacturer} > strings/0x409/manufacturer
		echo ${usb_iproduct} > strings/0x409/product

		if [ ! "x${USB_NETWORK_DISABLED}" = "xyes" ]; then
			mkdir -p functions/rndis.usb0
			# first byte of address must be even
			echo ${usb_1_mac} > functions/rndis.usb0/host_addr
			echo ${usb_0_mac} > functions/rndis.usb0/dev_addr

			# Starting with kernel 4.14, we can do this to match Microsoft's built-in RNDIS driver.
			# Earlier kernels require the patch below as a work-around instead:
			# https://github.com/beagleboard/linux/commit/e94487c59cec8ba32dc1eb83900297858fdc590b
			if [ -f functions/rndis.usb0/class ]; then
				echo EF > functions/rndis.usb0/class
				echo 04 > functions/rndis.usb0/subclass
				echo 01 > functions/rndis.usb0/protocol
			fi

			# Add OS Descriptors for the latest Windows 10 rndiscmp.inf
			# https://answers.microsoft.com/en-us/windows/forum/windows_10-networking-winpc/windows-10-vs-remote-ndis-ethernet-usbgadget-not/cb30520a-753c-4219-b908-ad3d45590447
			# https://www.spinics.net/lists/linux-usb/msg107185.html
			echo 1 > os_desc/use
			echo CD > os_desc/b_vendor_code || true
			echo MSFT100 > os_desc/qw_sign || true
			echo "RNDIS" > functions/rndis.usb0/os_desc/interface.rndis/compatible_id  || true
			echo "5162001" > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id || true
		fi

		mkdir -p functions/acm.usb0

		if [ "x${has_img_file}" = "xtrue" ] ; then
			echo "${log} enable USB mass_storage ${usb_image_file}"
			mkdir -p functions/mass_storage.usb0
			echo ${usb_ms_stall} > functions/mass_storage.usb0/stall
			echo ${usb_ms_cdrom} > functions/mass_storage.usb0/lun.0/cdrom
			echo ${usb_ms_nofua} > functions/mass_storage.usb0/lun.0/nofua
			echo ${usb_ms_removable} > functions/mass_storage.usb0/lun.0/removable
			echo ${usb_ms_ro} > functions/mass_storage.usb0/lun.0/ro
			echo ${actual_image_file} > functions/mass_storage.usb0/lun.0/file
		fi

		mkdir -p configs/c.1/strings/0x409
		echo "Multifunction with RNDIS" > configs/c.1/strings/0x409/configuration

		echo 500 > configs/c.1/MaxPower

		if [ ! "x${USB_NETWORK_DISABLED}" = "xyes" ]; then
			ln -s configs/c.1 os_desc
			mkdir functions/rndis.usb0/os_desc/interface.rndis/Icons
			echo 2 > functions/rndis.usb0/os_desc/interface.rndis/Icons/type
			echo "%SystemRoot%\\system32\\shell32.dll,-233" > functions/rndis.usb0/os_desc/interface.rndis/Icons/data
			mkdir functions/rndis.usb0/os_desc/interface.rndis/Label
			echo 1 > functions/rndis.usb0/os_desc/interface.rndis/Label/type
			echo "BeagleBone USB Ethernet" > functions/rndis.usb0/os_desc/interface.rndis/Label/data
			ln -s functions/rndis.usb0 configs/c.1/
		fi
		ln -s functions/acm.usb0 configs/c.1/
		if [ "x${has_img_file}" = "xtrue" ] ; then
			ln -s functions/mass_storage.usb0 configs/c.1/
		fi

		#ls /sys/class/udc
		if [ -n "$udc" ] ; then
			echo "$udc" > UDC
		fi

		usb0="enable"
		echo "${log} g_multi Created"
	#else
	#	echo "${log} FIXME: need to bring down g_multi first, before running a second time."
	#fi
}

use_libcomposite () {
	echo "${log} use_libcomposite"
	unset has_img_file
	if [ "x${USB_IMAGE_FILE_DISABLED}" = "xyes" ]; then
		echo "${log} usb_image_file disabled by bb-boot config file."
	elif [ -f "${usb_image_file}" ] ; then
		actual_image_file=$(readlink -f ${usb_image_file} || true)
		if [ ! "x${actual_image_file}" = "x" ] ; then
			if [ -f ${actual_image_file} ] ; then
				has_img_file="true"
				test_usb_image_file=$(echo ${actual_image_file} | grep .iso || true)
				if [ ! "x${test_usb_image_file}" = "x" ] ; then
					usb_ms_cdrom=1
				fi
			else
				echo "${log} FIXME: no usb_image_file"
			fi
		else
			echo "${log} FIXME: no usb_image_file"
		fi
	else
		#We don't use a physical partition anymore...
		unset root_drive
		root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root=UUID= | awk -F 'root=' '{print $2}' || true)"
		if [ ! "x${root_drive}" = "x" ] ; then
			root_drive="$(/sbin/findfs ${root_drive} || true)"
		else
			root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root= | awk -F 'root=' '{print $2}' || true)"
		fi
	fi

	echo "${log} modprobe libcomposite"
	modprobe libcomposite || true
	if [ -d /sys/module/libcomposite ] ; then
		run_libcomposite
	elif zcat /proc/config.gz | grep "CONFIG_USB_LIBCOMPOSITE=y" > /dev/null; then
		echo "${log} libcomposite built-in"
		run_libcomposite
	else
		if [ -f /sbin/depmod ] ; then
			/sbin/depmod -a
		fi
		echo "${log} ERROR: [libcomposite didn't load]"
	fi
}

unset usb0 usb1
use_libcomposite

if [ ! "x${USB_NETWORK_DISABLED}" = "xyes" ]; then
	if [ "x${usb0}" = "xenable" ] ; then
		echo "${log} Starting usb0 network"
		# Auto-configuring the usb0 network interface:
		$(dirname $0)/autoconfigure_usb0.sh || true
	fi
fi

#Just Cleanup /etc/issue, systemd starts up tty before these are updated...
sed -i -e '/Address/d' /etc/issue || true

check_getty_tty=$(systemctl is-active serial-getty@ttyGS0.service || true)
if [ "x${check_getty_tty}" = "xinactive" ] ; then
	systemctl restart serial-getty@ttyGS0.service || true
fi

# save the random mac address if unexist
wfile="/boot/uEnv.txt"
keth0addr=$(sed -nre 's/^ *eth1addr=([0-9a-fA-F:]+) *$/\1/p' $wfile)
if [ "x${keth0addr}" = "x" ] ; then
	rndaddr=$(ip address show dev eth0 | sed -nre 's/ *link\/ether ([0-9a-fA-F:]+) .*/\1/p')
	echo "# specify kernel eth0 mac address" >> $wfile
	echo "# kernel eth0 is u-boot eth1" >> $wfile
	echo "eth1addr=$rndaddr" >> $wfile
	echo "" >> $wfile
	sync
fi

keth1addr=$(sed -nre 's/^ *ethaddr=([0-9a-fA-F:]+) *$/\1/p' $wfile)
if [ "x${keth1addr}" = "x" ] ; then
	rndaddr=$(ip address show dev eth1 | sed -nre 's/ *link\/ether ([0-9a-fA-F:]+) .*/\1/p')
	echo "# specify kernel eth1 mac address" >> $wfile
	echo "# kernel eth1 is u-boot eth0" >> $wfile
	echo "ethaddr=$rndaddr" >> $wfile
	echo "" >> $wfile
	sync
fi
#
