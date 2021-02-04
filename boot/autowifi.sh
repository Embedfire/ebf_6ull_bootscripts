#!/bin/bash

rfkill unblock all

ifconfig wlan0 up

if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] ; then

  wpa_supplicant -B -c /etc/wpa_supplicant/wpa_supplicant.conf -i wlan0

fi

udhcpc -b -i wlan0
