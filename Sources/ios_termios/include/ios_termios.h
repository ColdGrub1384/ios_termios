#ifndef ios_termios_h
#define ios_termios_h

#include <termios.h>

extern void ios_register_pty(void *name, struct termios *termp, struct winsize *winp, int stdin, int stdout, int stderr);
extern void ios_clear_pty(void *name);

extern int ios_tcgetwinsize(int fd, struct winsize *w);
extern int ios_tcsetwinsize(int fd, const struct winsize *w);

extern int ios_tcgetattr(int fd, struct termios *termios_p);
extern int ios_tcsetattr(int fd, int optional_actions, const struct termios *termios_p);

extern int ios_tcsendbreak(int fd, int duration);
extern int ios_tcdrain(int fd);
extern int ios_tcflush(int fd, int queue_selector);
extern int ios_tcflow(int fd, int action);

#define tcsendbreak ios_tcsendbreak
#define tcdrain ios_tcdrain
#define tcflush ios_tcflush
#define tcflow ios_tcflow

#define tcgetattr ios_tcgetattr
#define tcsetattr ios_tcsetattr

#define tcgetwinsize ios_tcgetwinsize
#define tcsetwinsize ios_tcsetwinsize

#endif
