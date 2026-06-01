#include <sys/ioctl.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include "include/ios_termios_c.h"

int libc_ioctl(int fd, unsigned long request, void *arg) {
    return ioctl(fd, request, arg);
}
