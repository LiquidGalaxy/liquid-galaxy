#include "config.h"
#include "xiv_readers.h"
#include <stdio.h>
#ifdef HAVE_LIBJPEG
#include <jpeglib.h>
#endif
#include <setjmp.h>
#ifdef HAVE_LIBTIFF
#include <tiffio.h>
#endif
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern bool verbose;

// Swap bytes of an unsigned short
inline unsigned short swap(unsigned short s)
{
	unsigned short r;
	unsigned char *sc = (unsigned char *)&s;
	unsigned char *rc = (unsigned char *)&r;
	rc[0] = sc[1];
	rc[1] = sc[0];
	return r;
}

// Return endianness 1 -> LSB (ex x86)
inline int endian()
{
	unsigned short s = 1;
	return *(unsigned char *)&s;	// 1 for x86 Little Endian LSB
}

// Read a line from a ppm file discarding comment and empty lines
char *read_ppm_line(FILE * f, char *buf)
{
	if (!fgets(buf, 1024, f)) return NULL;
	// Ignores comment and empty lines
	while (strstr(buf, "#") == buf || strstr(buf, "\n") == buf) {
		if (!fgets(buf, 1024, f)) return NULL;
	}
	return buf;
}

// Read a ppm image, returns 0 if not recognized.
// Returns width, height, nb of bytes (1 or 2) and max value for 16 bits imagery.
// Max value is used in case a 16 bits image has less significant bits (eg 12 or 14 for some camera).
unsigned char *read_ppm(const char *sFile, int &iW, int &iH, int &nbBytes,
			int &max)
{
	FILE *f = fopen(sFile, "rb");
	if (f == NULL)
		return 0;
	char sTmp[1024];
	// P6
	read_ppm_line(f, sTmp);
	if (strstr(sTmp, "P6") != sTmp) {
		fclose(f);
		return 0;
	}
	// iW, iH
	read_ppm_line(f, sTmp);
	sscanf(sTmp, "%d %d", &iW, &iH);
	if (iW < 0 || iW > 65536 || iH < 0 || iH > 65536) {
		fclose(f);
		return 0;
	}
	// 255
	read_ppm_line(f, sTmp);
	if (strstr(sTmp, "255") == sTmp) {
		nbBytes = 1;
		max = 255;
	} else if (strstr(sTmp, "65535") == sTmp) {
		nbBytes = 2;
		max = 0;	// Will be computed later
	} else
		return 0;
	unsigned char *buf = (unsigned char *)malloc(iW * iH * 3 * nbBytes);
	if (buf == NULL)
		return 0;

	if (!fread(buf, iW * iH, 3 * nbBytes, f))
        return 0;
	// If image is 16 bit wide, compute max value in case there a less significant bytes.
	if (nbBytes == 2) {
		unsigned short *p = (unsigned short *)buf;
		for (int i = 0; i < iW * iH * 3; i++) {
			if (endian())
				*p = swap(*p);
			if (*p > max)
				max = *p;
			p++;
		}
	}
	fclose(f);
	return buf;
}

#ifdef HAVE_LIBJPEG
jmp_buf env;

void error_handler(j_common_ptr cinfo)
{
	// Does nothing, it's just to prevent libjpeg from exiting
	longjmp(env, 1);
}
#endif

// Read a jpeg image, returns 0 if not recognized.
// Returns width, height
unsigned char *read_jpeg(const char *sFile, int &iW, int &iH)
{
#ifdef HAVE_LIBJPEG
	FILE *f = fopen(sFile, "rb");
	if (f == NULL)
		return 0;
	struct jpeg_decompress_struct cinfo;
	struct jpeg_error_mgr jerr;
	cinfo.err = jpeg_std_error(&jerr);
	jerr.error_exit = error_handler;

	unsigned char *buf = 0;

	/* Establish the setjmp return context to prevent jpeglib from exiting. */
	if (setjmp(env)) {
		/* If we get here, the JPEG code has signaled an error.
		 * We need to clean up the JPEG object, close the input file, and return.
		 */
		jpeg_destroy_decompress(&cinfo);
		fclose(f);
		if (buf)
			free(buf);

		return 0;
	}
	jpeg_create_decompress(&cinfo);

	jpeg_stdio_src(&cinfo, f);
	if (jpeg_read_header(&cinfo, TRUE) != JPEG_HEADER_OK)
		return 0;

	jpeg_calc_output_dimensions(&cinfo);
	iW = cinfo.output_width;
	iH = cinfo.output_height;
	// Tell libjpeg to convert to RGB
	cinfo.out_color_space = JCS_RGB;

	buf = (unsigned char *)malloc(iW * iH * 3);
	if (buf == NULL)
		return 0;

	jpeg_start_decompress(&cinfo);

	while (cinfo.output_scanline < cinfo.output_height) {
		unsigned char *pImage = buf + cinfo.output_scanline * 3 * iW;
		jpeg_read_scanlines(&cinfo, &pImage, 1);
	}

	jpeg_finish_decompress(&cinfo);

	jpeg_destroy_decompress(&cinfo);

	fclose(f);

	return buf;
#else
	return 0;
#endif
}

