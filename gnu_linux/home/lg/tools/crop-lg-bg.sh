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

# Helper for making a large rasterization of an SVG file and cutting
# configurable pieces out as a background for each frame piece.
# 
# Tue Jul 20 13:55:14 EDT 2010
# - Kiel C <kiel@endpoint.com>
#

trap "exit 1" INT

## VARS
IMAGE=$1
PIECES=${2:-8}
WIDTH=${3:-1200}
HEIGHT=${4:-1920}

BIGWIDTH=$(( $PIECES * $WIDTH ))
LASTXPOS=$(( $BIGWIDTH - $WIDTH ))

# grab XDG user dir vars
test -f ${XDG_CONFIG_HOME:-${HOME}/.config}/user-dirs.dirs && source ${XDG_CONFIG_HOME:-${HOME}/.config}/user-dirs.dirs

OUTPNG="${XDG_PICTURES_DIR}/$( basename $IMAGE .svg )-source.png"

## FUNC
usage() {
    echo "
I rasterize and crop an SVG image for use as an LG system background.

$0 \$image.svg [\$pieces] [\$width] [\$height]

* SVG image is required. If pieces, width, or height are
  left unspecified, (8*1200)x1900 will be assumed.
"
    exit 1
}

## PRE-REQ
if [[ ${IMAGE##*.} != "svg" ]]; then
    usage
fi
if [[ ! -x `which convert` ]]; then
    echo "FAIL: cannot execute \"convert\""
    exit 1
fi

## ACTION!
# high-quality rasterization of the SVG - takes forever
if [[ -r $OUTPNG ]]; then
    echo -n "Do you want to re-rasterize/overwrite \"$OUTPNG\"? [y/N]: "
    read rasteryesno
    if [[ $rasteryesno == "y" ]]; then
        echo -n "Rasterizing \"$IMAGE\"..."
        time rsvg-convert -f png -w ${BIGWIDTH} -o ${OUTPNG} $IMAGE
    else
        echo "okay"
    fi
else
    echo -n "Rasterizing \"$IMAGE\"..."
    time rsvg-convert -f png -w ${BIGWIDTH} -o ${OUTPNG} $IMAGE
fi

# galaxy screens arranged linearly, left-to-right would be:
# [6, 7, 8, 1, 2, 3, 4, 5]
PIECENUM=6
CURXPOS=0

while [[ $CURXPOS -le $LASTXPOS ]]; do

    # see the comment for "PIECENUM"
    if [[ $PIECENUM -gt 8 ]]; then
        PIECENUM=$( echo "$PIECENUM - 8" | bc )
    fi
    PIECEOUT="${XDG_PICTURES_DIR}/backgrounds/lg-bg-${PIECENUM}.png"

    echo -n "Cropping piece \"$PIECENUM\"..."
    if( convert -crop ${WIDTH}x${HEIGHT}+$CURXPOS $OUTPNG ${PIECEOUT} ); then
        echo success\!
        ls -lFa ${PIECEOUT}
        let CURXPOS+=$WIDTH
        let PIECENUM+=1
    else
        echo "fail. Did the rasterize step fail?"
    fi
done

exit 0
