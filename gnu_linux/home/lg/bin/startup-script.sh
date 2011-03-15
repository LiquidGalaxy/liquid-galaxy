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

echo "DISPLAY = \"$DISPLAY\"."
echo "DISPLAY_portion = \"${DISPLAY##*\.}\"."

. ${HOME}/etc/shell.conf

FRAME_NO="$(cat /lg/frame)"

echo "MY FRAME = \"${FRAME_NO}\"."

if [[ $FRAME_NO = 0 ]]; then
    # a kiosk browser-based experience on a second display, 
    # and the earth.tcl search interface below are mutually exclusive.
    # -- uncomment the one you like --
    if [[ "${DISPLAY##*\.}" = "1" ]]; then
        echo "launching kiosk browser on second screen"
        sed -i -e 's/exited_cleanly.*/exited_cleanly\":\ true,/' ${HOME}/.config/chromium/Default/Preferences && \
        rm -f ${HOME}/.config/chromium/Singleton*
        gnome-www-browser --disable-session-storage --kiosk --no-first-run localhost:81 &
        exit
    fi

    nitrogen --set-zoom-fill ${XDG_PICTURES_DIR}/backgrounds/lg-bg-${FRAME_NO}.png &
    ${SCRIPDIR}/launch-earth.sh &
    sleep 3
#    ${HOME}/bin/earth.tcl &
elif [[ $FRAME_NO -ge 1 ]]; then
    nitrogen --set-zoom-fill ${XDG_PICTURES_DIR}/backgrounds/lg-bg-${FRAME_NO}.png &
else
    # will wait up to 9 seconds in increments of 3
    # to get an IP
    IP_WAIT=0
    
    nitrogen --set-tiled ${XDG_PICTURES_DIR}/backgrounds/lg-bg-noframe.png &

    while [[ $IP_WAIT -le 9 ]]; do
        PRIMARY_IP="$(ip addr show dev eth0 primary | awk '/inet\ / { print $2}')"
        if [[ -z $PRIMARY_IP ]]; then
            let IP_WAIT+=3
            sleep 3
        else
            break
        fi
    done

    # notify user
    xmessage \
"\"Personality\" assignment is _essential_
My primary IP address: $PRIMARY_IP

Utilize ${HOME}/bin/personality.sh with root priv."
fi

