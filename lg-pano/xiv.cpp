/*
  Copyright (c) 2010, Gilles BERNARD lordikc at free dot fr
  All rights reserved.
  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
  * Neither the name of the Author nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdio.h>
#include <stdint.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/cursorfont.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xdbe.h>
#include <math.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <libgen.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include "xiv.h"
#include "xiv_utils.h"
#include "xiv_readers.h"
#include "read-event.h"

#define MAX_SLAVES 30
#define SLAVE_ADDR_LEN 100

// X11 global variables
pthread_mutex_t mutexWin = PTHREAD_MUTEX_INITIALIZER;    // Mutex protecting the window
Display *display;
Window window;
Visual *visual;
int screen;
int depth;
GC gc;
XImage *image = NULL;
//Pixmap pixmap;
XdbeBackBuffer d_backBuf;
Drawable drawable;
bool can_double_buff = false;     // Whether we've decided we can use double buffering with Xdbe
bool do_double_buff = true;       // Should we double-buffer if we can?
int major, minor;
Cursor watch;             // Wait cursor
Cursor normal;            // Normal cursor
Atom wmDeleteMessage;
bool fullscreen = false;
bool fakewin = false;

// Threads
pthread_t th;             // Drawing thread
pthread_t *thFill = 0;    // Sub drawing threads
pthread_t thFifo;         // Pipe control thread
pthread_t thSpacenav;     // Spacenav control thread
pthread_t thUDPSlave;     // UDP slave control thread
pthread_t thUDPMaster;    // UDP master control thread
pthread_t thPreload;      // Preload image thread

#ifdef WATCHDOG
pthread_t thWatchdog;     // Watchdog to restart thFill if needed
pthread_mutex_t watchdog_mutex = PTHREAD_MUTEX_INITIALIZER;
#endif

// Drawing 
pthread_mutex_t mutexData = PTHREAD_MUTEX_INITIALIZER;    // Mutex protecting the data array
int w, h;
int wref = -1;
int href = -1;
int ox, oy;
unsigned char *data = NULL;

// Display characteristics
float dx = 0;            // Translation
float dy = 0;
float z = 1;             // Zoom
float a = 0;             // Rotation
float zoom_max = 16;     // Maximum zoom factor
float minz = 2.5;
float maxz = 10;
bool autorot = true;
int lu = 0;              // Luminosity
int cr = 255;            // Contrast
float gm = 1;            // Gamma
int osdSize = 256;

// Position buffer
typedef struct {
    float dx, dy, z, a;
    Image *imgCurrent;
} pos_buf;
pos_buf fillState;

// Current image
Image *imgCurrent = 0;

// Image cache
int CACHE_NBIMAGES = 5;
pthread_mutex_t mutexCache = PTHREAD_MUTEX_INITIALIZER;    // Mutex protecting the cache
Image **imgCache;
int idxCache = 0;

// FIFO file name
char *fifo = NULL;

bool revert = false;              // Use reverse video
bool bilin = false;               // Use bilinear interpolation (true) or nearest neighbour (false)
bool bilinMove = false;
bool displayHist = false;         // Display histogram
bool displayQuickview = false;    // Display overview
bool refresh = false;             // Need a window refresh
bool run = true;                  // Keeping running while it's true

// Histogram of current image
int histMax;
int histr[256];
int histg[256];
int histb[256];

typedef struct {
    char host[SLAVE_ADDR_LEN];
    int port;
    bool broadcast;
} slavehost;

// File list
#define MAX_NBFILES 32768
char **files = 0;
int nbfiles = 0;
int idxfile = 0;
bool shuffle = false;

// Control
bool h360 = false;
bool spacenav = false;
float spsens = 3.0;
int swapaxes = 1;
char *spdev = NULL;
int xoffset = 0, yoffset = 0;

#ifdef WATCHDOG
int watchdog_counter = 0;
#endif

// X attributes
char *win_name = NULL;
char *win_class = NULL;

// Sync and network stuff
slavehost slavehosts[MAX_SLAVES];
int num_slaves = 0;
int num_allocd_slaves = 0;
char *listenaddr = NULL;
int listenport = 0;
bool slavemode = false;
bool multicast = false;

// values of powf(x,powe) for x between 0 and 1 to speed up calculation.
int powv[256];
float powe = 0;

// Nb of cores available
int ncores = 0;
int *fillBounds = NULL;

// Zoom on zone
int zx1 = 0, zx2 = 0, zy1 = 0, zy2 = 0;
bool displayZone = false;

// Points
float pts[20];
const char *ptsNames[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" };

bool displayPts = true;
int crossSize = 4;

bool displayGrid = false;
int ncells = 12;

bool verbose = false;

bool displayAbout = false;
const char *about = " xiv " VERSION " (c) Gilles BERNARD lordikc@free.fr ";

void usage(const char *prog)
{
    char *progn = basename(strdup(prog));
    fprintf(stderr, "%s v%s\n", progn, VERSION);
    fprintf(stderr, "Usage %s [options] file1 file2...\n", progn);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "   -geometry widthxheight+ox+oy, default is screen size\n");
    fprintf(stderr, "   -fakewin Don't create a window, but do pretend to have a window (must specify -geometry)\n");
    fprintf(stderr, "   -threads # threads, default is to auto-detect # of cores.\n");
    fprintf(stderr, "   -cache # images (default 5).\n");
    fprintf(stderr, "   -no-autorot Disable auto rotate according to EXIF tags.\n");
    fprintf(stderr, "   -overview Display overview.\n");
    fprintf(stderr, "   -fullscreen.\n");
    fprintf(stderr, "   -histogram Display histogram.\n");
    fprintf(stderr, "   -grid Display grid.\n");
    fprintf(stderr, "   -browse expand the list of files by browsing the directory of the first file.\n");
    fprintf(stderr, "   -shuffle file list.\n");
    fprintf(stderr, "   -bilinear Turn on bilinear interpolation.\n");
    fprintf(stderr, "   -fifo filename for incoming commands, default is no command file.\n");
    fprintf(stderr, "   -xoffset/yoffset ##  The number of pixels to offset the image in the X/Y direction\n");
    fprintf(stderr, "   -nodoublebuf don't use Xdbe double buffering, even if it's available\n");
//    fprintf(stderr, "   -xthreads tell X11 we're using threads. This may cause, or possibly cure, hanging problems\n");
    fprintf(stderr, "   -h360 treat photos as 360 panoramas horizontally. Scrolling off either side causes the image to repeat\n");
    fprintf(stderr, "   -maxzoom ## maximum zoom factor\n");
    fprintf(stderr, "   -spacenav use space navigator at /dev/input/spacenavigator for direction\n");
    fprintf(stderr, "   -spsens ## Change spacenav sensitivity. Higher numbers mean less sensitivity. Default is 3.\n");
    fprintf(stderr, "   -swapaxes Change spacenav axes so pushing the spacenav left moves the image right, etc.\n");
    fprintf(stderr, "   -spdev <dev> the device name for the spacenav (default: /dev/input/spacenavigator)\n");
    fprintf(stderr, "   -listenport <port> port to listen on for UDP synchronization traffic. Setting either this or listenaddr will disable mouse, keyboard, and spacenav input on this system. For predictable behavior, listenaddr or listenport should be the first option on the command line, if either is used.\n");
    fprintf(stderr, "   -listenaddr <addr> address to listen on for UDP synchronization traffic to. Will default to 0.0.0.0 if unspecified, and -listenport is used.\n");
    fprintf(stderr, "   -slavehost <host>:<port> address to send UDP synchronization traffic to, or to listen on. Can be a multicast group. Can be repeated to send traffic to multiple addresses, up to a maximum of %d slaves. Useful only when -listenaddr and -listenport are not used\n", MAX_SLAVES);
    fprintf(stderr, "   -broadcast include this option if the last -slavehost option on the command line thus far is a broadcast address. Not useful on slave instances.\n");
    fprintf(stderr, "   -multicast Use this option if the -listenaddr is a multicast address. Only useful on slave instances.\n");
    fprintf(stderr, "   -winname <NAME> Set the window name to NAME\n");
    fprintf(stderr, "   -winclass <NAME> Set the window class to NAME\n");
    fprintf(stderr, "   -v verbose.\n");
    fprintf(stderr, "       Commands are:\n");
    fprintf(stderr, "         o l filename: load a new image\n");
    fprintf(stderr, "         o z zoom_level: if zoom_level <0 fit image in window\n");
    fprintf(stderr, "         o c x y: Center view on (x,y) (image pixel coordinates system)\n");
    fprintf(stderr, "         o m x y: Move view of (x,y) (image pixel coordinates system)\n");
    fprintf(stderr, "         o q: quit\n");
    fprintf(stderr, "%s is a very simple and lightweight image viewer without UI but a X11 window and only controled by keys and mouse.\n", progn);
    fprintf(stderr, "As opposed to most of the image viewers, it does not rely on scrollbar for image panning.\n");
    fprintf(stderr, "It is a powerful tool to analyse huge images.\n");
    fprintf(stderr, "The Window is a view of the image in which you can zoom, pan, rotate...\n");
    fprintf(stderr, "%s reads natively 8 and 16 bits binary PPM and TIFF and JPEG images. It uses ImageMagick to convert other formats.\n", progn);
    fprintf(stderr, "Image drawing is performed in several threads for a better image analysis experience.\n");
    fprintf(stderr, "Next image is preloaded during current image analysis.\n");
    fprintf(stderr, "Shortcuts are:\n");
    fprintf(stderr, "   - Key based:\n");
    fprintf(stderr, "      o q/Q Quit\n");
    fprintf(stderr, "      o n/p Next/previous image in the list\n");
    fprintf(stderr, "      o D Delete current image. \n");
    fprintf(stderr, "      o d The current image is renamed to file.jpg.del. You'llcan delete it manually afterward.\n");
    fprintf(stderr, "      o Shift+n/p Jump 10 images forward/backward.\n");
    fprintf(stderr, "      o ' '/. Center view on pointer\n");
    fprintf(stderr, "      o z/Z/+/i Zoom/Unzoom\n");
    fprintf(stderr, "      o c/C Contrast +/-\n");
    fprintf(stderr, "      o g/G Gamma +/-\n");
    fprintf(stderr, "      o l/L Luminosity +/-\n");
    fprintf(stderr, "      o v   Reset Luminosity/Contrast\n");
    fprintf(stderr, "      o i   Invert colors\n");
    fprintf(stderr, "      o Fn  Memorize current pixel coordinate as nth point.\n");
    fprintf(stderr, "      o s   Show/hide points.\n");
    fprintf(stderr, "      o a   Show/hide about message.\n");
    fprintf(stderr, "      o f   Toggle Full Screen.\n");
    fprintf(stderr, "      o h   Toggle display histogram\n");
    fprintf(stderr, "      o b   Toggle bilinear interpolation\n");
    fprintf(stderr, "      o o   Toggle display overview\n");
    fprintf(stderr, "      o m   Toggle display grid\n");
    fprintf(stderr, "      o r/=/0 Reset view\n");
    fprintf(stderr, "      o 1-9 Set zoom level to 1/1..9\n");
    fprintf(stderr, "      o [Alt+]1-9 Set zoom level to 1..9\n");
    fprintf(stderr, "      o Left/Right/Up/Down pan\n");
    fprintf(stderr, "      o Shift+Left/Right/Up/Down fine pan\n");
    fprintf(stderr, "      o / or * rotate around center of window by 90° increments rounding angle to n x 90°.\n");
    fprintf(stderr, "      o Alt+Left/Right rotate around center of window\n");
    fprintf(stderr, "      o Shift+Alt+Left/Right fine rotate around center of window\n");
    fprintf(stderr, "   - Mouse based:\n");
    fprintf(stderr, "      o Left button+Drag Pan\n");
    fprintf(stderr, "      o Shift+Left button+Drag Upper-Left -> Lower Right : Zoom on zone, Lower-Right -> Upper Left Unzoom from zone.\n");
    fprintf(stderr, "      o Wheel Zoom/Unzoom keeping pointer position\n");
    fprintf(stderr, "      o Shift+Wheel Fine Zoom/Unzoom keeping pointer position\n");
    fprintf(stderr, "      o Alt+Wheel Rotate around pointer\n");
    fprintf(stderr, "      o Shift+Alt+Wheel Fine rotate around pointer\n");
    fprintf(stderr, "      o Button middle Previous image\n");
    fprintf(stderr, "      o Button right Next image\n");
    fprintf(stderr, "Points input:\n");
    fprintf(stderr, "   You can set up to 10 points using keys F1 to F10. If points are displayed (which is the default) you'll see them on top of the image.\n");
    fprintf(stderr, "   At the end of the image viewing, the points are written to stdout (before switching to another image or quitting).\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s -browse /images/image1.jpg: opens images1.jpg as well as every files in the /images directory.\n", progn);
    fprintf(stderr, "  %s -shuffle /images/*: opens every files in /images in random order.\n", progn);
    fprintf(stderr, "Capabilities: ");
    fprintf(stderr, "PPM ");
#ifdef HAVE_LIBJPEG
    fprintf(stderr, "JPEG ");
#endif
#ifdef HAVE_LIBTIFF
    fprintf(stderr, "TIFF ");
#endif
#ifdef HAVE_LIBEXIF
    fprintf(stderr, "EXIF ");
#endif
    fprintf(stderr, "\n");
}

void write_points(const char *file)
{
    for (int p = 0; p < 10; p++) {
        float xp = pts[2 * p];
        float yp = pts[2 * p + 1];
        if (xp >= 0) {
            printf("%s %d %f %f\n", file, p, xp, yp);
        }
    }
}

// Return a pixel r,g and b value according to geometric and radiometric transformation.
// r,g and b are between 0 and 255 even if the input image is 16 bits.
// contrast, luminosity and gamma take advantage of the 16bits wide input to best convert to 8 bits.
inline void pixel_gm_nb2(int ii, int ji, int &r, int &g, int &b, Image *img)
{
    int idx = 3 * (img->w * ii + ji);
    int val = 0;

    val = *(((unsigned short *)img->buf) + idx);

    val = (int)(cr * powv[(val * 255) >> img->nbits]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    b = val;

    val = *(((unsigned short *)img->buf) + idx + 1);

    val = (int)(cr * powv[(val * 255) >> img->nbits]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    g = val;

    val = *(((unsigned short *)img->buf) + idx + 2);

    val = (int)(cr * powv[(val * 255) >> img->nbits]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    r = val;
}

inline void pixel_gm_nb1(int ii, int ji, int &r, int &g, int &b, Image *img)
{
    int idx = 3 * (img->w * ii + ji);
    int val = 0;

    val = img->buf[idx];

    val = (int)(cr * powv[val]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    b = val;

    val = img->buf[idx + 1];

    val = (int)(cr * powv[val]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    g = val;

    val = img->buf[idx + 2];

    val = (int)(cr * powv[val]) >> 8;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    r = val;
}

inline void pixel_gm1_nb2(int ii, int ji, int &r, int &g, int &b, Image *img)
{
    int idx = 3 * (img->w * ii + ji);
    int val = 0;

    val = *(((unsigned short *)img->buf) + idx);

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    b = val;

    val = *(((unsigned short *)img->buf) + idx + 1);

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    g = val;

    val = *(((unsigned short *)img->buf) + idx + 2);

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    r = val;
}

inline void pixel_gm1_nb1(int ii, int ji, int &r, int &g, int &b, Image *img)
{
    int idx = 3 * (img->w * ii + ji);
    int val = 0;

    val = img->buf[idx];

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    b = val;

    val = img->buf[idx + 1];

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    g = val;

    val = img->buf[idx + 2];

    val *= cr;
    val >>= img->nbits;

    val += lu;

    if (val > 255)
        val = 255;
    if (val < 0)
        val = 0;

    if (revert)
        val = 255 - val;

    r = val;
}

inline void pixel(int ii, int ji, int &r, int &g, int &b, Image *img)
{
    int ji2 = ji;

    r = g = b = 255;

    if (h360 && (ji < 0 || ji >= img->w)) {
        while (ji2 < 0) ji2 += img->w;
        while (ji2 >= img->w) ji2 -= img->w;
    }
    if (ji2 >= 0 && ji2 < img->w && ii >= 0
        && ii < img->h) {
        if (gm == 1) {
            if (img->nb == 1)
                pixel_gm1_nb1(ii, ji2, r, g, b, img);
            else
                pixel_gm1_nb2(ii, ji2, r, g, b, img);
        } else {
            if (img->nb == 1)
                pixel_gm_nb1(ii, ji2, r, g, b, img);
            else
                pixel_gm_nb2(ii, ji2, r, g, b, img);
        }
    } else {
        // Outside of the image, the world is black...
        r = g = b = 0;
    }

}

// Fill a part of the drawing area.
// Part is delimited by bounds int[2] with starting row and ending row.
void *async_fill_part(void *bounds)
{
    Image *img = fillState.imgCurrent;
    double zca = fillState.z * cos(fillState.a);
    double zsa = fillState.z * sin(fillState.a);
    int *p = (int *)bounds;
    for (int i = p[0]; i < p[1]; i++) {
        int idx = 4 * w * i;
        double mix = (fillState.z * xoffset) + fillState.dx - zsa * i;
        double miy = zca * i + fillState.dy + (fillState.z * yoffset);
        double x = mix;
        double y = miy;
        for (int j = 0; j < w; j++) {
            int r = 0, g = 0, b = 0;
            x += zca;
            y += zsa;
            int ji = (int)x;
            int ii = (int)y;

            // If bilinear interpolation is not requested or useful
            if (!bilin || ((z >= 1) && (fillState.a == 0))) {
                pixel(ii, ji, r, g, b, img);
            } else    // Use bilinear interpolation
            {
                if (x < 0)
                    ji--;
                if (y < 0)
                    ii--;
                int r1 = 0, g1 = 0, b1 = 0;
                int r2 = 0, g2 = 0, b2 = 0;
                int r3 = 0, g3 = 0, b3 = 0;
                int r4 = 0, g4 = 0, b4 = 0;
                pixel(ii, ji, r1, g1, b1, img);
                pixel(ii, ji + 1, r2, g2, b2, img);
                pixel(ii + 1, ji, r3, g3, b3, img);
                pixel(ii + 1, ji + 1, r4, g4, b4, img);

                float u = x - ji;
                float v = y - ii;
                float u1 = 1 - u;
                float v1 = 1 - v;
                float uv = u * v;
                float u1v1 = u1 * v1;
                float uv1 = u * v1;
                float u1v = u1 * v;
                r = (int)(r1 * u1v1 + r2 * uv1 + r3 * u1v +
                      r4 * uv);
                g = (int)(g1 * u1v1 + g2 * uv1 + g3 * u1v +
                      g4 * uv);
                b = (int)(b1 * u1v1 + b2 * uv1 + b3 * u1v +
                      b4 * uv);
            }

            data[idx] = (unsigned char)r;
            data[idx + 1] = (unsigned char)g;
            data[idx + 2] = (unsigned char)b;

            idx += 4;
        }
    }
    return 0;
}

// Fill data with image according to zoom, angle and translation
void fill()
{
    bool do_fill = true;
    pthread_mutex_lock(&mutexData);
    if (imgCurrent != 0) {
        // Pack position into buffer
        fillState.imgCurrent = imgCurrent;
        fillState.dx = dx;
        fillState.dy = dy;
        fillState.z = z;
        fillState.a = a;
    } else do_fill = false;
    pthread_mutex_unlock(&mutexData);
    if (!do_fill)
        return;

    if (gm != powe) {
        powe = gm;
        for (int i = 0; i < 256; i++)
            powv[i] = (int)(255 * powf((float)i / (float)255, gm));
    }


    // If we have several cores available, split filling into several threads.
    if (ncores > 1) {
        for (int i = 0; i < ncores; i++)
            fillBounds[i] = i * (h / ncores);
        fillBounds[ncores] = h;

        for (int i = 0; i < ncores; i++)
            pthread_create(thFill + i, NULL, async_fill_part,
                       fillBounds + i);

        void *r;
        for (int i = 0; i < ncores; i++)
            pthread_join(*(thFill + i), &r);
    } else            // Or directly fill the buffer in the main thread.
    {
        int bounds[2];
        bounds[0] = 0;
        bounds[1] = h;
        async_fill_part(bounds);
    }
}

// Asynchronous image filling
void *async_fill(void *)
{
    float za = 0, aa = 0, dxa = 0, dya = 0;
    float gma = 0;
    int la = 0;
    int ca = 0;
    bool ra = false;
    bool bilina = false;
    //  bool dqa=false;
    //  bool dha=false;
    //  bool dza=false;
    int zx1a = 0, zx2a = 0, zy1a = 0, zy2a = 0;
    int delay = 20000;
    bool posChanged = false;

    #ifdef WATCHDOG
    if (pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, &watchdog_counter)) {
        perror("ERROR setting cancellation type for async_fill thread");
    }
    watchdog_counter = 1;
    #endif

    while (run) {
        #ifdef WATCHDOG
            watchdog_counter++;
            if (watchdog_counter >= 60000)
                watchdog_counter = 1;
        #endif
        // If something changed we need to redraw
        pthread_mutex_lock(&mutexData);
        if (za != z || dx != dxa || dy != dya || aa != a) {
            posChanged = true;
            za = z; dxa = dx; dya = dy; aa = a;
        } else { posChanged = false; }
        pthread_mutex_unlock(&mutexData);
        if (posChanged ||
            la != lu || ca != cr || ra != revert || gma != gm
            || bilina != bilin || zx1a != zx1 || zx2a != zx2
            || zy1a != zy1 || zy2a != zy2 || refresh) {
            delay = 5000;
            refresh = false;
            la = lu;
            ca = cr;
            bilina = bilin;
            gma = gm;
            ra = revert;
            zx1a = zx1;
            zx2a = zx2;
            zy1a = zy1;
            zy2a = zy2;
            pthread_mutex_lock(&mutexWin);
            if (data != NULL && image != NULL && image->data != NULL) {
                fill();

                //XClearWindow(display, window);
                XPutImage(display, drawable, gc, image, 0, 0, 0, 0, w, h);
                //XCopyArea(display, pixmap, window, gc, 0, 0, w, h, 0, 0);

                if (do_double_buff && can_double_buff) {
                    bool swap_success;
                    XdbeSwapInfo swapInfo;
                    swapInfo.swap_window = window;
                    swapInfo.swap_action = XdbeBackground;
                    //pthread_mutex_lock(&mutexWin);
                    swap_success = XdbeSwapBuffers(display, &swapInfo, 1);
                    //pthread_mutex_unlock(&mutexWin);
                    if (!swap_success) {
                        fprintf(stderr, "Problem swapping buffers\n");
                        return 0;
                    }
                }
                //XPutImage(display, window, gc, image, xoffset - dx, yoffset - dy, 0, 0, w, h);

                XFlush(display);
            }
            pthread_mutex_unlock(&mutexWin);
        } else        // Otherwise, just wait ...
        {
            // ... and gently increase wait state
            delay *= 102;
            delay /= 100;
            if (delay > 200000)
                delay = 200000;
            usleep(delay);
        }
    }
    return 0;
}

// Set parameters so that image fit into window
void full_extend()
{
    if (!imgCurrent)
        return;
    a = 0;
    lu = 0;
    gm = 1;
    revert = false;
    z = (float)imgCurrent->w / (float)w;
    float z2 = (float)imgCurrent->h / (float)h;
    // Comment this out because we always want the image zoomed full height
    //if (z2 > z)
        z = z2;
    maxz = z;
    minz = maxz / zoom_max;

    dx = imgCurrent->w / 2 - (z * cos(a) * (w / 2) - z * sin(a) * (h / 2));
    dy = imgCurrent->h / 2 - (z * sin(a) * (w / 2) + z * cos(a) * (h / 2));

    if (verbose)
        fprintf(stderr, "Full extend %f %f %f\n", z, dx, dy);
}

Image *get_image_from_cache(const char *file)
{
    MutexProtect mp(&mutexCache);
    for (int i = 0; i < CACHE_NBIMAGES; i++) {
        if (imgCache[i] && 0 == strcmp(file, imgCache[i]->name)) {
            return imgCache[i];
        }
    }
    return 0;
}

// Load an image, tries to open as ppm, then jpeg, then tiff and if fails, use imagemagick to convert to ppm
Image *load_image(const char *file)
{
    Image *img = get_image_from_cache(file);
    if (img) {
        // We are already loading the file from another thread
        // Wait for loading is done
        while (img && img->state == IN_PROGRESS) {
            usleep(50000);
            img = get_image_from_cache(file);
        }
        if (img->state == READY)
            return img;
        if (img)    // Error occured
            return 0;
        // Image was removed from cache, reload it
    }

    img = new Image(0, 0, 0, 0, 0, file, 0);

    // Add image to cache
    if (img) {
        MutexProtect mp(&mutexCache);
        if (imgCache[idxCache]) {
            delete imgCache[idxCache];
        }
        imgCache[idxCache] = img;
        idxCache++;
        idxCache %= CACHE_NBIMAGES;
    } else
        return 0;

    int wi, hi, nbBytes, valMax;
    // Try PPM -> JPEG -> TIFF -> convert
    struct stat statBuf;
    unsigned char *buf = 0;
    if (0 == stat(file, &statBuf))    // File exist
    {
        // Try ppm
        buf = read_ppm(file, wi, hi, nbBytes, valMax);
        if (buf == 0)    // No success, try jpeg
        {
            buf = read_jpeg(file, wi, hi);
            if (verbose && buf)
                fprintf(stderr,
                    "Success reading jpeg file %s\n", file);
            nbBytes = 1;
            valMax = 255;
        }
        if (buf == 0)    // No success, try tiff
        {
            buf = read_tiff(file, wi, hi, nbBytes, valMax);
            if (verbose && buf)
                fprintf(stderr,
                    "Success reading tiff file %s\n", file);
        }
        if (buf == 0)    // No success, convert with ImageMagick
        {
            if (verbose)
                fprintf(stderr,
                    "Converting image with ImageMagick\n");
            char cmd[2048];
            char tmp[32];
            char *tmpdir = getenv("TMP");
            sprintf(tmp, "%s/xiv_XXXXXX",
                tmpdir == NULL ? "/tmp" : tmpdir);
            int ret = mkstemp(tmp);
            if (ret == -1) {
                fprintf(stderr, "Error creating tmp file %s\n",
                    tmpdir == NULL ? "/tmp" : tmpdir);
            }
            close(ret);
            unlink(tmp);
            strcat(tmp, ".ppm");
            sprintf(cmd, "convert \"%s\" -quiet %s", file, tmp);
            if (system(cmd) == -1) {
                fprintf(stderr,
                    "Error calling ImageMagick convert\n");
            }
            buf = read_ppm(tmp, wi, hi, nbBytes, valMax);
            if (!buf) {
                fprintf(stderr,
                    "Unable to read converted image\n");
            } else if (verbose)
                fprintf(stderr,
                    "Success reading converted file %s\n",
                    file);
            unlink(tmp);
        }
    }

    if (buf) {
        int nbits = (int)round(log(valMax) / log(2));
        img->nb = nbBytes;
        img->max = valMax;
        img->nbits = nbits;
        // Perform autorotate if requested
        int ai = autorot ? orientation(file) : 0;
        if (verbose)
            fprintf(stderr, "Orientation %d\n", ai);
        if (ai == 0) {
            img->w = wi;
            img->h = hi;
            img->buf = buf;
            img->state = READY;
        } else if (ai == 1)    // 90
        {
            unsigned char *buf2 =
                (unsigned char *)malloc(wi * hi * 3);
            if (!buf2) {
                free(buf);
                return 0;
            }
            for (int i = 0; i < hi; i++) {
                int jn = i;
                for (int j = 0; j < wi; j++) {
                    int in = wi - j - 1;
                    buf2[3 * (in * hi + jn) + 0] =
                        buf[3 * (i * wi + j) + 0];
                    buf2[3 * (in * hi + jn) + 1] =
                        buf[3 * (i * wi + j) + 1];
                    buf2[3 * (in * hi + jn) + 2] =
                        buf[3 * (i * wi + j) + 2];
                }
            }
            ai = 0;
            img->w = hi;
            img->h = wi;
            img->buf = buf2;
            img->state = READY;
            free(buf);
        } else if (ai == 2)    //180
        {
            unsigned char *buf2 =
                (unsigned char *)malloc(wi * hi * 3);
            if (!buf2) {
                free(buf);
                return 0;
            }
            for (int i = 0; i < hi; i++) {
                int in = hi - i - 1;
                for (int j = 0; j < wi; j++) {
                    int jn = wi - j - 1;
                    buf2[3 * (in * hi + jn) + 0] =
                        buf[3 * (i * wi + j) + 0];
                    buf2[3 * (in * hi + jn) + 1] =
                        buf[3 * (i * wi + j) + 1];
                    buf2[3 * (in * hi + jn) + 2] =
                        buf[3 * (i * wi + j) + 2];
                }
            }
            ai = 0;
            img->w = wi;
            img->h = hi;
            img->buf = buf2;
            img->state = READY;
            free(buf);
        } else if (ai == 3)    //270
        {
            unsigned char *buf2 =
                (unsigned char *)malloc(wi * hi * 3);
            if (!buf2) {
                free(buf);
                return 0;
            }
            for (int i = 0; i < hi; i++) {
                int jn = i;
                for (int j = 0; j < wi; j++) {
                    int in = j;
                    buf2[3 * (in * hi + jn) + 0] =
                        buf[3 * (i * wi + j) + 0];
                    buf2[3 * (in * hi + jn) + 1] =
                        buf[3 * (i * wi + j) + 1];
                    buf2[3 * (in * hi + jn) + 2] =
                        buf[3 * (i * wi + j) + 2];
                }
            }
            ai = 0;
            img->w = hi;
            img->h = wi;
            img->buf = buf2;
            img->state = READY;
            free(buf);
        }
    } else {
        img->state = ERROR;
        return 0;
    }

    return img;
}

// Set WM_CLASS
void set_class(void) {
    XClassHint *xch;

    if ((xch = XAllocClassHint())) {
        xch->res_class = win_class;
        xch->res_name = win_name;
        XSetClassHint(display, window, xch);
        delete xch;
    }
    else {
        fprintf(stderr, "Couldn't allocate a class hint structure. Probably out of memory.\n");
        exit(1);
    }
}

// Set the title of the window
void set_title(const char *file)
{
    // Tell the WM what is the name of the window.
    char title[1024];

    if (win_name != NULL) {
        XStoreName(display, window, win_name);
        return;
    }
    if (imgCurrent)
        sprintf(title, "%s - %d x %d - %db - %d / %d", imgCurrent->name,
            imgCurrent->w, imgCurrent->h,
            (int)round(log(imgCurrent->max) / log(2)), idxfile + 1,
            nbfiles);
    else
        sprintf(title, "%s - %d x %d - %db - %d / %d", file, 0, 0, 0,
            idxfile + 1, nbfiles);
    XStoreName(display, window, title);
}

// Display the image
void display_image(const char *file)
{
    if (verbose)
        fprintf(stderr, "display_image %s\n", file);
    for (int i = 0; i < 20; i++)
        pts[i] = -1;
    // Set the wait cursor
    if (!fakewin) {
        pthread_mutex_lock(&mutexWin);
        XDefineCursor(display, window, watch);
        pthread_mutex_unlock(&mutexWin);
        XFlush(display);
    }

    histMax = 0;
    imgCurrent = load_image(file);
    if (imgCurrent == 0)
        imgCurrent = load_image(PREFIX "/share/xiv/xiv.ppm");
    if (imgCurrent == 0)
        fprintf(stderr,
            "Can't open default file %s, there's something wrong with the installation\n",
            PREFIX "/share/xiv/xiv.ppm");
    // Init to image fitting in window
    full_extend();

    cr = 255;
    refresh = true;
    // Restore normal cursor
    if (!fakewin) {
        pthread_mutex_lock(&mutexWin);
        XDefineCursor(display, window, normal);
        set_title(file);
        pthread_mutex_unlock(&mutexWin);
    }
}

void *async_load(void *)
{
    while (nbfiles > 1) {
        // Ensure the next image in the list is preloaded in the cache
        for (int s = 0; s <= 1; s++) {
            bool found = false;
            int next = 0;
            {
                MutexProtect mp(&mutexCache);
                // Preload next file
                if (nbfiles > 0) {
                    next = (idxfile + s) % nbfiles;
                    // Search if it's already in the cache
                    for (int i = 0; i < CACHE_NBIMAGES; i++) {
                        if (imgCache[i]
                            && 0 ==
                            strcmp(imgCache[i]->name,
                               files[next])) {
                            found = true;
                            break;
                        }
                    }
                }
            }

            if (!found) {
                if (verbose)
                    fprintf(stderr,
                        "Preload next image %s\n",
                        files[next]);
                load_image(files[next]);
                if (verbose)
                    fprintf(stderr, "Preload done\n");
            }
            usleep(200000);
        }
    }
    return 0;
}

void rotate(float da)
{
    float xp = z * cos(a) * w / 2 - z * sin(a) * h / 2 + dx;
    float yp = z * sin(a) * w / 2 + z * cos(a) * h / 2 + dy;
    a = da;
    dx = xp - (z * cos(a) * w / 2 - z * sin(a) * h / 2);
    dy = yp - (z * sin(a) * w / 2 + z * cos(a) * h / 2);
}

typedef struct {
    int flag, img_idx;
    float dx, dy, z;
} sync_struct;

void *udp_handler(void *) {
    int recv_socket = 0, so_reuseaddr = 1;
    struct sockaddr_in addr;
    sync_struct data;
    struct hostent *server;
    struct ip_mreq mreq;
    bool new_image = false;

    recv_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (recv_socket == 0) {
        perror("Couldn't open receiving socket");
        exit(0);
    }
    memset(&addr, 0, sizeof(sockaddr_in));
    addr.sin_family = AF_INET;

    if (listenaddr != NULL) {
        if (! multicast) {
            server = gethostbyname(listenaddr);
            if (server == NULL) {
                perror("Couldn't figure out host to bind to");
                exit(0);
            }
            memcpy(&addr.sin_addr.s_addr, server->h_addr, server->h_length);
        }
        else {
            // In multicast mode, we need to listen on INADDR_ANY. We'll use -listenaddr later on
            addr.sin_addr.s_addr = htonl(INADDR_ANY);
        }
    }
    else {
        addr.sin_addr.s_addr = INADDR_ANY;
    }
    addr.sin_port = htons(listenport);
    if (bind(recv_socket, (sockaddr *) &addr, sizeof(addr)) < 0) {
        perror("Couldn't bind socket");
        exit(0);
    }

    if (setsockopt(recv_socket, SOL_SOCKET, SO_REUSEADDR, &so_reuseaddr, sizeof so_reuseaddr) == -1) {
        perror("Couldn't turn on SO_REUSEADDR");
    }

    if (multicast) {
        mreq.imr_multiaddr.s_addr = inet_addr(listenaddr);
        mreq.imr_interface.s_addr = htonl(INADDR_ANY);
        if (setsockopt(recv_socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) < 0) {
            perror("Problem joining multicast group");
            exit(1);
        }
    }

    while (1) {
        if (read(recv_socket, &data, sizeof(sync_struct)) >= (ssize_t) sizeof(sync_struct) &&
            data.flag == 1234) {
            // Do something here with what we've received
            if (verbose) {
                fprintf(stderr, "%d, %d, %f, %f, %f\n", data.img_idx, data.flag, data.dx, data.dy, data.z);
            }

            pthread_mutex_lock(&mutexData);
            new_image = (idxfile != data.img_idx);
            dx = data.dx;
            dy = data.dy;
            z = data.z;
            idxfile = data.img_idx;
            pthread_mutex_unlock(&mutexData);
            if (new_image) {
                if (data.img_idx >= nbfiles || data.img_idx < 0) {
                    fprintf(stderr, "ERROR: Tried to cycle past the end of the image list (idxfile = %d, nbfiles = %d). Is the list of images on your command line identical to the master, and do all the images actually exist?\n", data.img_idx, nbfiles);
                    exit(1);
                }
                display_image(files[data.img_idx]);
            }
        }
    }
    return 0;
}

int *send_sockets;
int num_sockets = 0;

void *send_coords(void *) {
    sync_struct a;
    int i;
    bool update_needed;

    if (slavemode || num_slaves == 0) {
        return 0;
    }

    a.flag = 1234;

    pthread_mutex_lock(&mutexData);
    a.dx = dx;
    a.dy = dy;
    a.z = z;
    a.img_idx = idxfile;
    pthread_mutex_unlock(&mutexData);

    while(run) {
        pthread_mutex_lock(&mutexData);
        if (dx != a.dx || dy != a.dy || z != a.z || idxfile != a.img_idx) {
            a.dx = dx;
            a.dy = dy;
            a.z = z;
            a.img_idx = idxfile;
            update_needed = true;
        } else
            update_needed = false;
        pthread_mutex_unlock(&mutexData);

        if (update_needed) {
            if (num_sockets == 0) {
                struct sockaddr_in addr;
                struct hostent *server;
                int dummy = 1;

                send_sockets = (int *) malloc(sizeof(int) * num_slaves);
                if (! send_sockets) {
                    perror("Couldn't allocate memory for sockets");
                    exit(1);
                }
                for (i = 0; i < num_slaves; i++) {
                    if (verbose) {
                        fprintf(stderr, "Opening socket to %s:%d\n", slavehosts[i].host, slavehosts[i].port);
                    }
                    send_sockets[i] = socket(AF_INET, SOCK_DGRAM, 0);
                    if (send_sockets[i] == 0) {
                        perror("Couldn't open socket");
                        exit(0);
                    }
                    num_sockets++;
                    if (slavehosts[i].broadcast)
                        setsockopt(send_sockets[i], SOL_SOCKET, SO_BROADCAST, &dummy, sizeof(int));
                    server = gethostbyname(slavehosts[i].host);
                        if (server == NULL) {
                        perror("Couldn't figure out host");
                        exit(0);
                    }

                    memset(&addr, 0, sizeof(sockaddr_in));
                    addr.sin_family = AF_INET;
                    memcpy(&addr.sin_addr.s_addr, server->h_addr, server->h_length);
                    addr.sin_port = htons(slavehosts[i].port);
                    if (connect(send_sockets[i], (sockaddr *) &addr, sizeof(addr)) < 0) {
                        perror("Error connecting UDP client");
                    }
                }
            }

            //fprintf(stderr, "sending coords: [[%f]] [[%f]] [[%f]] [[%d]]\n",a.dx,a.dy,a.z,a.img_idx);

            for (i = 0; i < num_slaves; i++) {
                if (write(send_sockets[i], &a, sizeof(a)) <= 0 && verbose) {
                    fprintf(stderr, "Write returned 0 or -1; writing to %s:%d may have failed\n", slavehosts[i].host, slavehosts[i].port);
                }
            }
        } else
            usleep(10000); // limit the update rate
    } return 0;
}

void translate(float stepX, float stepY)
{
    float xp = dx - (-z * cos(a) * stepX - z * sin(a) * stepY);
    float yp = dy - (-z * sin(a) * stepX + z * cos(a) * stepY);

    // Constrain dy so that no black bars show up above or below the image
    if (imgCurrent) {
        if (yp < 0) yp = 0;
        else if (yp > imgCurrent->h - h * z) yp = imgCurrent->h - h*z;

        if (h360) {
            // Wrap-around
            if (xp > imgCurrent->w)
                xp -= imgCurrent->w;
            else if (xp < -imgCurrent->w)
                xp += imgCurrent->w;
        } else {
            if (xp > imgCurrent->w - 10)
                xp = imgCurrent->w - 10;
            if (xp / z < -w + 10)
                xp = (10 -w) * z;
        }
    }
    dx = xp;
    dy = yp;
}

void zoom(float zf)
{
    float xp = z * cos(a) * w / 2 - z * sin(a) * h / 2 + dx;
    float yp = z * sin(a) * h / 2 + z * cos(a) * h / 2 + dy;

    // Constrain zoom amount
    if (zf < minz) zf = minz;
    if (zf > maxz) zf = maxz;

    xp = xp - (zf * cos(a) * w / 2 - zf * sin(a) * h / 2);
    yp = yp - (zf * sin(a) * w / 2 + zf * cos(a) * h / 2);

    // Constrain dy so that no black bars show up above or below the image
    if (imgCurrent) {
        if (yp < 0) yp = 0;
        else if (yp > imgCurrent->h - h * zf) yp = imgCurrent->h - h*zf;
    
        if (h360) {
            // Wrap-around
            if (xp > imgCurrent->w)
                xp -= imgCurrent->w;
            else if (xp < -imgCurrent->w)
                xp += imgCurrent->w;
        } else {
            if (xp > imgCurrent->w - 10)
                xp = imgCurrent->w - 10;
            if (xp / z < -w + 10)
                xp = (10 -w) * z;
        }
    }
    z = zf;
    dx = xp;
    dy = yp;
}

// Display next image
void next_image(int step)
{
    pthread_mutex_lock(&mutexData);
    idxfile += step;

    if (idxfile >= nbfiles)
        idxfile = 0;
    if (idxfile < 0)
        idxfile = nbfiles - 1;
    display_image(files[idxfile]);
    pthread_mutex_unlock(&mutexData);
}

#ifdef WATCHDOG
// Watchdog thread
void *watchdog_handler(void *)
{
    int last_counter = 0;

    // Wait for fill thread to start up
    while (watchdog_counter == 0) {
        usleep(100);
    }

    while (1) {
        usleep(300000);
        if (last_counter == watchdog_counter) { 
            fprintf(stderr, "Watchdog says we need to kill the fill process!\n");
            // Randomly-selected nonzero number
            exit(-4);
        }
        else {
            last_counter = watchdog_counter;
        }
    }

    return NULL;
}
#endif

// Thread for spacenav
void *spacenav_handler(void *)
{
    spnav_event spev;

    if (!init_spacenav(spdev == NULL ? "/dev/input/spacenavigator" : spdev)) {
        pthread_exit(0);
    }

    while (1) {
        if (get_spacenav_event(&spev)) {
            {
                // Mutex protection here means translation and zoom amounts
                // don't change while the async_fill thread is drawing,
                // preventing ugliness.
                if (spev.type == SPNAV_MOTION) {
                    pthread_mutex_lock(&mutexData);
                    zoom(z - z * spev.z / 350.0 / spsens / 2);
                    translate(swapaxes * -1 * spev.x / spsens, swapaxes * spev.y / spsens);
                    pthread_mutex_unlock(&mutexData);
                } else {
                    // value == 0  means the button is coming up. Without this, it
                    // would cycle images both on press *and* on release, which
                    // gets irritating.
                    if (spev.type == SPNAV_BUTTON && spev.value == 0) {
                        next_image(1);
                    }
                }
            }
        } else {
            usleep(100);
        }
    }
    return 0;
}

// Thread for fifo listening
void *async_fifo(void *)
{
    while (fifo != NULL) {
        int fd = open(fifo, O_RDONLY);
        if (fd == -1) {
            fprintf(stderr, "Can't open fifo %s for reading\n",
                fifo);
            fifo = NULL;
        } else {
            char msg[2048];
            int ret = read(fd, msg, 2048);
            if (ret > 0) {
                msg[ret - 1] = 0;
                printf("msg: [%s]\n", msg);
                if (strstr(msg, "l ") == msg) {
                    pthread_mutex_lock(&mutexData);
                    display_image(msg + 2);
                    pthread_mutex_unlock(&mutexData);
                } else if (strstr(msg, "z") == msg) {
                    float zc = atof(msg + 2);
                    pthread_mutex_lock(&mutexData);
                    if (zc <= 0) {
                        full_extend();
                    } else {
                        zoom(zc);
                    }
                    pthread_mutex_unlock(&mutexData);
                } else if (strstr(msg, "c") == msg) {
                    int xp, yp;
                    sscanf(msg, "c %d %d\n", &xp, &yp);
                    pthread_mutex_lock(&mutexData);
                    dx = xp - (z * cos(a) * (w / 2) -
                           z * sin(a) * (h / 2));
                    dy = yp - (z * sin(a) * (w / 2) +
                           z * cos(a) * (h / 2));
                    pthread_mutex_unlock(&mutexData);
                } else if (strstr(msg, "m") == msg) {
                    int dxp, dyp;
                    sscanf(msg, "m %d %d\n", &dxp, &dyp);
                    pthread_mutex_lock(&mutexData);
                    translate(dxp, dyp);
                    pthread_mutex_unlock(&mutexData);
                } else if (strstr(msg, "q") == msg) {
                    close(fd);
                    unlink(fifo);
                    exit(1);
                    run = false;
                }
                close(fd);
            }
        }
    }
    return 0;
}

void quit()
{
    void *r;
    nbfiles = 0;
    if (fifo != NULL) {
        fifo = NULL;
        pthread_cancel(thFifo);
        pthread_join(thFifo, &r);
    }
    if (spacenav) {
        pthread_cancel(thSpacenav);
        pthread_join(thSpacenav, &r);
    }
    if (slavemode) {
        pthread_cancel(thUDPSlave);
        pthread_join(thUDPSlave, &r);
    } else if (num_slaves > 0) {
        pthread_cancel(thUDPMaster);
        pthread_join(thUDPMaster, &r);
    }
    #ifdef WATCHDOG
    pthread_cancel(thWatchdog);
    pthread_join(thWatchdog, &r);
    #endif
    pthread_join(thPreload, &r);
    pthread_join(th, &r);
}

// Destroy current window
void destroy_window()
{
    XDestroyWindow(display, window);
}

// Create the window
void create_window(bool fs)
{
    // Create the 
    Window root = DefaultRootWindow(display);
    int ww = wref;
    int wh = href;
    if (fs) {
        ww = XDisplayWidth(display, screen);
        wh = XDisplayHeight(display, screen);
    }

    if (do_double_buff && can_double_buff) {
        unsigned long xAttrMask = CWBackPixel;
        XSetWindowAttributes xAttr;
        xAttr.background_pixel = WhitePixel(display, screen);
        window = XCreateWindow(display, root, ox, oy, ww, wh, 0, CopyFromParent, CopyFromParent, visual, xAttrMask, &xAttr);
        if (!window) {
            fprintf(stderr, "Problem creating double-buffered window\n");
            exit(1);
        }

        d_backBuf = XdbeAllocateBackBufferName(display, window, XdbeBackground);
        gc = XCreateGC(display, d_backBuf, 0, NULL);
        XSetForeground(display, gc, BlackPixel(display, screen));
        XSetBackground(display, gc, 0xFFA000);
        drawable = d_backBuf;
    }
    else {
        window = XCreateSimpleWindow(display, root,
                        ox, oy, ww, wh, 0,
                        BlackPixel(display, screen),
                        WhitePixel(display, screen));
        drawable = window;
    }

    XSelectInput(display, window,
             ExposureMask | ButtonPressMask | ButtonReleaseMask |
             KeyPressMask | PointerMotionMask | StructureNotifyMask);

    // Tell the window manager to call us when user close the window
    XSetWMProtocols(display, window, &wmDeleteMessage, 1);

    // Tell the window manager to go fullscreen (if compatible)...
    if (fs) {
        Atom first, second;

        first = XInternAtom(display, "_NET_WM_STATE", False);
        second =
            XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
        XChangeProperty(display, window, first, XA_ATOM, 32,
                PropModeReplace, (unsigned char *)&second, 1);
    }
    set_title("");
    if (win_class != NULL)
        set_class();

    // Display the window
    XMapWindow(display, window);
}

int main(int argc, char **argv)
{
    char *dummy_pchar;

    if (argc > 1
        && (0 == strcmp(argv[1], "-h") || 0 == strcmp(argv[1], "--help"))) {
        usage(argv[0]);
        exit(1);
    }

    XEvent event;

    bool browse = false;

    // Allocate file list
    files = (char **)malloc(sizeof(char *) * MAX_NBFILES);
    if (files == NULL) {
        fprintf(stderr, "Not enough memory\n");
        exit(1);
    }

    // Analyse arguments
    for (int i = 1; i < argc; i++) {
        if (0 == strcmp(argv[i], "-geometry")) {
            if ((i + 1) < argc) {
                sscanf(argv[++i], "%dx%d+%d+%d", &w, &h, &ox,
                       &oy);
                wref = w;
                href = h;
            } else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-fakewin")) {
            if (wref > 0 && href > 0) {
                fakewin = true;
            } else {
                fprintf(stderr, "Option -fakewin requires a preceding -geometry!\n");
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-no-autorot")) {
            autorot = false;
        } else if (0 == strcmp(argv[i], "-fullscreen")) {
            fullscreen = true;
        } else if (0 == strcmp(argv[i], "-overview")) {
            displayQuickview = true;
        } else if (0 == strcmp(argv[i], "-histogram")) {
            displayHist = true;
        } else if (0 == strcmp(argv[i], "-grid")) {
            displayGrid = true;
        } else if (0 == strcmp(argv[i], "-browse")) {
            browse = true;
        } else if (0 == strcmp(argv[i], "-shuffle")) {
            shuffle = true;
        } else if (0 == strcmp(argv[i], "-winname")) {
            if ((i + 1) < argc)
                win_name = argv[++i];
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-winclass")) {
            if ((i + 1) < argc)
                win_class = argv[++i];
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-yoffset")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%d", &yoffset);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-xoffset")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%d", &xoffset);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-h360")) {
            h360 = true;
//        } else if (0 == strcmp(argv[i], "-xthreads")) {
//            XInitThreads();
//            fprintf(stderr, "Threads initialized\n");
        } else if (0 == strcmp(argv[i], "-maxzoom")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%f", &zoom_max);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-swapaxes")) {
            swapaxes = -1;
        } else if (0 == strcmp(argv[i], "-spsens")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%f", &spsens);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-spacenav")) {
            spacenav = true;
            if (slavemode) {
                fprintf(stderr, "Cannot include -spacenav and -listenaddr / -listenport on the same command.");
                exit(0);
            }
        } else if (0 == strcmp(argv[i], "-spdev")) {
            if ((i + 1) < argc)
                spdev = argv[++i];
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-multicast")) {
            if (slavemode) {
                multicast = true;
            }
            else {
                fprintf(stderr, "Use -multicast only in slave mode, after the -listenaddr or -listenport options\n");
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-broadcast")) {
            if (! slavemode && num_slaves > 0) {
                slavehosts[num_slaves-1].broadcast = true;
            }
            else {
                fprintf(stderr, "Please use -broadcast only after a -slavehost option\n");
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-slavehost")) {
            if (num_slaves >= MAX_SLAVES) {
                fprintf(stderr, "You tried to allocate more than %d slaves. I'm afraid Ican't let you do that, Dave.\n", MAX_SLAVES);
                exit(1);
            }
            if ((i + 1) < argc) {
                dummy_pchar = strchr(argv[++i], ':');
                if (dummy_pchar) {
                    memset(slavehosts[num_slaves].host, 0, SLAVE_ADDR_LEN);
                    strncpy(slavehosts[num_slaves].host, argv[i], dummy_pchar - argv[i]);
                    slavehosts[num_slaves].port = atoi(dummy_pchar + 1);
                    fprintf(stderr, "Added slave host %s:%d\n", slavehosts[num_slaves].host, slavehosts[num_slaves].port);
                    num_slaves++;
                }
                else {
                    fprintf(stderr, "I can't understand \"%s\". I expect something of the form addr:port\n", dummy_pchar);
                    exit(1);
                }
            }
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-listenaddr")) {
            if ((i + 1) < argc) {
                listenaddr = argv[++i];
                slavemode = true;
            }
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-listenport")) {
            if ((i + 1) < argc) {
                sscanf(argv[++i], "%d", &listenport);
                slavemode = true;
            }
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-bilinear")) {
            bilin = true;
        } else if (0 == strcmp(argv[i], "-v")) {
            verbose = true;
        } else if (0 == strcmp(argv[i], "-threads")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%d", &ncores);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-cache")) {
            if ((i + 1) < argc)
                sscanf(argv[++i], "%d", &CACHE_NBIMAGES);
            else {
                usage(argv[0]);
                exit(1);
            }
        } else if (0 == strcmp(argv[i], "-fifo")) {
            if ((i + 1) < argc)
                fifo = argv[++i];
            if (slavemode) {
                fprintf(stderr, "Cannot include -fifo and -listenaddr / -listenport on the same command.");
                exit(0);
            }
        } else {
            struct stat statbuf;
            if (lstat(argv[i], &statbuf) != -1) {
                // If a dir was passed, set browse to true
                if (S_ISDIR(statbuf.st_mode)) {
                    browse = true;
                }
                // Add file to list
                if (nbfiles < MAX_NBFILES)
                    files[nbfiles++] = strdup(argv[i]);
            }
        }
    }

    if (!fakewin) {
        XInitThreads();
        if (! (display = XOpenDisplay(NULL))) {
            fprintf(stderr, "Cannot connect to X server\n");
            exit(0);
        }
        screen = DefaultScreen(display);
        depth = DefaultDepth(display, screen);

        if (do_double_buff && XdbeQueryExtension(display, &major, &minor)) {
            fprintf(stderr, "xdbe (%d, %d) supported, so we'll double-buffer\n", major, minor);
            Drawable screens[] = { DefaultRootWindow(display) };
            int nscreens = 1;
            XdbeScreenVisualInfo *info = XdbeGetVisualInfo(display, screens, &nscreens);
            if (!info || nscreens < 1 || info->count < 1) {
                fprintf(stderr, "No visuals support Xdbe\n");
                exit(1);
            }
            XVisualInfo xvisinfo_temp1;
            xvisinfo_temp1.visualid = info->visinfo[0].visual;
            xvisinfo_temp1.screen = 0;
            xvisinfo_temp1.depth = info->visinfo[0].depth;
            delete info;

            int matches;
            XVisualInfo *xvisinfo_match = XGetVisualInfo(display, VisualIDMask | VisualScreenMask | VisualDepthMask, &xvisinfo_temp1, &matches);
            if (!xvisinfo_match || matches < 1) {
                fprintf(stderr, "Couldn't match a visual with double buffering\n");
                exit(1);
            }
            visual = xvisinfo_match->visual;
            delete xvisinfo_match;
            can_double_buff = true;
        }
        else {
            visual = DefaultVisual(display, screen);
        }

        w = XDisplayWidth(display, screen);
        h = XDisplayHeight(display, screen);
        wref = w;
        href = h;

        watch = XCreateFontCursor(display, XC_watch);
        normal = XCreateFontCursor(display, XC_left_ptr);
    }

    if (spacenav) {
        pthread_create(&thSpacenav, NULL, spacenav_handler, 0);
    }
    if (slavemode) {
        pthread_create(&thUDPSlave, NULL, udp_handler, 0);
    } else if (num_slaves > 0) {
        pthread_create(&thUDPMaster, NULL, send_coords, 0);
    }
    // Create the image cache.
    {
        MutexProtect mp(&mutexCache);
        imgCache = (Image **) malloc(CACHE_NBIMAGES * sizeof(Image *));
        if (imgCache == NULL) {
            fprintf(stderr, "Not enough memory\n");
            exit(1);
        }
        for (int i = 0; i < CACHE_NBIMAGES; i++) {
            imgCache[i] = 0;
        }
    }

    // No files and no fifo, display usage and exit
    if (nbfiles == 0 && fifo == NULL) {
        usage(argv[0]);
        exit(1);
    }
    // Expand file list
    if (nbfiles == 1 && browse) {
        struct stat statbuf;
        if (lstat(files[0], &statbuf) == -1) {
            fprintf(stderr, "Unable to open %s\n", files[0]);
            exit(1);
        }
        char *basepart = NULL;
        char *dirpart = NULL;
        char *start = NULL;
        if (S_ISDIR(statbuf.st_mode)) {
            dirpart = strdup(files[0]);    // Leaked
            free(files[0]);    // Remove the dir
            nbfiles = 0;
        } else {
            // These strings will be leaked
            basepart = basename(strdup(files[0]));
            dirpart = dirname(strdup(files[0]));
            if (start == NULL)
                start = files[0];
        }
        DIR *dir = opendir(dirpart);
        if (dir != NULL) {
            // Add every file in the directory
            for (struct dirent * dirent;
                 (dirent = readdir(dir)) != NULL;) {
                if (strncmp(dirent->d_name, ".", 1) == 0 ||    // Ignores everything starting with "."
                    (basepart != NULL
                     && strcmp(dirent->d_name, basepart) == 0))
                    continue;

                files[nbfiles] =
                    (char *)malloc(strlen(dirpart) + 2 +
                           strlen(dirent->d_name));
                sprintf(files[nbfiles], "%s/%s", dirpart,
                    dirent->d_name);
                // Add only regular files
                if (is_file(files[nbfiles]))
                    nbfiles++;
                else
                    free(files[nbfiles]);
            }

            closedir(dir);
        }
        // Sort files
        qsort(files, nbfiles, sizeof(char *), cmpstr);
        // Start with the requested file
        if (start != NULL) {
            for (idxfile = 0; idxfile < nbfiles; idxfile++)
                if (0 == strcmp(start, files[idxfile]))
                    break;
        }

    }
    // Shuffle files
    if (shuffle && nbfiles) {
        if (verbose)
            fprintf(stderr, "Shuffling files\n");
        srand(time(NULL));
        for (int i = 0; i < nbfiles; i++) {
            int i1 = rand() % nbfiles;
            int i2 = rand() % nbfiles;
            char *tmp = files[i1];
            files[i1] = files[i2];
            files[i2] = tmp;
        }
    }
    // Try to detect number of cores
    if (ncores == 0) {
        FILE *f = fopen("/proc/cpuinfo", "r");
        char tmp[1024];
        if (fgets(tmp, 1024, f)) {
            while (!feof(f)) {
                if (strstr(tmp, "processor") == tmp)
                    ncores++;
                if (!fgets(tmp, 1024, f)) break;
            }
        }
        fclose(f);
        if (ncores == 0)
            ncores = 1;
    }
    // If several cores are available, create variables for multithreaded drawing
    if (ncores > 1 && !fakewin) {
        thFill = (pthread_t *) malloc(ncores * sizeof(pthread_t));
        fillBounds = (int *)malloc((ncores + 1) * sizeof(int));
        if (thFill == NULL || fillBounds == NULL) {
            fprintf(stderr, "Not enough memory\n");
            exit(1);
        }
    }
    if (verbose)
        fprintf(stderr, "%d core(s).\n", ncores);

    // Open the fifo if requested.
    if (fifo != NULL) {
        if (mkfifo(fifo, 0700)) {
            fprintf(stderr, "Can't create fifo %s\n", fifo);
            exit(1);
        }
        pthread_create(&thFifo, NULL, async_fifo, 0);
    }
    float xp = 0, yp = 0;

    //#define PERF
#ifdef PERF
    printf("Load image %s\n", files[0]);
    imgCurrent = load_image(files[0]);
    printf("done\n");
    time_t debut = time(NULL);
    if (fakewin) {
        w = wref;
        h = href;
    } else {
        w = 2048;
        h = 2048;
    }
    data = (unsigned char *)malloc(4 * w * h);
    full_extend();
    xp = z * cos(a) * w / 2 - z * sin(a) * h / 2 + dx;
    yp = z * sin(a) * h / 2 + z * cos(a) * h / 2 + dy;

    z /= 3;
    a = 0.1;

    dx = xp - (z * cos(a) * w / 2 - z * sin(a) * h / 2);
    dy = yp - (z * sin(a) * w / 2 + z * cos(a) * h / 2);

    bilin = true;

    gm = 1.1;
    for (int i = 0; i < 30; i++) {
        fill();
    }

    printf("GM=%f NB=%d %ds\n", gm, imgCurrent->nb, time(NULL) - debut);
    debut = time(NULL);
    gm = 1;

    for (int i = 0; i < 30; i++) {
        fill();
    }

    printf("GM=%f NB=%d %ds\n", gm, imgCurrent->nb, time(NULL) - debut);

    exit(1);
#endif

    // If no requested files, add the default one (for fifo to load one)
    if (nbfiles == 0) {
        files[nbfiles++] = strdup(PREFIX "/share/xiv/xiv.ppm");
    }

    if (!fakewin) {
        gc = DefaultGC(display, screen);
        XSetForeground(display, gc, BlackPixel(display, screen));
        XSetBackground(display, gc, 0xFFA000);
    
        wmDeleteMessage = XInternAtom(display, "WM_DELETE_WINDOW", False);
        create_window(fullscreen);
    
        pthread_create(&th, NULL, async_fill, 0);
    } else {
        // Normally done on first window resize
        pthread_mutex_lock(&mutexData);
        display_image(files[idxfile]);
        pthread_mutex_unlock(&mutexData);
    }

    pthread_create(&thPreload, NULL, async_load, 0);

    #ifdef WATCHDOG
        pthread_create(&thWatchdog, NULL, watchdog_handler, 0);
    #endif

    bool leftdown = false;
    bool done = false;

    run = true;

    // Event Loop
    do {
        done = false;
        while (!done) {
            if (fakewin) {
                usleep(1000000);
            }
            else if (XPending(display)) {
                XNextEvent(display, &event);
                done = true;
            }
            else {
                usleep(100);
            }
        }

        if (event.type == Expose && event.xexpose.count < 1
            && image != NULL && image->data != NULL) {
            if (verbose)
                fprintf(stderr, "Expose\n");
            refresh = true;
            //XClearWindow(display, window);
            //XPutImage(display, window, gc, image, 0, 0, 0, 0, w, h);
            //XPutImage(display, window, gc, image, xoffset - dx, yoffset - dy, 0, 0, w, h);
            //XFlush(display);
        } else if (event.type == ConfigureNotify)    // Handle window resizing
        {
            if (verbose)
                fprintf(stderr, "Configure %d %d %d\n",
                    event.xconfigure.width,
                    event.xconfigure.height, image == NULL);
            if (w != event.xconfigure.width
                || h != event.xconfigure.height || image == NULL) {
                if (image != NULL) {
                    pthread_mutex_lock(&mutexWin);
                    XDestroyImage(image);    // This destroys the data pointer as well.
                    pthread_mutex_unlock(&mutexWin);
                } else {
                    pthread_mutex_lock(&mutexData);
                    display_image(files[idxfile]);
                    pthread_mutex_unlock(&mutexData);
                }

                // Keep image centered
                pthread_mutex_lock(&mutexData);
                xp = z * cos(a) * w / 2 - z * sin(a) * h / 2 + dx;
                yp = z * sin(a) * w / 2 + z * cos(a) * h / 2 + dy;
                w = event.xconfigure.width;
                osdSize = w / 7;    // Adjust OSD size
                h = event.xconfigure.height;
                data = (unsigned char *)malloc(w * h * 4);    // Allocate new drawing area
                if (data == NULL) {
                    fprintf(stderr, "Not enough memory\n");
                    exit(1);
                }
                // Keep image centered
                dx = xp - (z * cos(a) * (w / 2) -
                       z * sin(a) * (h / 2));
                dy = yp - (z * sin(a) * (w / 2) +
                       z * cos(a) * (h / 2));
                image =
                    XCreateImage(display, visual, depth,
                         ZPixmap, 0, (char *)data, w, h,
                         32, 0);
                pthread_mutex_unlock(&mutexData);

                //pixmap = XCreatePixmap(display, window, w, h, depth);
            }
        } else if (!slavemode && event.type == ButtonPress
            && event.xbutton.button == Button2) {
            next_image(-1);
        } else if (!slavemode && event.type == ButtonPress
            && event.xbutton.button == Button3) {
            next_image(1);
        } else if (!slavemode && event.type == ButtonPress
            && event.xbutton.button == Button4) {
            // Wheel Forward
            Window r, wr;
            int wx, wy, rx, ry;
            unsigned int m;
            pthread_mutex_lock(&mutexWin);
            XQueryPointer(display, window, &r, &wr, &rx, &ry, &wx,
                    &wy, &m);
            pthread_mutex_unlock(&mutexWin);

            // Zoom/Rotate on current position
            pthread_mutex_lock(&mutexData);
            xp = z * cos(a) * wx - z * sin(a) * wy + dx;
            yp = z * sin(a) * wx + z * cos(a) * wy + dy;

            if (m & Mod1Mask)    // Alt is pressed -> Rotate
            {
                if (m & ShiftMask)
                    a -= 0.5 * M_PI / 180;
                else
                    a -= 5 * M_PI / 180;
            } else    // No Alt -> Zoom
            {
                float zf;

                if (m & ShiftMask)
                    zf = z / 1.05;
                else
                    zf = z / 1.5;
                zoom(zf);
            }

            dx = xp - (z * cos(a) * wx - z * sin(a) * wy);
            dy = yp - (z * sin(a) * wx + z * cos(a) * wy);
            pthread_mutex_unlock(&mutexData);
        } else if (!slavemode && event.type == ButtonPress
            && event.xbutton.button == Button5) {
            // Wheel Backward
            Window r, wr;
            int wx, wy, rx, ry;
            unsigned int m;
            pthread_mutex_lock(&mutexWin);
            XQueryPointer(display, window, &r, &wr, &rx, &ry, &wx,
                    &wy, &m);
            pthread_mutex_unlock(&mutexWin);

            // Unzoom from current position
            pthread_mutex_lock(&mutexData);
            xp = z * cos(a) * wx - z * sin(a) * wy + dx;
            yp = z * sin(a) * wx + z * cos(a) * wy + dy;

            if (m & Mod1Mask) {
                if (m & ShiftMask)
                    a += 0.2 * M_PI / 180;
                else
                    a += 5 * M_PI / 180;
            } else {
                float zf;

                if (m & ShiftMask)
                    zf = z * 1.05;
                else
                    zf = z * 1.5;
                zoom(zf);
            }

            dx = xp - (z * cos(a) * wx - z * sin(a) * wy);
            dy = yp - (z * sin(a) * wx + z * cos(a) * wy);
            pthread_mutex_unlock(&mutexData);
        } else if (!slavemode && event.type == ButtonPress
            && event.xbutton.button == Button1) {
            // Left is down
            leftdown = true;
            bilinMove = bilin;
            bilin = false;
            Window r, wr;
            int wx, wy, rx, ry;
            unsigned int m;
            pthread_mutex_lock(&mutexWin);
            XQueryPointer(display, window, &r, &wr, &rx, &ry, &wx,
                    &wy, &m);
            pthread_mutex_unlock(&mutexWin);
            if (m & ShiftMask) {
                displayZone = true;
                zx1 = zx2 = wx;
                zy1 = zy2 = wy;
            } else {
                xp = z * cos(a) * wx - z * sin(a) * wy + dx;
                yp = z * sin(a) * wx + z * cos(a) * wy + dy;
            }

        } else if (!slavemode && event.type == ButtonRelease
            && event.xbutton.button == Button1) {
            // Left is up
            leftdown = false;
            bilin = bilinMove;
            if (displayZone) {
                Window r, wr;
                int wx, wy, rx, ry;
                unsigned int m;
                pthread_mutex_lock(&mutexWin);
                XQueryPointer(display, window, &r, &wr, &rx,
                        &ry, &wx, &wy, &m);
                pthread_mutex_unlock(&mutexWin);
                displayZone = false;
                if (m & ShiftMask && zx1 < zx2 && zy1 < zy2) {
                    pthread_mutex_lock(&mutexData);
                    float xp1 =
                        z * cos(a) * zx1 -
                        z * sin(a) * zy1 + dx;
                    float yp1 =
                        z * sin(a) * zx1 +
                        z * cos(a) * zy1 + dy;
                    float xp2 =
                        z * cos(a) * zx2 -
                        z * sin(a) * zy2 + dx;
                    float yp2 =
                        z * sin(a) * zx2 +
                        z * cos(a) * zy2 + dy;
                    xp = (xp1 + xp2) / 2;
                    yp = (yp1 + yp2) / 2;
                    // Compute new zoom
                    z = max(fabsf((xp2 - xp1) / w),
                        fabsf((yp2 - yp1) / h));
                    // Center view on center of zone
                    dx = xp - (z * cos(a) * (w / 2) -
                        z * sin(a) * (h / 2));
                    dy = yp - (z * sin(a) * (w / 2) +
                        z * cos(a) * (h / 2));
                    pthread_mutex_unlock(&mutexData);
                } else if (m & ShiftMask && zx1 > zx2
                    && zy1 > zy2) {
                    pthread_mutex_lock(&mutexData);
                    float xp1 =
                        z * cos(a) * zx1 -
                        z * sin(a) * zy1 + dx;
                    float yp1 =
                        z * sin(a) * zx1 +
                        z * cos(a) * zy1 + dy;
                    float xp2 =
                        z * cos(a) * zx2 -
                        z * sin(a) * zy2 + dx;
                    float yp2 =
                        z * sin(a) * zx2 +
                        z * cos(a) * zy2 + dy;
                    xp = (xp1 + xp2) / 2;
                    yp = (yp1 + yp2) / 2;
                    // Compute new zoom
                    z /= max(fabsf((xp2 - xp1) / w),
                        fabsf((yp2 - yp1) / h));
                    // Center view on center of zone
                    dx = xp - (z * cos(a) * (w / 2) -
                        z * sin(a) * (h / 2));
                    dy = yp - (z * sin(a) * (w / 2) +
                        z * cos(a) * (h / 2));
                    pthread_mutex_unlock(&mutexData);
                }
            }

        } else if (!slavemode && leftdown)    // Handle mouse based pan
        {
            Window r, wr;
            int wx, wy, rx, ry;
            unsigned int m;

            pthread_mutex_lock(&mutexWin);
            XQueryPointer(display, window, &r, &wr, &rx, &ry, &wx,
                    &wy, &m);
            pthread_mutex_unlock(&mutexWin);
            if (displayZone) {
                zx2 = wx;
                zy2 = wy;
            } else {
                pthread_mutex_lock(&mutexData);
                dx = xp - (z * cos(a) * wx - z * sin(a) * wy);
                dy = yp - (z * sin(a) * wx + z * cos(a) * wy);
                pthread_mutex_unlock(&mutexData);
            }
        } else if (event.type == KeyPress) {
            char c[11];
            KeySym ks;
            XComposeStatus cs;
            int nc = XLookupString(&(event.xkey), c, 10, &ks, &cs);
            c[nc] = 0;

            Window r, wr;
            int wx, wy, rx, ry;
            unsigned int m;
            {
                pthread_mutex_lock(&mutexWin);
                XQueryPointer(display, window, &r, &wr, &rx,
                        &ry, &wx, &wy, &m);
                pthread_mutex_unlock(&mutexWin);
            }

            if (0 == strcmp(c, "q") || 0 == strcmp(c, "Q"))    // Quit
            {
                write_points(files[idxfile]);
                run = false;
            } else if (! slavemode) {
                if (0 == strcmp(c, "1") || 0 == strcmp(c, "2") || 0 == strcmp(c, "3") || 0 == strcmp(c, "4") || 0 == strcmp(c, "5") || 0 == strcmp(c, "6") || 0 == strcmp(c, "7") || 0 == strcmp(c, "8") || 0 == strcmp(c, "9"))    // Zoom level keep center view
                {
                    pthread_mutex_lock(&mutexData);
                    xp = z * cos(a) * w / 2 - z * sin(a) * h / 2 + dx;
                    yp = z * sin(a) * h / 2 + z * cos(a) * h / 2 + dy;

                    z = 1 / atof(c);
                    if (m & Mod1Mask)
                        z = 1 / z;

                    dx = xp - (z * cos(a) * w / 2 -
                        z * sin(a) * h / 2);
                    dy = yp - (z * sin(a) * w / 2 +
                        z * cos(a) * h / 2);

                    pthread_mutex_unlock(&mutexData);
                }
                if (0 == strcmp(c, "+") || 0 == strcmp(c, "z"))    // Zoom keep center view
                {
                    pthread_mutex_lock(&mutexData);
                    zoom(z / 1.5);
                    pthread_mutex_unlock(&mutexData);
                } else if (0 == strcmp(c, "-") || 0 == strcmp(c, "Z"))    // Unzoom keep center view
                {
                    pthread_mutex_lock(&mutexData);
                    zoom(z * 1.5);
                    pthread_mutex_unlock(&mutexData);
                } else if (0 == strcmp(c, "/") || 0 == strcmp(c, "*"))    // Rotate PI/2
                {
                    pthread_mutex_lock(&mutexData);
                    float fa = 0;
                    int n = (int)(a / (M_PI / 2));
                    if (n > 3)
                        n = 0;
                    if (n < -3)
                        n = 0;
                    if (0 == strcmp(c, "/"))
                        fa = (n + 1) * M_PI / 2;
                    else
                        fa = (n - 1) * M_PI / 2;
                    rotate(fa);
                    pthread_mutex_unlock(&mutexData);
                } else if (0 == strcmp(c, " ") || 0 == strcmp(c, "."))    // Center on current pointer position
                {
                    pthread_mutex_lock(&mutexData);
                    xp = z * cos(a) * wx - z * sin(a) * wy + dx;
                    yp = z * sin(a) * wx + z * cos(a) * wy + dy;

                    dx = xp - (z * cos(a) * (w / 2) -
                        z * sin(a) * (h / 2));
                    dy = yp - (z * sin(a) * (w / 2) +
                        z * cos(a) * (h / 2));
                    pthread_mutex_unlock(&mutexData);
                } else if (0 == strcmp(c, "s")) {
                    displayPts = !displayPts;
                    refresh = true;
                } else if (0 == strcmp(c, "a")) {
                    displayAbout = !displayAbout;
                    refresh = true;
                } else if (0 == strcmp(c, "f")) {
                    pthread_mutex_lock(&mutexWin);
                    fullscreen = !fullscreen;
                    destroy_window();
                    create_window(fullscreen);
                    pthread_mutex_unlock(&mutexWin);
                } else if (0 == strcmp(c, "c") || 0 == strcmp(c, "C"))    // Contrast +/-
                {
                    if (0 == strcmp(c, "C"))
                        cr -= 8;
                    else
                        cr += 8;
                    if (cr <= 0)
                        cr = 1;
                } else if (0 == strcmp(c, "g") || 0 == strcmp(c, "G"))    // Contrast +/-
                {
                    if (0 == strcmp(c, "g"))
                        gm *= 1.1;
                    else
                        gm /= 1.1;
                } else if (0 == strcmp(c, "h"))    // Toggle display histogram
                {
                    displayHist = !displayHist;
                    refresh = true;
                } else if (0 == strcmp(c, "m"))    // Toggle display grid
                {
                    displayGrid = !displayGrid;
                    refresh = true;
                } else if (0 == strcmp(c, "o"))    // Toggle display overview
                {
                    displayQuickview = !displayQuickview;
                    refresh = true;
                } else if (0 == strcmp(c, "b"))    // Toggle bilinear interpolation
                {
                    bilin = !bilin;
                } else if (0 == strcmp(c, "l") || 0 == strcmp(c, "L"))    // Luminosity +/-
                {
                    if (0 == strcmp(c, "l"))
                        lu += 8;
                    else
                        lu -= 8;
                } else if (0 == strcmp(c, "v"))    // Reset Luminosity/Contrast
                {
                    lu = 0;
                    cr = 255;
                    gm = 1;
                } else if (0 == strcmp(c, "i"))    // Invert radiometry
                {
                    revert = !revert;
                } else if (0 == strcmp(c, "=") || 0 == strcmp(c, "r") || 0 == strcmp(c, "0"))    // Reset view
                {
                    pthread_mutex_lock(&mutexData);
                    full_extend();
                    pthread_mutex_unlock(&mutexData);
                } else if (0 == strcmp(c, "n") || 0 == strcmp(c, "p") || 0 == strcmp(c, "N") || 0 == strcmp(c, "P"))    // next/previous image
                {
                    if (0 == strcmp(c, "n"))
                        next_image(1);
                    else if (0 == strcmp(c, "N"))
                        next_image(nbfiles / 20);
                    else if (0 == strcmp(c, "p"))
                        next_image(-1);
                    else
                        next_image(-nbfiles / 20);
                } else if (0 == strcmp(c, "D"))    // Delete image 
                {
                    if (nbfiles > 0) {
                        unlink(files[idxfile]);
                        free(files[idxfile]);
                        nbfiles--;
                        for (int i = idxfile; i < nbfiles; i++)
                            files[i] = files[i + 1];
                        next_image(0);
                    }
                } else if (0 == strcmp(c, "d"))    // Move image to file.jpg.del so that you can undelete it.
                {
                    if (nbfiles > 0) {
                        // Append .del to filename and rename file to it
                        // The file is not actually deleted.
                        char *tmp =
                            (char *)
                            malloc(strlen(files[idxfile]) + 5);
                        tmp[0] = 0;
                        sprintf(tmp, "%s.del", files[idxfile]);
                        rename(files[idxfile], tmp);
                        free(tmp);
                        free(files[idxfile]);
                        nbfiles--;
                        for (int i = idxfile; i < nbfiles; i++)
                            files[i] = files[i + 1];
                        next_image(0);
                    }
                } else if (ks == XK_Left)    // Key based Pan / Rotate
                {
                    pthread_mutex_lock(&mutexData);
                    if (m & Mod1Mask) {
                        if (m & ShiftMask)
                            rotate(a + 0.2 * M_PI / 180);
                        else
                            rotate(a + 5 * M_PI / 180);
                    } else {
                        if (m & ShiftMask)
                            translate(-w / 20, 0);
                        else
                            translate(-w / 5, 0);
                    }
                    pthread_mutex_unlock(&mutexData);
                } else if (ks == XK_Right)    // Key based Pan / Rotate
                {
                    pthread_mutex_lock(&mutexData);
                    if (m & Mod1Mask) {
                        if (m & ShiftMask)
                            rotate(a - 0.2 * M_PI / 180);
                        else
                            rotate(a - 5 * M_PI / 180);
                    } else {
                        if (m & ShiftMask)
                            translate(w / 20, 0);
                        else
                            translate(w / 5, 0);
                    }
                    pthread_mutex_unlock(&mutexData);
                } else if (ks == XK_Up)    // Key based Pan Up
                {
                    pthread_mutex_lock(&mutexData);
                    if (m & ShiftMask)
                        translate(0, h / 20);
                    else
                        translate(0, h / 5);
                    pthread_mutex_unlock(&mutexData);
                } else if (ks == XK_Down)    // Key based Pan Down
                {
                    pthread_mutex_lock(&mutexData);
                    if (m & ShiftMask)
                        translate(0, -h / 20);
                    else
                        translate(0, -h / 5);
                    pthread_mutex_unlock(&mutexData);
                } else if (ks == XK_F1 || ks == XK_F2 || ks == XK_F3
                    || ks == XK_F4 || ks == XK_F5 || ks == XK_F6
                    || ks == XK_F7 || ks == XK_F8 || ks == XK_F9
                    || ks == XK_F10) {
                    pthread_mutex_lock(&mutexData);
                    xp = z * cos(a) * wx - z * sin(a) * wy + dx;
                    yp = z * sin(a) * wx + z * cos(a) * wy + dy;

                    int idxp = 0;
                    switch (ks) {
                    case XK_F1:
                        idxp = 1;
                        break;
                    case XK_F2:
                        idxp = 2;
                        break;
                    case XK_F3:
                        idxp = 3;
                        break;
                    case XK_F4:
                        idxp = 4;
                        break;
                    case XK_F5:
                        idxp = 5;
                        break;
                    case XK_F6:
                        idxp = 6;
                        break;
                    case XK_F7:
                        idxp = 7;
                        break;
                    case XK_F8:
                        idxp = 8;
                        break;
                    case XK_F9:
                        idxp = 9;
                        break;
                    case XK_F10:
                        idxp = 10;
                        break;
                    }

                    if (verbose)
                        fprintf(stderr, "%d:%f %f\n", idxp, xp,
                            yp);
                    pts[2 * (idxp - 1) + 0] = xp;
                    pts[2 * (idxp - 1) + 1] = yp;
                    pthread_mutex_unlock(&mutexData);
                    refresh = true;
                }
            }
        } else if (event.type == ClientMessage &&
               (Atom) event.xclient.data.l[0] == wmDeleteMessage) {
            run = false;
        }

    } while (run);

    // Cleanup before leaving
    {
        pthread_mutex_lock(&mutexData);
        if (image != NULL)
            XDestroyImage(image);
        pthread_mutex_unlock(&mutexData);
        if (!fakewin) {
            pthread_mutex_lock(&mutexWin);
            XDestroyWindow(display, window);
            pthread_mutex_unlock(&mutexWin);
            XCloseDisplay(display);
        }
    }

    // Remove the fifo file if need be
    if (fifo != NULL) {
        unlink(fifo);
        fifo = NULL;
    }

    quit();

    if (thFill != NULL)
        free(thFill);
    if (fillBounds != NULL)
        free(fillBounds);

    for (int i = 0; i < nbfiles; i++)
        free(files[i]);
    free(files);

    MutexProtect mp(&mutexCache);
    for (int i = 0; i < CACHE_NBIMAGES; i++) {
        delete imgCache[i];
    }
    free(imgCache);

    return 0;
}
