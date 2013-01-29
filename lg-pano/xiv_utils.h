#ifndef _xiv_utils_h_
#define _xiv_utils_h_

#include "xiv.h"

void draw_grid(int w, int h, int ncells, unsigned char* data);
int max(int a,int b);
int min(int a,int b);
float max(float a,float b);
float min(float a,float b);
void compute_histogram(Image* img, int* histr, int* histg, int* histb, int& histMax);
int orientation(const char* file);
bool is_file(const char* path);
int cmpstr(const void* p1, const void* p2);
void draw_histogram(Image* img, int w, int h, unsigned char* data, int* histr, int* histg, int* histb, int histMax,int osdSize,int lu, int cr, int* powv);

#endif
