import Foundation
import Darwin

let queue = DispatchQueue.global(qos: .userInitiated)

// Each termios and winsize is associated to a name
nonisolated(unsafe) var _termios = [String:termios]()
nonisolated(unsafe) var _winsize = [String:winsize]()

// And each fake pty is associated to that same name
nonisolated(unsafe) var ptys = [String:[Int32]]()

// Child PTYs (map each child fd to its parent's name)
nonisolated(unsafe) var childPtys = [Int32:String]()

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

// MARK: - Swift API

enum NoTTYError: Error {

    case fd(Int32)

    case name(String)
}

public func ptyName(fd: Int32) throws -> String {
    if let name = ptys.filter({ $0.value.contains(fd) }).first?.key {
        return name
    } else if let name = childPtys[fd] {
        return name
    } else {
        throw NoTTYError.fd(fd)
    }
}

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

public func registerPTY(parentName: String, fd: Int32) throws {

    if ptys[parentName] == nil {
        throw NoTTYError.name(parentName)
    }

    childPtys[fd] = parentName
}

public func registerPTY(parent: Int32, fd: Int32) throws {
    let name = try ptyName(fd: parent)
    try registerPTY(parentName: name, fd: fd)
}

public func clearPTY(name: String) {
    ios_clear_pty("\(name)")
}

public func isATTY(_ fd: Int32) -> Bool {
    (try? ptyName(fd: fd)) != nil
}

public func getTermios(fd: Int32) throws -> termios {
    var term = defaultTermios
    if ios_tcgetattr(fd, &term) == 0 {
        return term
    } else {
        throw NoTTYError.fd(fd)
    }
}

public func getTermios(ptyName: String) throws -> termios {
    guard let fd = ptys[ptyName]?.first else {
        throw NoTTYError.name(ptyName)
    }
    return try getTermios(fd: fd)
}

public func setTermios(_ termios: termios, fd: Int32) throws {
    var _termios = termios
    if ios_tcsetattr(fd, TCSANOW, &_termios) != 0 {
        throw NoTTYError.fd(fd)
    }
}

public func setTermios(_ termios: termios, ptyName: String) throws {
    guard let fd = ptys[ptyName]?.first else {
        throw NoTTYError.name(ptyName)
    }
    try setTermios(termios, fd: fd)
}

public func getWinSize(fd: Int32) throws -> winsize {
    var win = winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
    if ios_tcgetwinsize(fd, &win) == 0 {
        return win
    } else {
        throw NoTTYError.fd(fd)
    }
}

public func getWinSize(ptyName: String) throws -> winsize {
    guard let fd = ptys[ptyName]?.first else {
        throw NoTTYError.name(ptyName)
    }
    return try getWinSize(fd: fd)
}

public func setWinSize(_ winsize: winsize, fd: Int32) throws {
    var _winsize = winsize
    if ios_tcsetwinsize(fd, TCSANOW, &_winsize) != 0 {
        throw NoTTYError.fd(fd)
    }
}

public func setWinSize(_ winsize: winsize, ptyName: String) throws {
    guard let fd = ptys[ptyName]?.first else {
        throw NoTTYError.name(ptyName)
    }
    return try setWinSize(winsize, fd: fd)
}

// MARK: - C API

@_cdecl("ios_register_pty")
public func ios_register_pty(_ name: UnsafePointer<CChar>, termp: UnsafeMutablePointer<termios>?, winp: UnsafeMutablePointer<winsize>?, stdin: Int32, stdout: Int32, stderr: Int32) {
    let _name = String(cString: name)
    queue.sync {
        ptys[_name] = [stdin, stdout, stderr]
        _termios[_name] = termp?.pointee
        _winsize[_name] = winp?.pointee
    }
}

@_cdecl("ios_register_child_pty")
public func ios_register_child_pty(_ parentFd: Int32, childFd: Int32) -> Int32 {
    guard let name = try? ptyName(fd: parentFd) else {
        return 1
    }
    try? registerPTY(parentName: name, fd: childFd)
    return 0
}

@_cdecl("ios_clear_pty")
public func ios_clear_pty(_ name: UnsafePointer<CChar>) {
    let _name = String(cString: name)
    queue.sync {
        ptys[_name] = nil
        
        let keysToRemove = childPtys.filter { $0.value == _name }.map { $0.key }
        for key in keysToRemove {
            childPtys.removeValue(forKey: key)
        }
            
        _termios[_name] = nil
        _winsize[_name] = nil
    }
}

