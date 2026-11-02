//
//  LogLineParser+Syslog.swift
//  LogReader
//
//  syslog's shapes: BSD syslog, journald's short forms, syslog after an ISO time, and macOS's `log show`.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLineParser {
    /// `Oct  1 00:00:00 web-01 sshd[123]: message` (RFC 3164, journald's `short`): the program, without its pid,
    /// is the component. syslog lines carry no level, unless the message is logfmt with one (`at=error`).
    static func bsdSyslog(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.syslog(&c, ref), c.expect(" ") else { return nil }
        return syslogTail(&c, time: time, format: .syslog, line: line)
    }

    /// An ISO time, then `host program[pid]: ` or `program[pid]: ` (journald's `short-iso`, `log show --style
    /// syslog`, a Heroku drain's `app[web.1]:`). A level word where the host would be makes it a plain line instead.
    static func isoSyslog(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.iso(&c), c.skipSpaces() > 0 else { return nil }
        return syslogTail(&c, time: time, format: .syslog, line: line)
    }

    /// After the time: an optional host, then the program and its `: `.
    private static func syslogTail(_ c: inout ByteCursor, time: LogInstant, format: LogFormat, line: ArraySlice<UInt8>) -> LogLineHead? {
        var t = c
        let first = t.word()
        guard !first.isEmpty, first.first != UInt8(ascii: "["), level(first, anyCase: false) == nil else { return nil }
        var program = first
        if first.last != UInt8(ascii: ":") {
            t.skipSpaces()
            program = t.word()
            guard program.last == UInt8(ascii: ":"), level(program, anyCase: false) == nil,
                !continuationWords.contains(program.text)
            else { return nil }
        }
        let name = programName(program.dropLast())
        guard let name, name.contains(where: { !$0.isNumber }) else { return nil }
        t.skipSpaces()
        c = t
        var head = LogLineHead(format: format, time: time, component: name, messageStart: c.offset)
        if let pairs = LogfmtPairs(c.rest), let at = pairs["at"] ?? pairs["level"], let level = LogLevel.named(at) {
            head.level = level  // Heroku's router: `at=info method=GET …`
        }
        return head
    }

    /// `sshd[123]` → `sshd`; `heroku[router]` → `heroku`; a program with no pid as it is.
    private static func programName(_ token: ArraySlice<UInt8>) -> String? {
        let name = token.firstIndex(of: UInt8(ascii: "[")).map { token[token.startIndex..<$0] } ?? token
        return component(name)
    }

    /// macOS's `log show` (its default style): `2026-10-01 00:00:00.123456+0100 0x1a2b  Default  0x0  123  0
    /// process: message`. The type is the level (Default and Info are info, Debug debug, Error error, Fault fatal).
    static func appleUnified(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.iso(&c), c.skipSpaces() > 0, c.expect("0x") else { return nil }
        _ = c.word()  // thread
        c.skipSpaces()
        let type = c.word().text
        guard let level = Self.appleTypes[type] else { return nil }
        c.skipSpaces()
        guard c.expect("0x") else { return nil }
        _ = c.word()  // activity
        c.skipSpaces()
        guard c.someDigits() != nil else { return nil }  // pid
        c.skipSpaces()
        guard c.someDigits() != nil else { return nil }  // ttl
        c.skipSpaces()
        let start = c.i
        guard c.until(":") != nil else { return nil }
        let process = line[start..<(c.i - 1)]
        c.skipSpaces()
        return LogLineHead(format: .appleUnified, level: level, time: time, component: component(process), messageStart: c.offset)
    }

    private static let appleTypes: [String: LogLevel] = [
        "Default": .info, "Info": .info, "Debug": .debug, "Error": .error, "Fault": .fatal, "Activity": .info,
    ]
}
