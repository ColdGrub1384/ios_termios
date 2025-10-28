# ios_termios

`ios_termios` is a wrapper of `tcgetattr`, `tcsetattr`, `tcgetwinsize` and `tcsetwinsize` for iOS. Because iOS doesn't let processes open pseudo terminals, this library manage their own. I'm trying to get `libedit` and the Python `readline` library to work with this wrapper.

The client is still responsible of opening the pipes. This library will not open fake pseudo terminals for you but instead you register your file descriptors with the `ios_register_pty` function.

## Usage

To use this library, you must link this Swift Package or the framework compiled from the Xcode project to your app. This will make the necessary symbols available to the libraries that you want to compile.

To compile a library using `termios`, you must include the `ios_termios.h` file either alongside `termios.h` or in place of `termios.h`. This will replace calls to termios functions with the appropriate wrapper.

Before using this library, you must call `ios_register_pty` with an unique identifier, then optionally initial `termios` and `winsize` structures, followed by the file descriptors corresponding to the `stdin`, `stdout` and `stderr` streams managed by your terminal. If you don't do that, `termios` will raise `ENOTTY` and return `-1`.

After the program finished using the pty, clear its attributes from memory with the `ios_clear_pty` function.

## API

This library is written in Swift and exposed functions to C. There are equivalent functions more suitable for Swift that can be used on the frontend.

### Swift functions

```swift

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
```

Termios wrapper functions:

```c
int ios_tcgetwinsize(int fd, struct winsize *w);
int ios_tcsetwinsize(int fd, const struct winsize *w);

int ios_tcgetattr(int fd, struct termios *termios_p);
int ios_tcsetattr(int fd, int optional_actions, const struct termios *termios_p);
```

And functions that do nothing and return 0:

```c
int ios_tcsendbreak(int fd, int duration);
int ios_tcdrain(int fd);
int ios_tcflush(int fd, int queue_selector);
int ios_tcflow(int fd, int action);
```
