#include "xiv_utils.h"
#include <stdint.h>
#ifdef HAVE_LIBEXIF
#include <libexif/exif-data.h>
#endif
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

int max(int a, int b)
{
	return a > b ? a : b;
}

int min(int a, int b)
{
	return a < b ? a : b;
}

float max(float a, float b)
{
	return a > b ? a : b;
}

float min(float a, float b)
{
	return a < b ? a : b;
}

void draw_grid(int w, int h, int ncells, unsigned char *data)
{
	int step = max(w / ncells, h / ncells);
	for (int i = (h % step) / 2; i < h; i += step) {
		for (int j = 0; j < w; j += 4) {
			int idx = 4 * (i * w + j);

			data[idx] = data[idx] > 128 ? 0 : 255;
			idx++;
			data[idx] = data[idx] > 128 ? 0 : 255;
			idx++;
			data[idx] = data[idx] > 128 ? 0 : 255;
		}
	}
	for (int j = (w % step) / 2; j < w; j += step) {
		for (int i = 0; i < h; i += 4) {
			int idx = 4 * (i * w + j);

			data[idx] = data[idx] > 128 ? 0 : 255;
			idx++;
			data[idx] = data[idx] > 128 ? 0 : 255;
			idx++;
			data[idx] = data[idx] > 128 ? 0 : 255;
		}
	}
}

// Compute histogram of current image
void compute_histogram(Image * img, int *histr, int *histg, int *histb,
		       int &histMax)
{
	memset(histr, 0, 256 * sizeof(int));
	memset(histg, 0, 256 * sizeof(int));
	memset(histb, 0, 256 * sizeof(int));
	histMax = 0;

	if (!img || !img->max)
		return;

	unsigned short *p = (unsigned short *)img->buf;
	int idx = 0;
	int n = img->w * img->h;
	for (int i = 0; i < n; i++) {
		for (int c = 0; c < 3; c++) {
			unsigned int val = 0;
			if (img->nb == 2) {
				val = (p[idx++] * 255) / img->max;
			} else
				val = img->buf[idx++];
			if (val > 255)
				val = 255;
			if (val < 0)
				val = 0;

			switch (c) {
			case 0:
				histr[val]++;
				if (histr[val] > histMax)
					histMax = histr[val];
				break;
			case 1:
				histg[val]++;
				if (histg[val] > histMax)
					histMax = histg[val];
				break;
			case 2:
				histb[val]++;
				if (histb[val] > histMax)
					histMax = histb[val];
				break;
			}
		}
	}
}

// Try to retrieve orientation EXIF attributes from the file
int orientation(const char *file)
{
	int val = 0;
#ifdef HAVE_LIBEXIF
	ExifData *d = exif_data_new_from_file(file);
	if (d != NULL) {
		ExifEntry *e = exif_data_get_entry(d, EXIF_TAG_ORIENTATION);
		if (e != NULL) {
			char tmp[1024];
			exif_entry_get_value(e, tmp, 1024);
			if (0 == strcmp(tmp, "top - left"))
				val = 0;
			else if (0 == strcmp(tmp, "left - bottom"))
				val = 1;
			else if (0 == strcmp(tmp, "bottom - right"))
				val = 2;
			else if (0 == strcmp(tmp, "right - top"))
				val = 3;
		}
		exif_data_unref(d);
	}
#endif
	return val;
}

// Test if path is a regular file
bool is_file(const char *path)
{
	struct stat buf;
	if (stat(path, &buf) == 0) {
		if (S_ISREG(buf.st_mode)) {
			return true;
		}
	}
	return false;
}

// Compare two strings for qsort
int cmpstr(const void *p1, const void *p2)
{
	return strcmp(*(char **)p1, *(char **)p2);
}

void draw_histogram(Image * img, int w, int h, unsigned char *data, int *histr,
		    int *histg, int *histb, int histMax, int osdSize, int lu,
		    int cr, int *powv)
{
	// Histogram
	for (int j = 0; j < osdSize; j++) {
		int maxr = (histr[(j * 255) / osdSize] * osdSize) / histMax;
		int maxg = (histg[(j * 255) / osdSize] * osdSize) / histMax;
		int maxb = (histb[(j * 255) / osdSize] * osdSize) / histMax;
		for (int i = 0; i < osdSize; i++) {
			int val = osdSize - i - 1;
			int idx = w * i + w - osdSize;
			data[4 * (idx + j) + 2] = val <= maxr ? 255 : 0;
			data[4 * (idx + j) + 1] = val <= maxg ? 255 : 0;
			data[4 * (idx + j) + 0] = val <= maxb ? 255 : 0;
		}
	}

	// Radiometry transformation based on luminosity and contrast in the upper right corner
	// rado=lu+(radi*cr)/radMax
	int radimin = 0;
	int radomin = lu;
	int radimax = img->max;
	int radomax = lu + cr;	// lu+(cr*val)/max

	if (radomin < 0) {
		radomin = 0;
		radimin = -(lu * img->max) / cr;
	}

	if (radomax > 255) {
		radomax = 255;
		radimax = ((255 - lu) * img->max) / cr;
	}

	for (int t = 0; t < 256; t++) {
		int radi = radimin + (t * (radimax - radimin)) / 255;
		int rado = lu + (cr * powv[(255 * radi) / img->max]) / 255;
		int j = (radi * osdSize) / img->max;
		int i = osdSize - (rado * osdSize) / 255;
		int idx = 4 * (w * i + w - osdSize + j);

		if (i >= 0 && i < osdSize && j >= 0 && j < osdSize) {
			data[idx++] = 128;
			data[idx++] = 128;
			data[idx] = 128;
		}
	}
}
