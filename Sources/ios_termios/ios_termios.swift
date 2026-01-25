import Foundation
import Darwin

// SERIAL queue used as a mutex for all shared state
private let ptyQueue = DispatchQueue(label: "pty.state.lock")

// MARK: - Shared State (ONLY touch inside ptyQueue)

// Each termios and winsize is associated to a name
nonisolated(unsafe) var _termios = [String:termios]()
nonisolated(unsafe) var _winsize = [String:winsize]()

// And each fake pty is associated to that same name
nonisolated(unsafe) var ptys = [String:[Int32]]()

// Child PTYs (map each child fd to its parent's name)
nonisolated(unsafe) var childPtys = [Int32:String]()

// MARK: - Defaults

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

// MARK: - Errors

enum NoTTYError: Error {
    case fd(Int32)
    case name(String)
}

// MARK: - Internal Helpers (ASSUME ptyQueue HELD)

private func _ptyName_unlocked(fd: Int32) throws -> String {
    if let name = ptys.first(where: { $0.value.contains(fd) })?.key {
        return name
    } else if let name = childPtys[fd] {
        return name
    } else {
        throw NoTTYError.fd(fd)
    }
}

// MARK: - Swift API (thread-safe)

public func ptyName(fd: Int32) throws -> String {
    try ptyQueue.sync {
        try _ptyName_unlocked(fd: fd)
    }
}

public func registerPTY(name: String, termios: termios?, winsize: winsize?, stdin: Int32, stdout: Int32, stderr: Int32) {
    name.withCString { cname in
        var t = termios
        var w = winsize
        ios_register_pty(cname, termp: t != nil ? &t! : nil, winp: w != nil ? &w! : nil, stdin: stdin, stdout: stdout, stderr: stderr)
    }
}

public func registerPTY(parentName: String, fd: Int32) throws {
    try ptyQueue.sync {
        guard ptys[parentName] != nil else {
            throw NoTTYError.name(parentName)
        }
        childPtys[fd] = parentName
    }
}

public func registerPTY(parent: Int32, fd: Int32) throws {
    let name = try ptyName(fd: parent)
    try registerPTY(parentName: name, fd: fd)
}

public func clearPTY(name: String) {
    name.withCString { ios_clear_pty($0) }
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
    let fd: Int32 = try ptyQueue.sync {
        guard let fd = ptys[ptyName]?.first else { throw NoTTYError.name(ptyName) }
        return fd
    }
    return try getTermios(fd: fd)
}

public func setTermios(_ termios: termios, fd: Int32) throws {
    var t = termios
    if ios_tcsetattr(fd, TCSANOW, &t) != 0 {
        throw NoTTYError.fd(fd)
    }
}

