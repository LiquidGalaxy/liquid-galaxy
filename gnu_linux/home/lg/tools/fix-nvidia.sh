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

# IF using DKMS for the nvidia kernel module allows for
# the latest driver to be used painlessly with changing kernels.
# However, if mesa packages are updated, the nvidia LIBRARY symlinks
# get overwritten. These libraries need to be managed separately, 
# which is also pretty painless, if just a little unexpected.
#
# Tue Jul 20 13:55:14 EDT 2010
# - Kiel C <kiel@endpoint.com>
#

NVINSTALL=${1:-~lg/downloads/NVIDIA-Linux-x86_64-256.35.run}

USERID=$(id -u)
# exit now if we do not have root privs
if [[ $USERID -ne 0 ]]; then
    echo "You need root privileges to do anything with this."
    exit 3
fi

# always perform sanity check and collect return value
$NVINSTALL --sanity --silent
SANITY=$?

if [[ $SANITY -ge 1 ]]; then
    echo "APPEARS UN-SANE!"
    # execute silent library installation
    $NVINSTALL -a -N -n --no-kernel-module --no-x-check --silent 
    exit $?
else
    echo "APPEARS SANE!"
    exit $SANITY
fi
