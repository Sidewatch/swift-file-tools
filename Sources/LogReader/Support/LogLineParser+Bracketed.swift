//
//  LogLineParser+Bracketed.swift
//  LogReader
//
//  The formats whose lines open with a bracket or a syslog priority.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLineParser {
    /// A line opening with `[`: Monolog / Laravel, PHP's error log, Apache's error log, or a bracketed plain
    /// header (Rust's env_logger: `[2026-10-01T00:00:00Z INFO  my_crate::module] …`).
    static func bracketed(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        monolog(line) ?? phpError(line) ?? apacheError(line) ?? bracketedPlain(line)
    }

    /// `[2026-10-01 00:00:00] production.ERROR: message {"context"} []`: the channel is the component.
    static func monolog(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.expect("["), let time = LogTimeParser.iso(&c), c.expect("] ") else { return nil }
        let start = c.i
        while let b = c.peek(), b != UInt8(ascii: "."), !ByteCursor.isSpace(b) { c.i += 1 }
        let channel = line[start..<c.i]
        guard !channel.isEmpty, c.expect(".") else { return nil }
        let levelStart = c.i
        while let b = c.peek(), ByteCursor.isLetter(b) { c.i += 1 }
        guard let level = level(line[levelStart..<c.i], anyCase: false), c.expect(":") else { return nil }
        c.skipSpaces()
        return LogLineHead(format: .monolog, level: level, time: time, component: channel.text, messageStart: c.offset)
    }

    /// `[01-Oct-2026 00:00:00 UTC] PHP Warning:  message`: PHP's own kinds as levels (a Fatal or Parse error stops the
    /// script: fatal, as Monolog has it; Deprecated a notice); a line `error_log()` wrote has no level.
    static func phpError(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.expect("["), let time = LogTimeParser.dayMonthYearDashed(&c) else { return nil }
        guard c.until("]") != nil else { return nil }  // a zone such as Europe/London is read as unzoned
        c.skipSpaces()
        var level: LogLevel?
        if c.expect("PHP ") {
            for (word, kind) in Self.phpKinds where c.expect(word) {
                level = kind
                break
            }
            c.skipSpaces()
        }
        return LogLineHead(format: .phpError, level: level, time: time, messageStart: c.offset)
    }

    private static let phpKinds: [(String, LogLevel)] = [
        ("Fatal error:", .fatal), ("Parse error:", .fatal), ("Recoverable fatal error:", .error), ("Catchable fatal error:", .error),
        ("Warning:", .warning), ("Notice:", .notice), ("Deprecated:", .notice), ("Strict Standards:", .notice),
    ]

    /// `[Wed Oct 01 00:00:00.123456 2026] [core:error] [pid 123] [client 192.0.2.1:1234] message`, and the older
    /// `[error]` with no module.
    static func apacheError(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.expect("["), let time = LogTimeParser.weekdayFirst(&c), c.expect("] ["), let tag = c.until("]") else { return nil }
        var module: ArraySlice<UInt8>?
        var word = tag
        if let colon = tag.lastIndex(of: UInt8(ascii: ":")) {
            module = tag[tag.startIndex..<colon]
            word = tag[(colon + 1)...]
        }
        guard let level = level(word, anyCase: true) else { return nil }
        // The [pid …], [client …] fields are part of the header.
        while true {
            var t = c
            t.skipSpaces()
            guard t.expect("["), let field = t.until("]"),
                field.starts(with: "pid ".utf8) || field.starts(with: "client ".utf8) || field.starts(with: "remote ".utf8)
            else { break }
            c = t
        }
        c.skipSpaces()
        return LogLineHead(format: .apacheError, level: level, time: time, component: module.flatMap(component), messageStart: c.offset)
    }

    /// `[2026-10-01T00:00:00Z INFO  my_crate::module] message`: the time, a level and a target inside one bracket.
    static func bracketedPlain(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.expect("["), let time = LogTimeParser.iso(&c), c.skipSpaces() > 0 else { return nil }
        guard let inner = c.until("]") else { return nil }
        let words = inner.split(separator: UInt8(ascii: " "))
        guard let first = words.first, let level = level(first, anyCase: false) else { return nil }
        let target = words.count > 1 ? component(words[1]) : nil
        c.skipSpaces()
        return LogLineHead(format: .plain, level: level, time: time, component: target, messageStart: c.offset)
    }

    /// `<34>1 2026-10-01T00:00:00Z host app procid msgid [sd] message` (RFC 5424), or a priority in front of a
    /// BSD syslog line (`<13>Oct  1 00:00:00 host app: …`). The priority's severity is the level.
    static func syslogWithPriority(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        guard c.expect("<"), let pri = c.someDigits(max: 3)?.value, pri < 192, c.expect(">") else { return nil }
        let level = LogLevel.syslog(severity: pri % 8)
        if c.expect("1 ") {
            let time = LogTimeParser.iso(&c)  // or "-", RFC 5424's NILVALUE
            if time == nil, !c.expect("-") { return nil }
            c.skipSpaces()
            _ = c.word()  // host
            c.skipSpaces()
            let app = c.word()
            c.skipSpaces()
            _ = c.word()  // procid
            c.skipSpaces()
            _ = c.word()  // msgid
            c.skipSpaces()
            skipStructuredData(&c)
            c.skipSpaces()
            return LogLineHead(
                format: .syslog5424, level: level, time: time, component: app.elementsEqual("-".utf8) ? nil : component(app),
                messageStart: c.offset)
        }
        guard var head = bsdSyslog(line[c.i...], ref) else { return nil }
        head.level = level
        head.messageStart += c.offset
        return head
    }

    /// RFC 5424's STRUCTURED-DATA: `-`, or one or more `[id key="value" …]` (a `]` inside a quoted value escaped).
    private static func skipStructuredData(_ c: inout ByteCursor) {
        if c.expect("-") { return }
        while c.peek() == UInt8(ascii: "[") {
            var escaped = false
            var quoted = false
            c.i += 1
            while let b = c.peek() {
                c.i += 1
                if escaped { escaped = false; continue }
                if b == UInt8(ascii: "\\") { escaped = true; continue }
                if b == UInt8(ascii: "\"") { quoted.toggle(); continue }
                if b == UInt8(ascii: "]"), !quoted { break }
            }
        }
    }
}