// MARK: - ioctl

@_cdecl("ios_winsize_ioctl")
public func ios_winsize_ioctl(_ fd: Int32, _ request: UInt, _ arg: UnsafeMutableRawPointer?) -> Int32 {

    switch request {
    case TIOCGWINSZ:
        do {
            var ws = try getWinSize(fd: fd)

            guard let dest = arg else {
                errno = EINVAL
                return -1
            }
            dest.copyMemory(from: &ws, byteCount: MemoryLayout<winsize>.size)
        } catch {
            errno = ENOTTY
            return -1
        }
        return 0
    case TIOCSWINSZ:
        guard let src = arg else {
            errno = EINVAL
            return -1
        }

        do {
            let ws = src.assumingMemoryBound(to: winsize.self)
            try setWinSize(ws.pointee, fd: fd)
            return 0
        } catch {
            errno = ENOTTY
            return -1
        }
    default:
        return -1
    }
}

// MARK: - dup

@_cdecl("ios_dup")
public func ios_dup(_ fd: Int32) -> Int32 {
    let duped = dup(fd)
    if isATTY(fd) {
        ios_register_child_pty(fd, duped)
    }
    return duped
}

@_cdecl("ios_dup2")
public func ios_dup2(_ fd: Int32, _ newfd: Int32) -> Int32 {
    let duped = dup2(fd, newfd)
    if isATTY(fd) {
        ios_register_child_pty(fd, duped)
    }
    return duped
}

// MARK: - close

@_cdecl("ios_close")
public func ios_close(_ fd: Int32) -> Int32 {
    if isATTY(fd), let name = try? ptyName(fd: fd), childPtys[fd] == nil {
        ios_clear_pty(name)
    }
    return close(fd)
}

// MARK: - termios

@_cdecl("ios_ttyname_r")
public func ios_ttyname_r( _ fd: Int32, _ buf: UnsafeMutablePointer<CChar>!, _ len: Int) -> Int32 {
    guard let buf = buf, len > 0 else {
        return EINVAL
    }

    guard let name = try? ptyName(fd: fd) else {
        return ENOTTY
    }

    return name.withCString { cstr in
        let needed = strlen(cstr) + 1

        if needed > len {
            return ERANGE
        }

        memcpy(buf, cstr, needed)
        return 0
    }
}

@_cdecl("ios_tcsendbreak")
public func ios_tcsendbreak(_ fd: Int32, _ duration: Int32) -> Int32 {
    guard (try? ptyName(fd: fd)) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcdrain")
public func ios_tcdrain(_ fd: Int32) -> Int32 {
    guard (try? ptyName(fd: fd)) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcflush")
public func ios_tcflush(_ fd: Int32, _ queue_selector: Int32) -> Int32 {
    guard (try? ptyName(fd: fd)) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcflow")
public func ios_tcflow(_ fd: Int32, _ action: Int32) -> Int32 {
    guard (try? ptyName(fd: fd)) != nil else {
        errno = ENOTTY
        return -1
    }
    return 0
}

@_cdecl("ios_tcgetattr")
public func ios_tcgetattr(_ fd: Int32, _ termios: UnsafeMutablePointer<termios>?) -> Int32 {
    guard let name = try? ptyName(fd: fd) else {
        errno = ENOTTY
        return -1
    }
    termios?.pointee = _termios[name] ?? defaultTermios
    return 0
}

@_cdecl("ios_tcsetattr")
public func ios_tcsetattr(_ fd: Int32, _ optional_actions: Int32, _ termios_p: UnsafeMutablePointer<termios>?) -> Int32 {

    guard let name = try? ptyName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    queue.sync {
        _termios[name] = termios_p?.pointee
    }
    return 0
}

@_cdecl("ios_tcgetwinsize")
public func ios_tcgetwinsize(_ fd: Int32, _ winsize_p: UnsafeMutablePointer<winsize>?) -> Int32 {

    guard let name = try? ptyName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    winsize_p?.pointee = _winsize[name] ?? winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
    return 0
}

@_cdecl("ios_tcsetwinsize")
public func ios_tcsetwinsize(_ fd: Int32, _ optional_actions: Int32, _ winsize_p: UnsafeMutablePointer<winsize>?) -> Int32 {

    guard let name = try? ptyName(fd: fd) else {
        errno = ENOTTY
        return -1
    }

    queue.sync {
        _winsize[name] = winsize_p?.pointee
    }
    return 0
}

