# ios_termios

`ios_termios` is a wrapper of `tcgetattr`, `tcsetattr`, `tcgetwinsize` and `tcsetwinsize` for iOS. It also wraps `ioctl` to work with `TIOCGWINSZ` and `TIOCSWINSZ` Because iOS doesn't let processes open pseudo terminals, this library manage their own. I'm trying to get `libedit` and the Python `readline` library to work with this wrapper.

The client is still responsible of opening the pipes. This library will not open fake pseudo terminals for you but instead you register your file descriptors with the `ios_register_pty` function.

## Usage

To use this library, you must link this Swift Package or the framework compiled from the Xcode project to your app. This will make the necessary symbols available to the libraries that you want to compile.

To compile a library using `termios`, you must include the `ios_termios.h` file either alongside `termios.h` and `sys/ioctl.h` or in place of these headers and link the framework or the Swift Package. This will replace calls to `termios` functions and `ioctl` with the appropriate wrapper.

Before using this library, you must call `ios_register_pty` with an unique identifier, then optionally initial `termios` and `winsize` structures, followed by the file descriptors corresponding to the `stdin`, `stdout` and `stderr` streams managed by your terminal. If you don't do that, `termios` will raise `ENOTTY` and return `-1`.

After the program finished using the pty, clear its attributes from memory with the `ios_clear_pty` function.

## API

This library is written in Swift and exposed to C. There are equivalent Swift functions that you can use in the frontend.

### Swift functions

```swift
import ios_termios

public func registerPTY(name: String, termios: termios?, winsize: winsize?, stdin: Int32, stdout: Int32, stderr: Int32)
public func clearPTY(name: String)

public func getTermios(ptyName: String) -> termios?
public func setTermios(ptyName: String, termios: termios)

public func getWinSize(ptyName: String) -> winsize?
public func setWinSize(ptyName: String, winsize: winsize)
```

### C functions

```c
void ios_register_pty(const char *name, struct termios *termp, struct winsize *winp, int stdin, int stdout, int stderr);
void ios_clear_pty(const char *name);

int ios_tcgetwinsize(int fd, struct winsize *w);
int ios_tcsetwinsize(int fd, const struct winsize *w);

int ios_tcgetattr(int fd, struct termios *termios_p);
int ios_tcsetattr(int fd, int optional_actions, const struct termios *termios_p);

int ios_tcsendbreak(int fd, int duration);
int ios_tcdrain(int fd);
int ios_tcflush(int fd, int queue_selector);
int ios_tcflow(int fd, int action);

int ios_winsize_ioctl(int fd, int request, void *arg);
static inline int ios_ioctl(int fd, unsigned int request, ...);
```

### Replacement macros

```c
#define tcsendbreak ios_tcsendbreak
#define tcdrain ios_tcdrain
#define tcflush ios_tcflush
#define tcflow ios_tcflow

#define tcgetattr ios_tcgetattr
#define tcsetattr ios_tcsetattr

#define tcgetwinsize ios_tcgetwinsize
#define tcsetwinsize ios_tcsetwinsize

#define ioctl(fd, request, ...) ios_ioctl((fd), (request), ##__VA_ARGS__)

#define isatty(fd) (ios_tcgetwinsize(fd, NULL) == 0)
```
