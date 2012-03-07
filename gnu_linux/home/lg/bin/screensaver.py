#!/usr/bin/python
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

"""
Executes applied command periodically while Space Navigator isn't touched.
It can be used to add screensaver-ish application to Liquid Galaxy.
"""

import fcntl
import os
import sys
import time

# Config
tour_check_per = 30
tour_wait_for_trigger = 4
# Input Devices
space_nav = "/dev/input/spacenavigator"
quanta_ts = "/dev/input/quanta_touch"

def Touched(dev1, dev2):
  # open file handles first
  devlist = []
  for dev in [dev1, dev2]:
    try:
      a = open(dev)
    except:
      print "Failed to open {0}".format( dev )
    else:
      devlist.append(a)

  for dev in devlist:
    fd = dev.fileno()
    fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK)

  # then sleep and let input accumulate
  time.sleep(tour_check_per)

  # then read input data, if any
  for dev in devlist:
    try:
      dev.read(6000)
      return True
    except IOError:
      pass

  # default to return False if no USB devs Touched
  return False

def main():
  if len(sys.argv) != 2:
    print "Usage:", sys.argv[0], "<command>"
    print "<command> will be called every", tour_check_per, "seconds",
    print "after", (tour_check_per * tour_wait_for_trigger), "seconds"
    print "if USB devs are not touched."
    sys.exit(1)
  
  cmd = sys.argv[1]
  cnt = 0
  while True:
    if Touched(space_nav, quanta_ts):
      cnt = 0
      print "Touched."
    else:
      cnt += 1
      if cnt >= tour_wait_for_trigger:
        print cmd
        os.system(cmd)
      else:
        print "Wait...", cnt

if __name__ == '__main__':
  main()
