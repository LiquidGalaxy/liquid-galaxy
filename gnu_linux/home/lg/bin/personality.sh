#!/bin/bash
# Copyright 2010 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [[ $UID -ne 0 ]] ; then
    echo You must run this as root.
    exit 1
fi

SCREEN=$1

if [[ ( $SCREEN -lt 1 ) || ( $SCREEN -gt 8 ) ]] ; then
    echo invalid screen number $SCREEN
    echo please choose a number 1..8
    exit 2
fi

echo lg$SCREEN > /etc/hostname

cat >/etc/network/if-up.d/99-lg_alias <<EOF
#!/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
# This file created automatically by $0
# to define an alias where lg systems can communicate
ifconfig eth0:0 10.42.42.${SCREEN} netmask 255.255.255.0
# end of file
EOF

chmod 0755 /etc/network/if-up.d/99-lg_alias

FRAME=`expr $1 - 1`

echo $SCREEN > /lg/screen
echo $FRAME > /lg/frame

echo "You may want to reboot now."
