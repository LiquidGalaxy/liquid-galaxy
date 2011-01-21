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

. ${HOME}/etc/shell.conf

echo "$(date +%s) $0 running."

# kill any other copies
ME="`basename $0`"

pkill `pidof -x -o '%PPID' $ME`

killall googleearth-bin
sleep 2

export DISPLAY=:0.0
export __GL_SYNC_TO_VBLANK=1  # broken for nvidia when rotating screen

cd ${SCRIPDIR} || exit 1
echo "running write drivers"
./write-drivers-ini.sh

if [[ "`cat /lg/frame`" -eq 0 ]] ; then
    DIR=master
else
    DIR=slave
fi
cp -a ${EARTHDIR}/config/$DIR/* ${HOME}/.config/Google/
  
while true ; do
    if [[ "$DIR" == "master" ]]; then
        lg-run killall googleearth-bin
    fi
    [ -w $SPACENAVDEV ] && ${HOME}/bin/led-enable ${SPACENAVDEV} 1

    cd ${EARTHDIR}/builds/latest
    rm -f ${HOME}/.googleearth/Cache/db* # important: otherwise we get random broken tiles
    rm -rf ${HOME}/.googleearth/Temp/*
    rm -f /tmp/query.txt
    # push mouse over to touchscreen interface
    DISPLAY=:0 xdotool mousemove -screen 1 1910 1190
    echo "running earth"
#    PLANET="`cat /lg/planet`"
#    ${SCRIPDIR}/set-planet.sh $PLANET
    ./googleearth -style cleanlooks --fullscreen

    [ -w $SPACENAVDEV ] && ${HOME}/bin/led-enable ${SPACENAVDEV} 0
    sleep 5
done
