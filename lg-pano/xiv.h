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

#ifndef _xiv_h_
#define _xiv_h_

#include "config.h"
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

enum
  {
    IN_PROGRESS,
    READY,
    ERROR
  };

class Image{
public:
 Image(int vw,int vh,int vnb,int vmax,int vnbits,const char* vname,unsigned char* vbuf=0) : w(vw),h(vh),nb(vnb),max(vmax),nbits(vnbits),buf(vbuf), name(strdup(vname)),state(IN_PROGRESS){}
  ~Image(){
    if(buf!=NULL) free(buf);
    if(name!=NULL) free(name);
  }
  int w,h,nb,max;
  int nbits;
  unsigned char* buf;
  char* name;
  int state;
};


class MutexProtect
{
 public:
 MutexProtect(pthread_mutex_t* m) : _m(m) {
    pthread_mutex_lock(_m);
  }
  ~MutexProtect() {
    pthread_mutex_unlock(_m);
  }
  
  pthread_mutex_t* _m;
};
#endif
