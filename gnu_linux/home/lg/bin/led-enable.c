/*
* Copyright 2010 Google Inc.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*    http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

/*
** This turns on the LED of a 3DConnection Space Navigator device:
** $ led-enable /dev/input/spacenavigator [1|0]
** where 1 is "on" and 0 is "off"
*/

#include <sys/ioctl.h>
#include <error.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <linux/input.h>

main(int argc, char **argv) {
  
  int fd;
  int retval;
  struct input_event ev; /* the event */

  if (argc != 3) {
    printf("Usage: %s device 1|0\n", argv[0]);
    exit(2);
  }

  if ((fd = open(argv[1], O_WRONLY)) < 0) {
      perror("opening the file you specified");
      exit(1);
  }
 
  ev.type = EV_LED;
  ev.code = LED_MISC;
  ev.value = (argv[2][0] == '1') ? 1:0;
  write(fd, &ev, sizeof(struct input_event));
}
