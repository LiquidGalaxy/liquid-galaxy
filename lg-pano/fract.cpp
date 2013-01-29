/***********************************************
 *	Juliazoom1.c
 *
 *  Generates a RAW format file of an image 
 *  of a Julia set (grayscale)
 *
 *  C source file by Alberto Strumia
 *
 ************************************************/

// Updated by Gilles Bernard to generate sample 16bits ppm file.

#include<stdio.h>

/* definition of constants */

#define Radius 10
#define Cx 0.7454294
#define Cy 0.113089
#define Side 1.7
// Size of output image
#define M 16384
#define Num 1024
/* alternative values Side 0.25, 0.025*/

inline unsigned short swap(unsigned short s)
{
  if(s>1023) s=1023;
  unsigned short r;
  unsigned char* sc=(unsigned char*)&s;
  unsigned char* rc=(unsigned char*)&r;
  rc[0]=sc[1];
  rc[1]=sc[0];
  return r;
}


/* main program */
main()
{
	
  int p, q, n, w;
  double x, y, xx, yy, Incx, Incy;

  // GBE Create a Red -> Yellow -> White colormap
  unsigned short cmapr[1024];
  unsigned short cmapg[1024];
  unsigned short cmapb[1024];
	
  for(int i=0;i<1024;i++)
    {
      if(i<342)
	{
	  cmapr[i]=swap(i*1024/342);
	  cmapg[i]=0;
	  cmapb[i]=0;
	}
      else if(i<684)
	{
	  cmapr[i]=swap(1024);
	  cmapg[i]=swap((i-342)*1024/342);
	  cmapb[i]=0;
	}
      else
	{
	  cmapr[i]=cmapg[i]=swap(1024);
	  cmapb[i]=swap((i-684)*1024/342);
	}
    }

  FILE *fp;
  fp = fopen("Julia.ppm","w");
  // Write PPM header
  fprintf(fp,"P6\n%d %d\n65535\n",M,M);
	
  for (p = 1; p <= M; p++)
    {
      Incy = - Side + 2*Side/M*p;
	
      for (q = 1; q <= M; q++)
	{
	  Incx = - Side + 2*Side/M*q;
			
	  x =  Incx;
	  y =  Incy;
	  w = 200;
			
	  for ( n = 1; n <= Num; ++n)
	    {
	      xx = x*x - y*y - Cx;
	      yy = 2*x*y - Cy;
				
	      x = xx;
	      y = yy;
				
	      if ( x*x + y*y > Radius )
		{
		  w = n;
		  n = Num;
		}
	    }
	  
	  // w is in between 0 and 1024.
	  unsigned short v=cmapr[w<1024?w:1023];
	  fwrite((unsigned char*)&v,2,1,fp);
	  v=cmapg[w<1024?w:1023];
	  fwrite((unsigned char*)&v,2,1,fp);
	  v=cmapb[w<1024?w:1023];
	  fwrite((unsigned char*)&v,2,1,fp);
	}
    }
	
  fclose(fp);
}

/* end of main program */
