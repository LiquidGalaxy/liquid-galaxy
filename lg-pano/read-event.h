#ifndef _read_event_h_
#define _read_event_h_

#include <linux/input.h>
#include <X11/Xlib.h>

#define SPNAV_MOTION 0
#define SPNAV_BUTTON 1

typedef struct {
    int type;
    int button, value;
    int x, y, z, yaw, pitch, roll;
} spnav_event;

int init_spacenav(const char *dev_name);
int get_spacenav_event(spnav_event *);

#endif
