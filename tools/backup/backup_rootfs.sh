#!/bin/bash -e

_exit_trap() {
    umount ${tmp_rootfs_dir}
    rmdir ${tmp_rootfs_dir}
}

_err_trap() {
    umount ${tmp_rootfs_dir}
    rmdir ${tmp_rootfs_dir}
}

dpkg -l | grep exfat-fuse || deb_pkgs="${deb_pkgs}exfat-fuse "
dpkg -l | grep exfat-utils || deb_pkgs="${deb_pkgs}exfat-utils "

if [ "${deb_pkgs}" ] ; then
    echo "Installing: ${deb_pkgs}"
    sudo apt-get update
    sudo apt-get -y install ${deb_pkgs}
fi

tmp_rootfs_dir=/mnt/rootfs_backup

if [ $# -gt 0 ]; then
	DEV="$1"
else
    echo "please input a storage device!"
    exit 0
fi

mkfs.exfat -n rootfs $DEV

trap _exit_trap EXIT
trap _err_trap ERR

if [ ! -d ${tmp_rootfs_dir} ] ; then
    mkdir ${tmp_rootfs_dir}
fi

mount -t exfat $DEV $tmp_rootfs_dir

tar -cvf ${tmp_rootfs_dir}/rootfs.tar --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/boot} /*

cd /boot

tar -cvf ${tmp_rootfs_dir}/boot.tar .

cd -

echo "roofs backup finished!!"