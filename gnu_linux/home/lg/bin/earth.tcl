#!/usr/bin/wish
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

## small Tcl/Tk window to provide search functionality
# * IR remote via serial
# * "kiosk" keyboard

set serialport [open /dev/ttyS0 w+]
fconfigure $serialport \
  -mode 1200,n,8,1 -buffering none -blocking 0 -buffersize 2 \
  -translation {binary binary}

. configure -bg white
label .welcome -text "Welcome to Liquid Galaxy" -bg white
pack .welcome

#label .remote -text "Use the remote or speak into the mic:" -bg white
#pack .remote

#label .options -text "Press 1 for Earth, 2 for Mars, 3 for Moon" -bg white
#pack .options

set listenprompt "...LISTENING: speak loudly into mic..."

label .incoming -text $listenprompt -bg white -fg blue
#pack .incoming

label .loading -text "X" -bg white
pack .loading

label .search -text "Use keyboard to search: " -bg white
pack .search

entry .searchbox -width 49 -textvariable query
pack .searchbox
focus .searchbox
bind .searchbox <Return> {
  set queryfile [open "/tmp/query.txt" "w"]
  switch -regexp $query {

    {(?i)^earth$} {
      puts -nonewline $queryfile "planet=earth"
    }
   
    {(?i)^mars$} {
      puts -nonewline $queryfile "planet=mars"
    }

    {(?i)^moon$} {
      puts -nonewline $queryfile "planet=moon"
    }

    default {
      puts -nonewline $queryfile "search=$query"
    }
  }
  close $queryfile
  set query ""
}

label .searchhelp1 -text "Examples: london, angkor wat," -bg white -fg grey
pack .searchhelp1
label .searchhelp2 -text "123 maple 94043, pizza, etc." -bg white -fg grey
pack .searchhelp2


set update_counter 0
wm geometry . =360x150+10+1750

proc keep_on_top {} {
  global update_counter
  incr update_counter
  raise .
  focus -force .searchbox
  wm geometry . =360x150+[expr 10 + ($update_counter/2 % 700)]+1750
  after 3000 keep_on_top
}
keep_on_top

proc loader {command arg timeout} {
  
  .loading configure -text "Loading..." -fg red
  update
  exec $command $arg ">/dev/null" "2>/dev/null"
  after $timeout
  .loading configure -text ""
  update
}

proc execute_remote {c} {
  switch -- $c {

    "\x15" { # keypad 1
      puts -nonewline $queryfile "planet=earth"
    }
   
    "\x16" { # keypad 2
      puts -nonewline $queryfile "planet=mars"
    }

    "\x14" { # keypad 3
      puts -nonewline $queryfile "planet=moon"
    }

    default {
    }
  }
}

set last_serial_char 0
set last_command 0
proc read_remote {} {
  global last_serial_char
  global serialport
  global last_command

  set c [read $serialport 1]
  if { $c != $last_serial_char } {
    set last_serial_char $c
    set last_command 0
    return
  }
  set last_serial_char $c

  if {$c == $last_command} { 
    return 
  }
  set last_command $c

  #scan $c %c ord
  #puts "$ord"

  execute_remote $c
}


fileevent $serialport readable read_remote

