# ios_termios

`ios_termios` is a wrapper of `tcgetattr`, `tcsetattr`, `tcgetwinsize` and `tcsetwinsize` for iOS. It also wraps `ioctl` to work with `TIOCGWINSZ` and `TIOCSWINSZ` Because iOS doesn't let processes open pseudo terminals, this library manage their own. I'm trying to get `libedit` and the Python `readline` library to work with this wrapper.

The client is still responsible of opening the pipes. This library will not open fake pseudo terminals for you but instead you register your file descriptors with the `ios_register_pty` or `registerPTY` functions. For duplicated file descriptors, you can register a child file descriptor that will hold the same terminal state of its parent with one of the Swift variants of `registerPTY` or `ios_register_child_pty`. Children file descriptors are cleared when their parent is cleared.

## Usage

To use this library, you must link this Swift Package or the framework compiled from the Xcode project to your app. This will make the necessary symbols available to the libraries that you want to compile.

To compile a library using `termios`, you must include the `ios_termios.h` file either alongside `termios.h` and `sys/ioctl.h` or in place of these headers and link the framework or the Swift Package. This will replace calls to `termios` functions and `ioctl` with the appropriate wrapper.

Before using this library, you must call `ios_register_pty` with an unique identifier, then optionally initial `termios` and `winsize` structures, followed by the file descriptors corresponding to the `stdin`, `stdout` and `stderr` streams managed by your terminal. If you don't do that, `termios` will raise `ENOTTY` and return `-1`.

After the program finished using the pty, clear its attributes from memory with the `ios_clear_pty` function.

## API

This library is written in Swift and exposed to C. There are equivalent Swift functions that you can use in the frontend. They accept both file descriptors and names plus they throw a `NoTTYError` error instead of returning -1.

Throwable Swift functions throw a `NoTTYError` when the passed PTY name or file descriptor is not valid.

### Swift interface

```swift
import ios_termios

enum NoTTYError: Error {
    case fd(Int32)
    case name(String)
}

func registerPTY(name: String, termios: termios?, winsize: winsize?, stdin: Int32, stdout: Int32, stderr: Int32)
func registerPTY(parentName: String, fd: Int32) throws
func registerPTY(parent: Int32, fd: Int32) throws

func clearPTY(name: String)
func ptyName(fd: Int32) throws -> String

func isATTY(_: Int32) -> Bool

func getTermios(fd: Int32) throws -> termios
func getTermios(ptyName: String) throws -> termios

func setTermios(_: termios, fd: Int32) throws
func setTermios(_: termios, ptyName: String) throws

func getWinSize(fd: Int32) throws -> winsize
func getWinSize(ptyName: String) throws -> winsize

func setWinSize(_: winsize, fd: Int32) throws
func setWinSize(_: winsize, ptyName: String) throws
```

### C functions

```c
#include "ios_termios.h"

void ios_register_pty(const char *name, struct termios *termp, struct winsize *winp, int stdin, int stdout, int stderr);
int ios_register_child_pty(int parent_fd, int child_fd);
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
#include "ios_termios.h"

#define ttyname ios_ttyname

#define tcgetattr ios_tcgetattr
#define tcsetattr ios_tcsetattr

#define tcgetwinsize ios_tcgetwinsize
#define tcsetwinsize ios_tcsetwinsize

#define ioctl(fd, request, ...) ios_ioctl((fd), (request), ##__VA_ARGS__)

#define isatty(fd) (ios_tcgetwinsize(fd, NULL) == 0)

// Not implemented
#define tcsendbreak ios_tcsendbreak
#define tcdrain ios_tcdrain
#define tcflush ios_tcflush
#define tcflow ios_tcflow
```
