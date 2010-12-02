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
check_per = 40
wait_for_trigger = 2

def Touched(path):
  f = open(path)
  fd = f.fileno()
  fcntl.fcntl(fd, fcntl.F_SETFL, os.O_NONBLOCK)
  time.sleep(check_per)
  try:
    f.read(10000)
    return True
  except:
    return False

def main():
  if len(sys.argv) != 2:
    print "Usage:", sys.argv[0], "<command>"
    print "<command> will be called every", check_per, "seconds",
    print "after", (check_per * wait_for_trigger), "seconds"
    print "if spacenavigator is not touched."
    sys.exit(1)
  
  cmd = sys.argv[1]
  cnt = 0
  while True:
    if Touched("/dev/input/spacenavigator"):
      cnt = 0
      print "Touched."
    else:
      cnt += 1
      if cnt >= wait_for_trigger:
        print cmd
        os.system(cmd)
      else:
        print "Wait...", cnt

if __name__ == '__main__':
  main()