// Read a ppm image, returns 0 if not recognized.
// Returns width, height, nb of bytes (1 or 2) and max value for 16 bits imagery.
// Max value is used in case a 16 bits image has less significant bits (eg 12 or 14 for some camera).
unsigned char *read_tiff(const char *file, int &iW, int &iH, int &nbBytes,
			 int &max)
{
#ifdef HAVE_LIBTIFF
	// reject NEF files which could be recognized as TIFF
	if (strlen(file) >= 3
	    && strcasecmp(file + strlen(file) - 3, "nef") == 0)
		return 0;
	TIFF *tif = TIFFOpen(file, "r");
	if (tif) {
		TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &iW);
		TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &iH);
		uint16_t c = 0xFFFF, bs = 8, fo = 1, rs = 1, tw = 1, tl =
		    1, ph = 0, es = 0;
		uint16_t *esv;
		TIFFGetField(tif, TIFFTAG_SAMPLESPERPIXEL, &c);
		TIFFGetField(tif, TIFFTAG_BITSPERSAMPLE, &bs);
		TIFFGetField(tif, TIFFTAG_ROWSPERSTRIP, &rs);
		TIFFGetField(tif, TIFFTAG_FILLORDER, &fo);
		TIFFGetField(tif, TIFFTAG_TILEWIDTH, &tw);
		TIFFGetField(tif, TIFFTAG_TILELENGTH, &tl);
		TIFFGetField(tif, TIFFTAG_PHOTOMETRIC, &ph);
		TIFFGetField(tif, TIFFTAG_EXTRASAMPLES, &es, &esv);
		if (verbose)
			fprintf(stderr,
				"read_tiff %s w %d h %d #c %d bps %d fo %d tile %d %d photo %d es %d\n",
				file, iW, iH, c, bs, fo, tw, tl, ph, es);
		if (c == 0xFFFF)	// Try to guess number of chanels
		{
			if (ph == PHOTOMETRIC_MINISBLACK) {
				c = 1;
			} else if (ph == PHOTOMETRIC_RGB) {
				c = 3;
			} else {
				TIFFClose(tif);
				return 0;
			}
			c += es;
		}

		if (fo == 2 || tw != 1 || tl != 1 || (ph != PHOTOMETRIC_MINISBLACK && ph != PHOTOMETRIC_RGB))	// Don't handle odd fill order or tiled tiff
		{
			TIFFClose(tif);
			return 0;
		}
		if (bs == 16)	// 16b images, compute maxi in case it has less significant bits.
		{
			nbBytes = 2;
			max = 0;
		} else if (bs == 8) {
			nbBytes = 1;
			max = 255;
		}		// 8 bit image, set maxi to 255
		else		// Only handle 16b or 8b images
		{
			TIFFClose(tif);
			return 0;
		}

		tdata_t bufstrip;
		bufstrip = _TIFFmalloc(TIFFStripSize(tif));
		if (bufstrip == NULL) {
			TIFFClose(tif);
			return 0;
		}
		unsigned char *buf =
		    (unsigned char *)malloc(iW * iH * 3 * nbBytes);
		if (buf == NULL) {
			_TIFFfree(bufstrip);
			TIFFClose(tif);
			return 0;
		}

		int row = 0;
		for (unsigned int strip = 0; strip < TIFFNumberOfStrips(tif);
		     strip++) {
			TIFFReadEncodedStrip(tif, strip, bufstrip,
					     (tsize_t) - 1);
			if (nbBytes == 1)	// Case of standard 8 bits images
			{
				unsigned char *p = (unsigned char *)bufstrip;
				for (int rowS = 0; rowS < rs && row < iH;
				     rowS++) {
					for (int col = 0; col < iW; col++) {
						// 3 channels or more (alpha) use only the first 3 ones
						if (c >= 3) {
							for (int cha = 0;
							     cha < 3; cha++) {
								buf[3 *
								    (row * iW +
								     col) +
								    cha] =
								    p[c *
								      (col +
								       rowS *
								       iW) +
								      cha];
							}
						} else {
							buf[3 *
							    (row * iW + col) +
							    0] =
							    buf[3 *
								(row * iW +
								 col) + 1] =
							    buf[3 *
								(row * iW +
								 col) + 2] =
							    p[rowS * iW + col];
						}
					}
					row++;
				}
			} else if (nbBytes == 2)	// Case of 16 bits imagery
			{
				unsigned short *p = (unsigned short *)bufstrip;
				unsigned short *b = (unsigned short *)buf;
				for (int rowS = 0; rowS < rs && row < iH;
				     rowS++) {
					for (int col = 0; col < iW; col++) {
						// 3 channels or more (alpha) use only the first 3 ones
						if (c >= 3) {
							for (int cha = 0;
							     cha < 3; cha++) {
								if (endian())
									b[3 *
									  (row *
									   iW +
									   col)
									  +
									  cha] =
									p[c *
									  (col +
									   rowS
									   *
									   iW) +
									  cha];
								else
									b[3 *
									  (row *
									   iW +
									   col)
									  +
									  cha] =
									swap(p
									     [c
									      *
									      (col
									       +
									       rowS
									       *
									       iW)
									      +
									      cha]);

								if (b
								    [3 *
								     (row * iW +
								      col) +
								     cha] > max)
									max =
									    b[3
									      *
									      (row
									       *
									       iW
									       +
									       col)
									      +
									      cha];
							}
						} else	// Convert Gray -> RGB
						{
							if (endian())
								b[3 *
								  (row * iW +
								   col) + 0] =
								b[3 *
								  (row * iW +
								   col) + 1] =
								b[3 *
								  (row * iW +
								   col) + 2] =
								p[rowS * iW +
								  col];
							else
								b[3 *
								  (row * iW +
								   col) + 0] =
								b[3 *
								  (row * iW +
								   col) + 1] =
								b[3 *
								  (row * iW +
								   col) + 2] =
								swap(p
								     [rowS *
								      iW +
								      col]);
							if (b
							    [3 *
							     (row * iW + col) +
							     0] > max)
								max =
								    b[3 *
								      (row *
								       iW +
								       col) +
								      0];
						}
					}
					row++;
				}
			}
		}
		_TIFFfree(bufstrip);

		TIFFClose(tif);
		return buf;
	}
#endif
	return 0;
}
