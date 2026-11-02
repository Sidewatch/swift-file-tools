//
//  LogLineParser+Generic.swift
//  LogReader
//
//  A timestamp, then a level and a component in some order: the shape most application logs share.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLineParser {
    /// A line led by an ISO time (or a bare clock followed by a level, as logback's and log4j2's default
    /// patterns write), then up to eight header tokens:
    /// - a level word in capitals (`INFO`, `WARN`, PostgreSQL's `LOG:`) or a `[level]` in any case;
    /// - `name - LEVEL` (Python's `%(name)s - %(levelname)s`): the name is the component;
    /// - after the level, `logger - ` (log4j, logback) or `target:` (Rust's tracing): the component;
    /// - otherwise the first other `[word]` (`[auth]`, MySQL's `[Server]`): the component;
    /// - a pid, a thread number, `[123]`, `[#7]` or an error code (`[MY-010068]`): skipped;
    /// - `-` and `|` separators: skipped.
    /// The message starts after the last header token. PostgreSQL's `DETAIL:` and its kind continue the entry above.
    static func generic(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        var clockOnly = false
        guard
            let time = LogTimeParser.iso(&c)
                ?? {
                    clockOnly = true
                    return LogTimeParser.timeOnly(&c, ref)
                }()
        else { return nil }
        var reading = GenericHeader(cursor: c)
        guard reading.read() else { return nil }  // a continuation line under the same prefix
        guard !clockOnly || reading.level != nil else { return nil }
        var start = reading.messageStart
        while start < line.endIndex, ByteCursor.isSpace(line[start]) { start += 1 }
        reading.messageStart = start
        return LogLineHead(
            format: .plain, level: reading.level, time: time, component: reading.component.flatMap(component),
            messageStart: reading.messageStart - line.startIndex)
    }
}

/// The token walk behind `LogLineParser.generic`.
private struct GenericHeader {
    var c: ByteCursor
    var level: LogLevel?
    var component: ArraySlice<UInt8>?
    var bracketed: ArraySlice<UInt8>?
    var messageStart: Int

    init(cursor: ByteCursor) {
        c = cursor
        messageStart = cursor.i
    }

    /// Reads the header tokens; false when the line is one that continues the entry above.
    mutating func read() -> Bool {
        var tokens = 0
        walk: while tokens < 8 {
            c.skipSpaces()
            guard !c.atEnd else { break }
            tokens += 1
            let mark = c.i
            if c.expect("- ") || c.expect("| ") || c.expect("--- ") || (c.peek() == UInt8(ascii: "-") && c.peek(1) == nil) {
                messageStart = c.i
                continue
            }
            if c.peek() == UInt8(ascii: "[") {
                guard readBracket() else {
                    c.i = mark
                    break
                }
                continue
            }
            let word = c.word()
            if LogLineParser.continuationWords.contains(word.text) { return false }
            if level == nil, let found = LogLineParser.level(word, anyCase: false) {
                level = found
                messageStart = c.i
                if word.last == UInt8(ascii: ":") { break }  // `LOG:  message`
                if readLoggerAfterLevel() { break }
                continue
            }
            if word.allSatisfy(ByteCursor.isDigit), level == nil || followedByMarker() {
                messageStart = c.i  // a pid or thread number; after the level only Spring Boot's `4127 --- [app]`
                continue
            }
            if level == nil, readPythonName(word) { break }
            if Self.isIdentifier(word), consumeDash() || consumeSpacedColon() {
                component = word  // `com.example.Main - message`, Spring Boot's `c.e.Main      : message`
                break
            }
            c.i = mark
            break walk
        }
        if component == nil { component = bracketed }
        return true
    }

    /// `[word]`: a level, skipped noise, or the component candidate. false when it is none of them.
    private mutating func readBracket() -> Bool {
        var t = c
        t.i += 1
        guard let inner = t.until("]") else { return false }
        if level == nil, let found = LogLineParser.level(inner, anyCase: true) {
            level = found
        } else if Self.isNoise(inner) {
            // a pid, a thread, an error code
        } else if bracketed == nil, component == nil {
            bracketed = inner
        } else if level != nil {
            // a thread after the level (Spring Boot: `[app] [   main] logger : message`)
        } else {
            return false
        }
        c = t
        messageStart = c.i
        return true
    }

