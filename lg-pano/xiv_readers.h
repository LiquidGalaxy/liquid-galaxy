#ifndef _xiv_readers_h_
#define _xiv_readers_h_

unsigned char* read_ppm(const char* sFile, int& iW, int& iH, int& nbBytes, int& max);
unsigned char* read_jpeg(const char* sFile, int& iW, int& iH);
unsigned char* read_tiff(const char* file, int& iW, int& iH, int& nbBytes, int& max);


#endif