public func setTermios(_ termios: termios, ptyName: String) throws {
    let fd: Int32 = try ptyQueue.sync {
        guard let fd = ptys[ptyName]?.first else { throw NoTTYError.name(ptyName) }
        return fd
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
    let fd: Int32 = try ptyQueue.sync {
        guard let fd = ptys[ptyName]?.first else { throw NoTTYError.name(ptyName) }
        return fd
    }
    return try getWinSize(fd: fd)
}

public func setWinSize(_ winsize: winsize, fd: Int32) throws {
    var w = winsize
    if ios_tcsetwinsize(fd, TCSANOW, &w) != 0 {
        throw NoTTYError.fd(fd)
    }
}

public func setWinSize(_ winsize: winsize, ptyName: String) throws {
    let fd: Int32 = try ptyQueue.sync {
        guard let fd = ptys[ptyName]?.first else { throw NoTTYError.name(ptyName) }
        return fd
    }
    try setWinSize(winsize, fd: fd)
}

// MARK: - C API (ALL STATE ACCESS INSIDE ptyQueue)

@_cdecl("ios_register_pty")
public func ios_register_pty(_ name: UnsafePointer<CChar>, termp: UnsafeMutablePointer<termios>?, winp: UnsafeMutablePointer<winsize>?, stdin: Int32, stdout: Int32, stderr: Int32) {
    let n = String(cString: name)
    ptyQueue.sync {
        ptys[n] = [stdin, stdout, stderr]
        _termios[n] = termp?.pointee
        _winsize[n] = winp?.pointee
    }
}

@_cdecl("ios_register_child_pty")
public func ios_register_child_pty(_ parentFd: Int32, _ childFd: Int32) -> Int32 {
    ptyQueue.sync {
        guard let name = try? _ptyName_unlocked(fd: parentFd) else { return 1 }
        childPtys[childFd] = name
        return 0
    }
}

@_cdecl("ios_clear_pty")
public func ios_clear_pty(_ name: UnsafePointer<CChar>) {
    let n = String(cString: name)
    ptyQueue.sync {
        ptys[n] = nil
        _termios[n] = nil
        _winsize[n] = nil
        let keys = childPtys.filter { $0.value == n }.map { $0.key }
        for k in keys { childPtys.removeValue(forKey: k) }
    }
}

@_cdecl("ios_fds_from_ttyname_r")
public func ios_fds_from_ttyname_r(_ name: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<Int32>) -> Int32 {
    let n = String(cString: name)
    return ptyQueue.sync {
        guard let arr = ptys[n], arr.count == 3 else { return -1 }
        out[0] = arr[0]
        out[1] = arr[1]
        out[2] = arr[2]
        return 0
    }
}

// MARK: - ioctl

@_cdecl("ios_winsize_ioctl")
public func ios_winsize_ioctl(_ fd: Int32, _ request: UInt, _ arg: UnsafeMutableRawPointer?) -> Int32 {
    switch request {
    case TIOCGWINSZ:
        guard let dest = arg else { errno = EINVAL; return -1 }
        let ws: winsize
        do { ws = try getWinSize(fd: fd) } catch { errno = ENOTTY; return -1 }
        dest.copyMemory(from: [ws], byteCount: MemoryLayout<winsize>.size)
        return 0
    case TIOCSWINSZ:
        guard let src = arg else { errno = EINVAL; return -1 }
        let ws = src.assumingMemoryBound(to: winsize.self).pointee
        do { try setWinSize(ws, fd: fd); return 0 } catch { errno = ENOTTY; return -1 }
    default:
        return -1
    }
}

// MARK: - dup / close

@_cdecl("ios_dup")
public func ios_dup(_ fd: Int32) -> Int32 {
    let d = dup(fd)
    if d >= 0 && isATTY(fd) { _ = ios_register_child_pty(fd, d) }
    return d
}

@_cdecl("ios_dup2")
public func ios_dup2(_ fd: Int32, _ newfd: Int32) -> Int32 {
    let d = dup2(fd, newfd)
    if d >= 0 && isATTY(fd) { _ = ios_register_child_pty(fd, d) }
    return d
}

@_cdecl("ios_close")
public func ios_close(_ fd: Int32) -> Int32 {
    ptyQueue.sync { childPtys[fd] = nil }
    return close(fd)
}

// MARK: - termios

@_cdecl("ios_ttyname_r")
public func ios_ttyname_r(_ fd: Int32, _ buf: UnsafeMutablePointer<CChar>!, _ len: Int) -> Int32 {
    guard let buf = buf, len > 0 else { return EINVAL }
    let name: String
    do { name = try ptyName(fd: fd) } catch { return ENOTTY }
    return name.withCString { cstr in
        let needed = strlen(cstr) + 1
        if needed > len { return ERANGE }
        memcpy(buf, cstr, needed)
        return 0
    }
}

@_cdecl("ios_tcsendbreak")
public func ios_tcsendbreak(_ fd: Int32, _ duration: Int32) -> Int32 {
    guard isATTY(fd) else { errno = ENOTTY; return -1 }
    return 0
}

@_cdecl("ios_tcdrain")
public func ios_tcdrain(_ fd: Int32) -> Int32 {
    guard isATTY(fd) else { errno = ENOTTY; return -1 }
    return 0
}

@_cdecl("ios_tcflush")
public func ios_tcflush(_ fd: Int32, _ queue_selector: Int32) -> Int32 {
    guard isATTY(fd) else { errno = ENOTTY; return -1 }
    return 0
}

@_cdecl("ios_tcflow")
public func ios_tcflow(_ fd: Int32, _ action: Int32) -> Int32 {
    guard isATTY(fd) else { errno = ENOTTY; return -1 }
    return 0
}

@_cdecl("ios_tcgetattr")
public func ios_tcgetattr(_ fd: Int32, _ termios_p: UnsafeMutablePointer<termios>?) -> Int32 {
    let name: String
    do { name = try ptyName(fd: fd) } catch { errno = ENOTTY; return -1 }
    let t = ptyQueue.sync { _termios[name] ?? defaultTermios }
    termios_p?.pointee = t
    return 0
}

@_cdecl("ios_tcsetattr")
public func ios_tcsetattr(_ fd: Int32, _ optional_actions: Int32, _ termios_p: UnsafeMutablePointer<termios>?) -> Int32 {
    let name: String
    do { name = try ptyName(fd: fd) } catch { errno = ENOTTY; return -1 }
    ptyQueue.sync { _termios[name] = termios_p?.pointee }
    return 0
}

@_cdecl("ios_tcgetwinsize")
public func ios_tcgetwinsize(_ fd: Int32, _ winsize_p: UnsafeMutablePointer<winsize>?) -> Int32 {
    let name: String
    do { name = try ptyName(fd: fd) } catch { errno = ENOTTY; return -1 }
    let w = ptyQueue.sync { _winsize[name] ?? winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0) }
    winsize_p?.pointee = w
    return 0
}

@_cdecl("ios_tcsetwinsize")
public func ios_tcsetwinsize(_ fd: Int32, _ optional_actions: Int32, _ winsize_p: UnsafeMutablePointer<winsize>?) -> Int32 {
    let name: String
    do { name = try ptyName(fd: fd) } catch { errno = ENOTTY; return -1 }
    ptyQueue.sync { _winsize[name] = winsize_p?.pointee }
    return 0
}
