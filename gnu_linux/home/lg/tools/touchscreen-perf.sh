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

## Use this script to simulate semi-random and impatient
## user tapping on the touchscreen PHP interface.

# create array(s?) for planet selection
PLANET_X=(
    595
    837
    1085
)
PLANET_Y=239

# set a floor value for each axis
FLOOR_X=238
FLOOR_Y=120
# set a range value for each axis
RANGE_X=1684
RANGE_Y=877

if [[ -z "$1" ]]; then
    echo "I need a sleep value"
    exit 1
else
    SLEEPVAL=$1
fi
if [[ -z "$DISPLAY" ]]; then
    echo "set DISPLAY variable"
    exit 1
fi

# loop forever clicking on new coordinates
while :; do
    # initialize planet index
    PLANET=0
    # initialize starting coordinate for each axis
    COORD_X=0
    COORD_Y=0

    # planet selection first
#    PLANETS=${#PLANET_X[@]}
#    let "PLANET = $RANDOM % $PLANETS"

#    echo -n "Moving mouse to X:${PLANET_X[$PLANET]}, Y:${PLANET_Y}."
#    xdotool mousemove --screen 1 ${PLANET_X[$PLANET]} ${PLANET_Y}
#    echo ".click!"
#    xdotool click 1

    # now random click
    while [[ ${COORD_X} -le ${FLOOR_X} ]]; do
        # find random coordinate on X axis
        COORD_X=$RANDOM
        let "COORD_X %= ${RANGE_X}"
    done
    while [[ ${COORD_Y} -le ${FLOOR_Y} ]]; do
        # find random coordinate on Y axis
        COORD_Y=$RANDOM
        let "COORD_Y %= ${RANGE_Y}"
    done

    echo -n "Moving mouse to X:${COORD_X}, Y:${COORD_Y}."
    xdotool mousemove --screen 1 ${COORD_X} ${COORD_Y}
    echo ".click!"
    xdotool click 1

    sleep $SLEEPVAL
done

