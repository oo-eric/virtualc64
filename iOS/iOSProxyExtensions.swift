// -----------------------------------------------------------------------------
// This file is part of VirtualC64
//
// Copyright (C) Dirk W. Hoffmann. www.dirkwhoffmann.de
// This FILE is dual-licensed. You are free to choose between:
//
//     - The GNU General Public License v3 (or any later version)
//     - The Mozilla Public License v2
//
// SPDX-License-Identifier: GPL-3.0-or-later OR MPL-2.0
// -----------------------------------------------------------------------------

// Minimal proxy extensions for iOS — only what CynthcartApp needs.
// The macOS version (ProxyExtensions.swift) has NSImage/NSAlert dependencies
// that don't compile on iOS.

//
// Logging / Debugging
//

public func log(_ enable: Int, _ msg: String = "",
                path: String = #file, function: String = #function, line: Int = #line) {

    if enable > 0 {
        if let file = URL(string: path)?.deletingPathExtension().lastPathComponent {
            if msg == "" {
                print("\(file).\(line)::\(function)")
            } else {
                print("\(file).\(line)::\(function): \(msg)")
            }
        }
    }
}

public func debug(_ enable: Int, _ msg: String = "",
                  path: String = #file, function: String = #function, line: Int = #line) {

    if !releaseBuild { log(enable, msg, path: path, function: function, line: line) }
}

public func warn(_ msg: String = "",
                 path: String = #file, function: String = #function, line: Int = #line) {

    log(1, "Warning: " + msg, path: path, function: function, line: line)
}

//
// Errors
//

final class AppError: Error {

    let errorCode: Fault
    let what: String

    init(_ exception: ExceptionWrapper) {
        self.errorCode = exception.fault
        self.what = exception.what
    }

    init(_ errorCode: vc64.Fault, _ what: String = "") {
        self.errorCode = errorCode
        self.what = what
    }
}

//
// Factory extensions
//

@MainActor
extension MediaFileProxy {

    static func make(with url: URL) throws -> Self {
        let exc = ExceptionWrapper()
        let obj = make(withFile: url.path, exception: exc)
        if exc.fault != .OK { throw AppError(exc) }
        return obj!
    }
}

@MainActor
extension FileSystemProxy {

    static func make(with file: MediaFileProxy) throws -> Self {
        let exc = ExceptionWrapper()
        let obj = make(withMediaFile: file, exception: exc)
        if exc.fault != .OK { throw AppError(exc) }
        return obj!
    }
}

//
// Emulator exception-throwing wrappers
//

@MainActor
extension EmulatorProxy {

    func launch() throws {
        let exception = ExceptionWrapper()
        launch(exception)
        if exception.fault != .OK { throw AppError(exception) }
    }

    func launch(_ listener: UnsafeRawPointer,
                _ callback: @escaping @convention(c) (UnsafeRawPointer?, Message) -> Void) throws {
        let exception = ExceptionWrapper()
        launch(listener, function: callback, exception: exception)
        if exception.fault != .OK { throw AppError(exception) }
    }

    func powerOn() throws {
        let exception = ExceptionWrapper()
        power(on: exception)
        if exception.fault != .OK { throw AppError(exception) }
    }

    func run() throws {
        let exception = ExceptionWrapper()
        run(exception)
        if exception.fault != .OK { throw AppError(exception) }
    }

    func flash(_ proxy: FileSystemProxy, item: Int) throws {
        let exception = ExceptionWrapper()
        flash(proxy, item: item, exception: exception)
        if exception.fault != .OK { throw AppError(exception) }
    }
}

//
// Build settings
//

struct BuildSettings {
    static let msgCallback = true
}

//
// Debug settings
//

public extension Int {
    static let audio        = 0
    static let config       = 0
    static let defaults     = 0
    static let dragndrop    = 0
    static let events       = 0
    static let exec         = 0
    static let hid          = 0
    static let lifetime     = 0
    static let media        = 0
    static let metal        = 0
    static let vsync        = 0
    static let shutdown     = 0
}
