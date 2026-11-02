//
//  LogLineParser+Servers.swift
//  LogReader
//
//  Web and data servers' logs: access logs, nginx's error log, Go's log package, Redis.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLineParser {
    /// The Common and Combined Log Formats (Apache, nginx): `192.0.2.1 - user [01/Oct/2026:00:00:00 +0000]
    /// "GET / HTTP/1.1" 200 1234 "referer" "agent"`, a virtual host in front allowed. 5xx is an error, 4xx a
    /// warning, anything else info; the message is the request onwards.
    static func accessLog(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        // Up to four fields before the time: [vhost] client ident user.
        var fields = 0
        while fields < 5, c.peek() != UInt8(ascii: "[") {
            guard !c.word().isEmpty, c.expect(" ") else { return nil }
            fields += 1
        }
        guard (3...4).contains(fields), c.expect("["), let time = LogTimeParser.commonLog(&c), c.expect("] \"") else { return nil }
        let request = c.i - 1
        guard c.until("\"") != nil, c.expect(" "), let status = c.digits(3) else { return nil }
        let level: LogLevel = status >= 500 ? .error : status >= 400 ? .warning : .info
        return LogLineHead(format: .accessLog, level: level, time: time, messageStart: request - line.startIndex)
    }

    /// `2026/10/01 00:00:00 [error] 123#0: *1 message` (nginx's error log), or the same date with no level
    /// (Go's log package: `2026/10/01 00:00:00 message`).
    static func slashDated(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.slashDate(&c), c.expect(" ") else { return nil }
        var t = c
        if t.expect("["), let word = t.until("]"), let level = level(word, anyCase: true) {
            t.skipSpaces()
            return LogLineHead(format: .nginxError, level: level, time: time, messageStart: t.offset)
        }
        return LogLineHead(format: .goLog, time: time, messageStart: c.offset)
    }

    /// `123:M 01 Oct 2026 00:00:00.123 * message`: the role letter after the pid, then the mark is the level
    /// (`.` and `-` debug, `*` notice, `#` warning).
    static func redis(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.someDigits() != nil, c.expect(":"), let role = c.peek(), "XCSM".utf8.contains(role) else { return nil }
        c.i += 1
        guard c.expect(" "), let time = LogTimeParser.dayMonthYearSpaced(&c), c.expect(" "), let mark = c.peek() else { return nil }
        let level: LogLevel
        switch mark {
        case UInt8(ascii: "."), UInt8(ascii: "-"): level = .debug
        case UInt8(ascii: "*"): level = .notice
        case UInt8(ascii: "#"): level = .warning
        default: return nil
        }
        c.i += 1
        c.skipSpaces()
        return LogLineHead(format: .redis, level: level, time: time, messageStart: c.offset)
    }
}
