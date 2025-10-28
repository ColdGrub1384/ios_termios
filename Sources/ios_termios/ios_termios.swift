import Foundation

let queue = DispatchQueue.global(qos: .userInitiated)

// Each termios and winsize is associated to a name, which is any type really
nonisolated(unsafe) var _termios = [UnsafePointer<CChar>:termios]()
nonisolated(unsafe) var _winsize = [UnsafePointer<CChar>:winsize]()

// And each fake pty is associated to that same name
nonisolated(unsafe) var ptys = [UnsafePointer<CChar>:[Int32]]()

// Default termios values
var defaultTermios: termios {
    var cc = [cc_t](repeating: 0, count: 20)
    cc[Int(VINTR)]  = 3
    cc[Int(VEOF)]   = 4
    cc[Int(VERASE)] = 127
    cc[Int(VKILL)]  = 21
    cc[Int(VMIN)]   = 1
    cc[Int(VTIME)]  = 0
    return termios(
        c_iflag: tcflag_t(BRKINT | ICRNL | IXON | IXANY | IMAXBEL),
        c_oflag: tcflag_t(OPOST | ONLCR),
        c_cflag: tcflag_t(CREAD | CS8 | HUPCL),
        c_lflag: tcflag_t(ISIG | ICANON | ECHO | ECHOE | ECHOK),
        c_cc: (
            cc[0], cc[1], cc[2], cc[3], cc[4],
            cc[5], cc[6], cc[7], cc[8], cc[9],
            cc[10], cc[11], cc[12], cc[13], cc[14],
            cc[15], cc[16], cc[17], cc[18], cc[19]
        ),
        c_ispeed: 9600,
        c_ospeed: 9600
    )
}

func getName(fd: Int32) -> UnsafePointer<CChar>? {
    ptys.filter({ $0.value.contains(fd) }).first?.key
}

// MARK: - Swift API

public func registerPTY(name: String, termios: termios?, winsize: winsize?, stdin: Int32, stdout: Int32, stderr: Int32) {

    var _termp: UnsafeMutablePointer<termios>?
    var _winp: UnsafeMutablePointer<winsize>?

    if var termios {
        _termp = .init(&termios)
    }

    if var winsize {
        _winp = .init(&winsize)
    }

    ios_register_pty("\(name)", termp: _termp, winp: _winp, stdin: stdin, stdout: stdout, stderr: stderr)
}

public func clearPTY(name: String) {
    ios_clear_pty("\(name)")
}

public func getTermios(ptyName: String) -> termios? {
    guard let fd = ptys.first(where: { strcmp($0.key, "\(ptyName)") == 0 })?.value.first else {
        return nil
    }

    var term: termios!
    _ = ios_tcgetattr(fd, &term)
    return term
}

public func setTermios(ptyName: String, termios: termios) {
    guard let fd = ptys.first(where: { strcmp($0.key, "\(ptyName)") == 0 })?.value.first else {
        return
    }

    var _termios = termios
    _ = ios_tcsetattr(fd, TCSANOW, &_termios)
}

public func getWinSize(ptyName: String) -> winsize? {
    guard let fd = ptys.first(where: { strcmp($0.key, "\(ptyName)") == 0 })?.value.first else {
        return nil
    }

    var win: winsize!
    _ = ios_tcgetwinsize(fd, &win)
    return win
}

public func setWinSize(ptyName: String, winsize: winsize) {
    guard let fd = ptys.first(where: { strcmp($0.key, "\(ptyName)") == 0 })?.value.first else {
        return
    }

    var _winsize = winsize
    _ = ios_tcsetwinsize(fd, TCSANOW, &_winsize)
}

// MARK: - API

@_cdecl("ios_register_pty")
public func ios_register_pty(_ name: UnsafePointer<CChar>, termp: UnsafeMutablePointer<termios>?, winp: UnsafeMutablePointer<winsize>?, stdin: Int32, stdout: Int32, stderr: Int32) {
    queue.sync {
        ptys[name] = [stdin, stdout, stderr]
        _termios[name] = termp?.pointee
        _winsize[name] = winp?.pointee
    }
}

@_cdecl("ios_clear_pty")
public func ios_clear_pty(_ name: UnsafePointer<CChar>) {
    guard let _name = ptys.keys.first(where: { strcmp($0, name) == 0 }) else {
        return
    }
    queue.sync {
        ptys[_name] = nil
        _termios[_name] = nil
        _winsize[_name] = nil
    }
}

// MARK: - Wrappers

@_cdecl("ios_tcsendbreak")
public func ios_tcsendbreak(_ fd: Int32, _ duration: Int32) -> Int32 {
    guard getName(fd: fd) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcdrain")
public func ios_tcdrain(_ fd: Int32) -> Int32 {
    guard getName(fd: fd) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcflush")
public func ios_tcflush(_ fd: Int32, _ queue_selector: Int32) -> Int32 {
    guard getName(fd: fd) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcflow")
public func ios_tcflow(_ fd: Int32, _ action: Int32) -> Int32 {
    guard getName(fd: fd) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcgetattr")
public func ios_tcgetattr(_ fd: Int32, _ termios: UnsafeMutablePointer<termios>!) -> Int32 {

    guard let name = getName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    termios.pointee = _termios[name] ?? defaultTermios
    return 0
}

@_cdecl("ios_tcsetattr")
public func ios_tcsetattr(_ fd: Int32, _ optional_actions: Int32, _ termios_p: UnsafeMutablePointer<termios>!) -> Int32 {

    guard let name = getName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    queue.sync {
        _termios[name] = termios_p.pointee
    }
    return 0
}

@_cdecl("ios_tcgetwinsize")
public func ios_tcgetwinsize(_ fd: Int32, _ winsize_p: UnsafeMutablePointer<winsize>!) -> Int32 {

    guard let name = getName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    winsize_p.pointee = _winsize[name] ?? winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
    return 0
}

@_cdecl("ios_tcsetwinsize")
public func ios_tcsetwinsize(_ fd: Int32, _ optional_actions: Int32, _ winsize_p: UnsafeMutablePointer<winsize>!) -> Int32 {

    guard let name = getName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    queue.sync {
        _winsize[name] = winsize_p.pointee
    }
    return 0
}
