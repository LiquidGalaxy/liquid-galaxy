all: spacenav-rezero

CC       ?= gcc
CFLAGS   ?= -g

CXX      ?= g++
CXXFLAGS ?= -Wall -g

COBJS     = src/hid.o
CPPOBJS   = src/spacenav-rezero.o
OBJS      = $(COBJS) $(CPPOBJS)
LIBS      = `pkg-config libudev --libs` -lpthread
INCLUDES ?= -Isrc/hidapi

spacenav-rezero: $(OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $^ $(LIBS) -o spacenav-rezero

$(COBJS): %.o: %.c
	$(CC) $(CFLAGS) -c $(INCLUDES) $< -o $@

$(CPPOBJS): %.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $(INCLUDES) $< -o $@

clean:
	rm -f $(OBJS) spacenav-rezero

.PHONY: clean
