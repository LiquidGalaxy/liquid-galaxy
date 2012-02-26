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

logger -p local3.info -i "$0: running at $(date +%s)"

# kill any other copies
ME="`basename $0`"
MEPIDS="$( pidof -x -o '%PPID' $ME )"
for pid in ${MEPIDS}; do
    pkill -u $(id -u) $pid
done

pkill -u $(id -u) googleearth-bin
sleep 2

if [[ "$( id -un )" == "lg" ]]; then
    for screen in /home/lgS*; do
        if [[ -d ${screen} ]]; then
            screennum=${screen##/home/lgS}
            logger -p local3.info -i "$0: launching $ME for my screen \"${screennum}\""
            sudo -u lgS${screennum} -H DISPLAY=:0.${screennum} ${SCRIPDIR}/${ME} ${@} &
            unset screennum
        fi
    done
fi

[[ -n "${DISPLAY}" ]] || export DISPLAY=:0.0
[ ${DISPLAY##*\.} -ne 0 ] && export SCREEN_NO=${DISPLAY##*\.}
export __GL_SYNC_TO_VBLANK=1  # broken for nvidia when rotating screen

cd ${SCRIPDIR} || exit 1
logger -p local3.info -i "$0: running write drivers. S:\"${SCREEN_NO}\"."
./write-drivers-ini.sh

if [ $FRAME_NO -eq 0 ] ; then
    DIR=master
else
    DIR=slave
fi

MYCFGDIR="${CONFGDIR}/${DIR}"
# build the configuration file
m4 -I${MYCFGDIR} ${MYCFGDIR}/GECommonSettings.conf.m4 > ${MYCFGDIR}/$( basename `readlink ${MYCFGDIR}/GECommonSettings.conf.m4` .m4 )
# copying files AND potentially symlinks here
mkdir -m 775 ${HOME}/.config/Google
mkdir -m 700 ${HOME}/.googleearth
cp -a ${MYCFGDIR}/*        ${HOME}/.config/Google/
cp -a ${LGKMLDIR}/${DIR}/* ${HOME}/.googleearth/
# expand the ##HOMEDIR## var in configs
sed -i -e "s:##HOMEDIR##:${HOME}:g" ${HOME}/.config/Google/*.conf
# expand LG_PHPIFACE (may contain ":" and "/") in kml files
sed -i -e "s@##LG_PHPIFACE##@${LG_PHPIFACE}@g" ${HOME}/.googleearth/*.kml

while true ; do
    if [[ "$DIR" == "master" ]]; then
        lg-sudo killall googleearth-bin
    fi
    [ -w $SPACENAVDEV ] && ${HOME}/bin/led-enable ${SPACENAVDEV} 1

    cd ${BUILDDIR}/${EARTH_BUILD}
    rm -f ${HOME}/.googleearth/Cache/db* # important: otherwise we get random broken tiles
    rm -rf ${HOME}/.googleearth/Temp/*
    rm -f ${EARTH_QUERY:-/tmp/query.txt}
    # shove mouse over to touchscreen interface
    if [[ "$DIR" == "master" ]]; then
        # use the touchscreen
        DISPLAY=:0 xdotool mousemove -screen 1 1910 1190
    else
        # lock the keyboard and mouse
        DISPLAY=:0 xtrlock & DISPLAY=:0 xdotool mousemove -screen 0 1190 1910
    fi
    logger -p local3.info -i "$0: running earth"
    ./googleearth -style cleanlooks --fullscreen -font '-adobe-helvetica-bold-r-normal-*-3-*-*-*-p-*-iso8859-1'
    # Normally use TINY font size to make the menu bar small and unobtrusive, but error windows become unreadable.
    # use the below execution for large font. (qt4 is supposed to ignore '-font' if built with freetype support).
    #./googleearth -style cleanlooks --fullscreen -font '-adobe-helvetica-bold-r-normal-*-16-*-*-*-p-*-iso8859-1'

    [ -w $SPACENAVDEV ] && ${HOME}/bin/led-enable ${SPACENAVDEV} 0
    sleep 3
done
