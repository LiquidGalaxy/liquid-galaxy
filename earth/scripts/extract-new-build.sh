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

# 
# Helper for extracting new builds
# 
# Tue Jul 20 13:55:14 EDT 2010
# - Kiel C <kiel@endpoint.com>
#

# grab XDG user dir vars
test -f ${XDG_CONFIG_HOME:-${HOME}/.config}/user-dirs.dirs && source ${XDG_CONFIG_HOME:-${HOME}/.config}/user-dirs.dirs

TMPROOT=${TMPDIR:-/tmp}
BUILDBIN="${XDG_DOWNLOAD_DIR}/GoogleEarthLinux.bin"
BUILDDIR="${HOME}/earth/builds"

# Test earth build binary and find version
if [[ -r $BUILDBIN ]]; then
    BUILDVER=$( head -n 10 $BUILDBIN | awk '/^label=/ { gsub (/\"+$/,"",$NF); print $NF}' )
    # Also make it executable
    if [[ ! -x $BUILDBIN ]]; then
        chmod -v +x $BUILDBIN
    fi
else
    echo "$0: Cannot read: \"${BUILDBIN}\"."
    exit 1
fi

# create target from version
echo -n "** Checking for build directories..."
if [[ ! -d ${BUILDDIR}/${BUILDVER} ]]; then
    mkdir -p ${BUILDDIR}/${BUILDVER} || exit 1
    echo -n "created..."
else
    echo -n "already exists..."
fi
echo "ok."

# pull data files out
if [[ -x $BUILDBIN ]]; then
    echo -n "** Selecting data files to extract (googleearth-*.tar)... "
    GRABFILES=$( $BUILDBIN --tar tf | awk '/.*googleearth(.*\.tar)?$/ {print $NF}' )
    echo "found: ${GRABFILES[*]}"
    echo -n "** Extracting selected data files to temp dir: \"${TMPROOT}\"... "
    $BUILDBIN --tar xpvf -C $TMPROOT ${GRABFILES[*]}
    echo "done."
else
    echo "$0: Cannot execute: \"${BUILDBIN}\"."
    exit 1
fi

if pushd $TMPROOT; then
    echo -n "** Extracting/moving data to target: \"${BUILDDIR}/${BUILDVER}\" ..."
    for file in ${GRABFILES[*]}; do
        if [[ -x $file ]]; then
            mv -vui $file ${BUILDDIR}/${BUILDVER}/
        else
            # cleanup with exit trap?
            tar xpf $file -C ${BUILDDIR}/${BUILDVER} || exit 1
        fi
    done
    echo "ok"
else
    echo "$0: Cannot change to: \"${TMPROOT}\"."
    # cleanup files with exit trap?
    exit 1
fi


echo "** Finished extracting version: \"${BUILDVER}\".
  Next, be sure you have a \"${HOME}/earth/builds/latest\" symlink!
  Right now, the link is as follows:"
  stat -c %N ${HOME}/earth/builds/latest

exit 0
