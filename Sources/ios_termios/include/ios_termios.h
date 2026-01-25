#ifndef ios_termios_h
#define ios_termios_h

#ifdef __APPLE__
#define _TIME_H
#endif

#include <termios.h>
#include <unistd.h>
#include <stdarg.h>
#include <stddef.h>
#include <fcntl.h>
#include <sys/ioctl.h>

extern int ios_dup(int fd);
extern int ios_dup2(int fd, int fd2);
extern int ios_close(int fd);

extern void ios_register_pty(const char *name, struct termios *termp, struct winsize *winp, int stdin, int stdout, int stderr);
extern int ios_register_child_pty(int parent_fd, int child_fd);
extern void ios_clear_pty(const char *name);

extern int ios_fds_from_ttyname_r(const char *name, int out_fds[3]);
extern int ios_ttyname_r(int fd, char *buf, size_t size);

extern int ios_tcgetwinsize(int fd, struct winsize *w);
extern int ios_tcsetwinsize(int fd, const struct winsize *w);

extern int ios_tcgetattr(int fd, struct termios *termios_p);
extern int ios_tcsetattr(int fd, int optional_actions, const struct termios *termios_p);

extern int ios_tcsendbreak(int fd, int duration);
extern int ios_tcdrain(int fd);
extern int ios_tcflush(int fd, int queue_selector);
extern int ios_tcflow(int fd, int action);

static int (*_orig_ioctl)(int, unsigned long, ...) = ioctl;
extern int ios_winsize_ioctl(int fd, int request, void *arg);
static inline int ios_ioctl(int fd, unsigned int request, ...) {
    va_list ap;
    void *arg = NULL;

    va_start(ap, request);

    if (request == TIOCGWINSZ || request == TIOCSWINSZ) {
        arg = va_arg(ap, void *);
    }

    va_end(ap);

    if (request == TIOCGWINSZ || request == TIOCSWINSZ) {
        return ios_winsize_ioctl(fd, request, arg);
    }

    return _orig_ioctl(fd, request, arg);
}

static int (*_orig_fcntl)(int, int, ...) = fcntl;
static inline int ios_fcntl(int fd, int cmd, ...) {
    va_list ap;
    void *arg = NULL;
    
    va_start(ap, cmd);
    arg = va_arg(ap, void *);
    va_end(ap);
    
    int ret = _orig_fcntl(fd, cmd, arg);
    
    if (ret != -1 && (cmd == F_DUPFD || cmd == F_DUPFD_CLOEXEC)) {
        ios_register_child_pty(fd, ret);
    }
    
    return ret;
}

#define ttyname_r ios_ttyname_r

#define tcsendbreak ios_tcsendbreak
#define tcdrain ios_tcdrain
#define tcflush ios_tcflush
#define tcflow ios_tcflow

#define tcgetattr ios_tcgetattr
#define tcsetattr ios_tcsetattr

#define tcgetwinsize ios_tcgetwinsize
#define tcsetwinsize ios_tcsetwinsize

#define ioctl(fd, request, ...) ios_ioctl((fd), (request), ##__VA_ARGS__)
#define fcntl(fd, request, ...) ios_fcntl((fd), (request), ##__VA_ARGS__)

#define dup ios_dup
#define dup2 ios_dup2
#define close ios_close

#define isatty(fd) (ios_tcgetwinsize(fd, NULL) == 0)

#endif
