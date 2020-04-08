#! /bin/bash

kernel_dir=$(uname -r)
echo $kernel_dir

cat /etc/modules | grep -i "touch-gt9xx.ko"
if [ $? -ne 0 ] ;then
    echo "touch-gt9xx" >> /etc/modules
    sudo insmod /lib/modules/$kernel_dir/kernel/drivers/input/touch-gt9xx.ko
fi
cat /etc/modules | grep -i "imx-wm8960.ko"
if [ $? -ne 0 ] ;then
    echo "imx-wm8960.ko" >> /etc/modules
    sudo insmod /lib/modules/$kernel_dir/kernel/drivers/input/imx-wm8960.ko
fi
cat /etc/modules | grep -i "ov5640_v2.ko"
if [ $? -ne 0 ] ;then
    echo "ov5640_v2.ko" >> /etc/modules
    sudo insmod /lib/modules/$kernel_dir/kernel/drivers/i2c/ov5640_v2.ko
fi

cd /lib/modules/$kernel_dir/ && sudo depmod -a && cd -

sudo rm -rf /var/lib/alsa/asound.state
cd /lib/modules/$kernel_dir/kernel/drivers/input && aplay -l && sudo alsactl restore -f asound.state && cd -

sudo systemctl mask solve_qt_deb.service
