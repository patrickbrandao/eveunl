#!/bin/sh

#
# Script que coloca o nome das ETHs baseada na ordem alfabetica dos MAC address
#

c=0

cat /proc/net/dev \
  | cut -f1 -d: \
    | grep eth \
      | sort \
        | while read x; do mac=$(head -1 /sys/class/net/$x/address); echo $mac; done \
          | sort \
            | while read mac; do x="eth$c"; echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$mac\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"$x\""; c=$(($c+1)); done \
            > /etc/udev/rules.d/70-persistent-net.rules
