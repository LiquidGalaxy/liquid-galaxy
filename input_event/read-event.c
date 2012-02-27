// Released into the public domain, 4 Mar 2011
// Google, Inc. Jason E. Holt <jholt [at] google.com>
//
// Simple example of how to read and parse input_event structs from device
// files like those found in /dev/input/event* for multi-axis devices such
// as the 3dconnexion Space Navigator.
//
// Our navigator shows up as:
// Bus 007 Device 004: ID 0510:1004 Sejin Electron, Inc.

#include <sys/ioctl.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <linux/input.h>

main(int argc, char **argv) {

  int fd;

  if (argc != 2) {
    printf("Usage: %s multi-axis-device-file\n", argv[0]);
    exit(2);
  }

  if ((fd = open(argv[1], O_RDONLY | O_NONBLOCK)) < 0) {
    perror("opening the file you specified");
    exit(1);
  }

  int x, y, z, yaw, pitch, roll;
  x = y = z = yaw = pitch = roll = 0;

  while(1) {
    struct input_event ev;
    struct input_event *event_data = &ev;
    int num_read = read(fd, event_data, sizeof(ev));

    if (sizeof(ev) != num_read) {
      usleep(100000);
      continue;
    } else {
    }

    if (event_data->type == EV_MSC) {
      printf("Misc Type: %u Value: %d\n", event_data->code, event_data->value);

    } else if (event_data->type == EV_KEY) {
      printf("Key/Button: %u State: %d\n", event_data->code, event_data->value);

    } else if (event_data->type == EV_SYN) {
      // EV_SYN type may be quite useful for some devices
      // identifies the sent data complete and therefore apply-able
      printf("Sync Event\n");

    } else if (event_data->type == EV_REL ||
               event_data->type == EV_ABS) {

      int axis = event_data->code;
      int amount = event_data->value;

      printf("Axis: %u Amount: %d\n", axis, amount);

      switch(axis) {
        case 0:
          x = amount;
          break;
        case 1:
          y = amount;
          break;
        case 2:
          z = amount;
          break;
        case 3:
          pitch = amount;
          break;
        case 4:
          roll = amount;
          break;
        case 5:
          yaw = amount;
          break;
        default:
          printf("unknown axis event\n");
          break;
      }

      printf("Most recent values: x=%d,y=%d,z=%d,yaw=%d,pitch=%d,roll=%d\n",
             x,y,z,yaw,pitch,roll);
    } else {
      int evtype = event_data->type;

      printf("Unknown event type \"%u\".\n", evtype);
    }
  }
}
