// Released into the public domain, 4 Mar 2011
// Google, Inc. Jason E. Holt <jholt [at] google.com>
//
// Create synthetic input_event structs for a multi-axis device.
//
// Compile with:
// $ gcc -m32 -o write-event write-event.c
// (Earth is compiled as a 32-bit binary, so we compile with -m32)


#include <sys/ioctl.h>
#include <error.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <linux/input.h>

main(int argc, char **argv) {
  if (argc != 4) {
    printf("Usage: %s fifo axis amount\n\n", argv[0]);

    printf("Populates an input_event struct and writes it to the file\n"
           "fifo (which will generally be a named pipe), with type set\n"
           "to EV_REL, code set to axis (0,1,2,3,4,5 = x,y,z,pitch,yaw,roll)\n"
           "and amount set to the specified (integer) amount.\n\n"
           "Example: %s my-named-pipe 0 100\n"
           " writes a relative input_event with x=100\n\n"
           "Example: %s my-named-pipe 3 -10\n"
           " writes a relative input_event with pitch=-10\n",
           argv[0], argv[0]
           );
    exit(2);
  }

  int fd;
  if ((fd = open(argv[1], O_WRONLY)) < 0) {
    perror("opening the file you specified");
    exit(1);
  }

  int axis = atoi(argv[2]);
  int amount = atoi(argv[3]);

  struct input_event ev;
  struct input_event *event_data = &ev;

  struct timeval timestamp;

  gettimeofday(&timestamp, NULL);
  ev.time = timestamp;
  ev.type = EV_REL;
  ev.value = amount;
  ev.code = axis;

  printf("Writing an input_event with type=EV_REL, value=%d and code=%d\n",
         ev.value, ev.code);

  write(fd, event_data, sizeof(ev));
  printf("Done.\n");
  close(fd);
}
