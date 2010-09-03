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

# !!! This DoS-in-a-script is meant to completely fill empty disk space with
# zeros which will allow the entire contents of the disk to be better
# compressed. (think network imaging)
#
# Tue Jul 20 13:55:14 EDT 2010
# - Kiel C <kiel@endpoint.com>
#

# manually create the container dir if you want this
# to succeed
container=/tmp/zero

trap ask_and_clear INT

ask_and_clear() {
	echo -n "would you like to remove \"$container\" now? [y/N] "
	read rmyesno
	if [[ "$rmyesno" == "y" ]]; then
		if [[ $(id -u) == 0 ]]; then
			echo "sorry, not going to execute \"rm -rf $container\" as root."
			exit 1
		else
			rm -rf $container
			exit $?
		fi
	else
		echo "okay."
		exit 0
	fi
}
	

for file in `seq -w 0001 9999`; do 
	if touch /tmp/zero/$file.zero; then
		if dd if=/dev/zero of=/tmp/zero/$file.zero bs=1k count=2048000; then
			:
		else
			echo "FAIL: disk full? Be sure to remove \"$container\"."
			ask_and_clear
			exit 1
		fi
	else
		echo FAIL
		exit 1
	fi
done
