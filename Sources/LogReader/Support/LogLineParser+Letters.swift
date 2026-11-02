//
//  LogLineParser+Letters.swift
//  LogReader
//
//  The formats that lead with a level letter or word, and the short-clock ones: Ruby's Logger, klog, logcat,
//  Python's basic format, java.util.logging, Elixir.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

extension LogLineParser {
    /// `I, [2026-10-01T00:00:00.123456 #123]  INFO -- progname: message` (Ruby's Logger, Rails): the spelled-out
    /// level is the level (`ANY` and an unknown letter none), the progname, when there is one, the component.
    static func rubyLogger(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let letter = c.peek(), ByteCursor.isLetter(letter) else { return nil }
        c.i += 1
        guard c.expect(", ["), let time = LogTimeParser.iso(&c), c.expect(" #"), c.someDigits() != nil, c.expect("]") else { return nil }
        c.skipSpaces()
        let word = c.word()
        let level = level(word, anyCase: false) ?? LogLevel.letter(letter)
        c.skipSpaces()
        guard c.expect("--") else { return nil }
        c.skipSpaces()
        let start = c.i
        guard c.until(":") != nil else { return nil }
        let progname = line[start..<(c.i - 1)]
        c.skipSpaces()
        return LogLineHead(format: .rubyLogger, level: level, time: time, component: component(progname), messageStart: c.offset)
    }

    /// `I1001 00:00:00.123456   12345 controller.go:123] message` (klog, glog): the letter is the level, the
    /// source file the component.
    static func klog(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let letter = c.peek(), "IWEF".utf8.contains(letter) else { return nil }
        c.i += 1
        guard let time = LogTimeParser.monthDay(&c, dashed: false, ref), c.skipSpaces() > 0, c.someDigits() != nil, c.expect(" ")
        else { return nil }
        let start = c.i
        guard c.until("]") != nil else { return nil }
        let source = line[start..<(c.i - 1)]
        let file = source.firstIndex(of: UInt8(ascii: ":")).map { source[source.startIndex..<$0] } ?? source
        c.skipSpaces()
        return LogLineHead(format: .klog, level: LogLevel.letter(letter), time: time, component: component(file), messageStart: c.offset)
    }

    /// `10-01 00:00:00.123  1234  5678 I ActivityManager: message` (logcat's threadtime): the letter is the level,
    /// the tag the component.
    static func logcat(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.monthDay(&c, dashed: true, ref), c.skipSpaces() > 0, c.someDigits() != nil, c.skipSpaces() > 0,
            c.someDigits() != nil, c.skipSpaces() > 0, let letter = c.peek(), let level = LogLevel.letter(letter), c.peek(1) == 0x20
        else { return nil }
        c.i += 2
        let start = c.i
        guard c.until(":") != nil else { return nil }
        let tag = line[start..<(c.i - 1)]
        c.skipSpaces()
        return LogLineHead(format: .logcat, level: level, time: time, component: component(tag), messageStart: c.offset)
    }

    /// `WARNING:root:message`: Python's logging with no format set (no time).
    static func pythonBasic(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let word = c.until(":"), Self.pythonLevels.contains(word.text), let level = LogLevel.named(word.text),
            let name = c.until(":"), !name.isEmpty, !name.contains(UInt8(ascii: " "))
        else { return nil }
        return LogLineHead(format: .pythonBasic, level: level, component: component(name), messageStart: c.offset)
    }

    private static let pythonLevels: Set<String> = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

    /// `Oct 01, 2026 12:00:00 AM com.example.Main run` (java.util.logging's SimpleFormatter): the class is the
    /// component; the level is on the next line (`INFO: message`).
    static func javaUtilLogging(_ line: ArraySlice<UInt8>) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.monthNameCommaYear(&c), c.expect(" ") else { return nil }
        let source = c.word()
        return LogLineHead(
            format: .javaUtilLogging, time: time, component: component(source), messageStart: c.offset, levelOnNextLine: true)
    }

    /// The level java.util.logging writes at the start of the line under its header: `INFO: message`.
    public static func javaUtilLoggingLevel(_ line: ArraySlice<UInt8>) -> LogLevel? {
        var c = ByteCursor(line)
        guard let word = c.until(":"), Self.julLevels.contains(word.text) else { return nil }
        return LogLevel.named(word.text)
    }

    private static let julLevels: Set<String> = ["SEVERE", "WARNING", "INFO", "CONFIG", "FINE", "FINER", "FINEST"]

    /// `00:00:00.123 [info] message` (Elixir's Logger), with metadata before the level where it is configured
    /// (Phoenix's `request_id=F18a… [warning] …`): no date, so the reference's.
    static func elixir(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        var c = ByteCursor(line)
        guard let time = LogTimeParser.timeOnly(&c, ref), c.expect(" ") else { return nil }
        while c.peek() != UInt8(ascii: "["), !c.atEnd {
            let pair = c.word()
            guard pair.contains(UInt8(ascii: "=")), c.expect(" ") else { return nil }
        }
        guard c.expect("["), let word = c.until("]"), let level = level(word, anyCase: true) else { return nil }
        c.skipSpaces()
        return LogLineHead(format: .elixir, level: level, time: time, messageStart: c.offset)
    }
}