    /// After the level: `target: message` (tracing, its spans `name{field=…}:` first) or `logger - message` (log4j,
    /// logback).
    private mutating func readLoggerAfterLevel() -> Bool {
        var t = c
        t.skipSpaces()
        while Self.skipSpan(&t) { t.skipSpaces() }
        let next = t.word()
        guard !next.isEmpty else { return false }
        if next.last == UInt8(ascii: ":"), Self.isIdentifier(next.dropLast()) {
            component = next.dropLast()
            c = t
            messageStart = c.i
            return true
        }
        guard Self.isIdentifier(next) else { return false }
        var u = t
        u.skipSpaces()
        guard u.expect("- ") else { return false }
        component = next
        c = u
        messageStart = c.i
        return true
    }

    /// `name - LEVEL - message`: Python's `%(name)s - %(levelname)s`.
    private mutating func readPythonName(_ word: ArraySlice<UInt8>) -> Bool {
        var t = c
        t.skipSpaces()
        guard t.expect("- ") else { return false }
        t.skipSpaces()
        let next = t.word()
        guard let found = LogLineParser.level(next, anyCase: false) else { return false }
        component = word
        level = found
        t.skipSpaces()
        _ = t.expect("- ")
        c = t
        messageStart = c.i
        return true
    }

    /// A tracing span, `request{method="GET" path="/"}:`, consumed with its colon; false when none is here.
    static func skipSpan(_ c: inout ByteCursor) -> Bool {
        var t = c
        while let b = t.peek(), ByteCursor.isLetter(b) || ByteCursor.isDigit(b) || b == UInt8(ascii: "_") { t.i += 1 }
        guard t.i > c.i, t.expect("{") else { return false }
        var quoted = false
        while let b = t.peek() {
            t.i += 1
            if b == UInt8(ascii: "\"") { quoted.toggle() }
            if b == UInt8(ascii: "}"), !quoted { break }
        }
        guard t.expect(":") else { return false }
        c = t
        return true
    }

    /// Spring Boot's `---` after its pid.
    private func followedByMarker() -> Bool {
        var t = c
        t.skipSpaces()
        return t.expect("--- ")
    }

    /// Spaces, then `: ` after the word just read (Spring Boot pads its logger): consumed.
    private mutating func consumeSpacedColon() -> Bool {
        var t = c
        guard t.skipSpaces() > 0, t.expect(": ") else { return false }
        c = t
        messageStart = c.i
        return true
    }

    /// ` - ` after the word just read: consumed, and the message starts after it.
    private mutating func consumeDash() -> Bool {
        var t = c
        t.skipSpaces()
        guard t.expect("- ") else { return false }
        c = t
        messageStart = c.i
        return true
    }

    /// A pid or thread (`123`, `#7`, `pid 123`), an error code (`MY-010068`), a hex id.
    static func isNoise(_ inner: ArraySlice<UInt8>) -> Bool {
        if inner.isEmpty || inner.allSatisfy(ByteCursor.isDigit) { return true }
        if inner.first == UInt8(ascii: "#"), inner.dropFirst().allSatisfy(ByteCursor.isDigit) { return true }
        if inner.starts(with: "pid ".utf8) || inner.starts(with: "0x".utf8) { return true }
        if let dash = inner.firstIndex(of: UInt8(ascii: "-")), dash > inner.startIndex,
            inner[inner.startIndex..<dash].allSatisfy({ $0 >= 0x41 && $0 <= 0x5A }),
            inner[(dash + 1)...].allSatisfy(ByteCursor.isDigit), dash + 1 < inner.endIndex
        {
            return true
        }
        return false
    }

    /// A logger, module or target name: letters, digits and `. _ : $ / - < >`, with a letter in it; brackets inside
    /// but not first (Spring's abbreviation of Tomcat's `o.a.c.c.C.[.[.[/].[dispatcherServlet]`).
    static func isIdentifier(_ word: ArraySlice<UInt8>) -> Bool {
        guard word.contains(where: ByteCursor.isLetter), word.first != UInt8(ascii: "[") else { return false }
        return word.allSatisfy { b in
            ByteCursor.isLetter(b) || ByteCursor.isDigit(b) || ".-_:$/<>[]".utf8.contains(b)
        }
    }
}
