The two programs in this directory show how to read and write input_event
structs used by the /dev/input/event* interface to multi-axis devices like
the 3dconnexion SpaceNavigator.

Compile with:

$ gcc -m32 -o read-event read-event.c
$ gcc -m32 -o write-event write-event.c

To use it:

$ mkfifo myfifo
$ ./read-event myfifo

# (in another terminal)
$ ./write-event myfifo 2 10
