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
#include <error.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <linux/input.h>
#include <unistd.h>
#include "read-event.h"

int spacenav_fd;

int init_spacenav(const char *dev_name)
{
	if ((spacenav_fd = open(dev_name, O_RDONLY | O_NONBLOCK)) < 0) {
		perror("Unable to open spacenav input device");
		return 0;
	}
	return 1;
}

int get_spacenav_event(spnav_event * p)
{
	int x, y, z, yaw, pitch, roll;
	x = y = z = yaw = pitch = roll = 0;
	struct input_event ev;
	struct input_event *event_data = &ev;

	int num_read = read(spacenav_fd, event_data, sizeof(ev));

	if (sizeof(ev) != num_read) {
		return 0;
	}

//    fprintf(stderr, "time.tv_sec: %ld, time.tv_usec: %ld, type: %d, code: %d, value: %d\n",
//        event_data->time.tv_sec,
//        event_data->time.tv_usec,
//        event_data->type,
//        event_data->code,
//        event_data->value);

	if (event_data->type == EV_KEY) {
        p->type = 1;
        p->button = event_data->code - BTN_0;
        p->value = event_data->value;
		return 1;

	} else if (event_data->type == EV_SYN) {
        // These events indicate the data from the spacenav has been flushed to
        // the host computer. Ignore these for now.
		return 0;

	} else if (event_data->type == EV_REL || event_data->type == EV_ABS) {
		int axis = event_data->code;
		int amount = event_data->value;

		switch (axis) {
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
			fprintf(stderr, "unknown axis event\n");
			break;
		}
        p->type = SPNAV_MOTION;
		p->x = yaw;
		p->y = -pitch;
		p->z = y*-1;
		p->yaw = x;
		p->pitch = pitch;
		p->roll = roll;

		return 1;

	} else if (event_data->type == EV_MSC) {
        // These can be ignored, it seems. The SourceForge spacenav driver ignores them anyway.
        return 0;
	} else {
		int evtype = event_data->type;

		fprintf(stderr, "Unknown event type \"%d\".\n", evtype);
		return 0;
	}
	return 1;
}
