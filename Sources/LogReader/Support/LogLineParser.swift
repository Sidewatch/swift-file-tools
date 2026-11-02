//
//  LogLineParser.swift
//  LogReader
//
//  Reads the header of one log line in any known format, or says the line has none.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One log line's header, read by trying the formats whose first byte fits, most particular first: a line
/// starting `{` is tried as JSON, `<` as syslog with a priority, `[` as Monolog, PHP's or Apache's error log
/// or a bracketed plain header, a digit as an access log, Redis, logcat, a slash date (nginx, Go), macOS's
/// `log show`, syslog after an ISO time, Elixir or a plain timestamp-led line, a letter as Ruby's Logger,
/// klog, Python's basic format, BSD syslog, java.util.logging or logfmt. nil means the line has no header
/// and continues the entry above it (a stack trace, a wrapped message, PostgreSQL's DETAIL lines).
public enum LogLineParser {
    /// The header of `line` (its bytes without the line break), read against `reference` for the formats that
    /// leave out the year or the date; nil when the line has none.
    public static func head(of line: ArraySlice<UInt8>, reference: LogReference) -> LogLineHead? {
        guard let first = line.first else { return nil }
        if ByteCursor.isDigit(first) { return digitLed(line, reference) }
        if ByteCursor.isLetter(first) { return letterLed(line, reference) }
        switch first {
        case UInt8(ascii: "{"): return json(line, reference)
        case UInt8(ascii: "<"): return syslogWithPriority(line, reference)
        case UInt8(ascii: "["): return bracketed(line, reference)
        case UInt8(ascii: ":"): return accessLog(line)  // an IPv6 client, `::1`
        default: return nil
        }
    }

    /// `head(of:reference:)` over a line's text.
    public static func head(of line: String, reference: LogReference) -> LogLineHead? {
        head(of: Array(line.utf8)[...], reference: reference)
    }

    private static func digitLed(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        if let head = accessLog(line) ?? redis(line) ?? logcat(line, ref) ?? slashDated(line) { return head }
        if let head = appleUnified(line) ?? isoSyslog(line) ?? elixir(line, ref) ?? generic(line, ref) { return head }
        return logfmt(line, ref)
    }

    private static func letterLed(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        if let head = rubyLogger(line) ?? klog(line, ref) ?? pythonBasic(line) { return head }
        if let head = javaUtilLogging(line) ?? bsdSyslog(line, ref) ?? accessLog(line) { return head }
        return logfmt(line, ref)
    }

    /// The level a line with no header names, for logs that have none: the most severe level word written in
    /// capitals (`ERROR`, `WARN`, `FATAL`…) among its first 256 bytes; nil when there is none.
    public static func keywordLevel(_ line: ArraySlice<UInt8>) -> LogLevel? {
        var found: LogLevel?
        var i = line.startIndex
        let end = min(line.endIndex, line.startIndex + 256)
        while i < end {
            guard line[i] >= 0x41, line[i] <= 0x5A else {
                i += 1
                continue
            }
            let start = i
            while i < end, ByteCursor.isLetter(line[i]) { i += 1 }
            let word = line[start..<i]
            if word.count >= 4, word.count <= 8, word.allSatisfy({ $0 <= 0x5A }), Self.keywords.contains(word.text),
                let level = LogLevel.named(word.text)
            {
                found = max(found ?? level, level)
            }
        }
        return found
    }

    private static let keywords: Set<String> = [
        "TRACE", "DEBUG", "INFO", "NOTICE", "WARN", "WARNING", "ERROR", "FATAL", "CRITICAL", "PANIC", "SEVERE",
    ]

    // MARK: - Shared reading

    /// A level word in a header: upper case (`INFO`, `WARN`), or any case when `anyCase` (inside brackets, a
    /// JSON or logfmt value). PostgreSQL's `LOG` counts only as `LOG:`.
    static func level(_ word: ArraySlice<UInt8>, anyCase: Bool) -> LogLevel? {
        var w = word
        let colon = w.last == UInt8(ascii: ":")
        if colon { w = w.dropLast() }
        guard !w.isEmpty, w.count <= 13 else { return nil }
        if !anyCase, w.contains(where: { $0 >= 0x61 && $0 <= 0x7A }) { return nil }
        if w.elementsEqual("LOG".utf8) { return colon ? .info : nil }
        // MySQL's bracketed `[System]` and `[Note]` are informational.
        if anyCase, let level = Self.bracketWords[w.text.lowercased()] { return level }
        return LogLevel.named(w.text)
    }

    private static let bracketWords: [String: LogLevel] = ["system": .info, "note": .info]

    /// A line that separates rather than records: logcat's `--------- beginning of main`, journald's `-- Boot … --`
    /// and `-- Logs begin at …`, Ruby Logger's `# Logfile created on …`, the column headings `log show` and
    /// `log stream` print. Such a line is its own row with no level, never the tail of the entry above.
    public static func isSeparator(_ line: ArraySlice<UInt8>) -> Bool {
        let text = line.prefix(64).text
        return text.hasPrefix("--------- beginning of ") || (text.hasPrefix("-- ") && line.suffix(3).elementsEqual(" --".utf8))
            || text.hasPrefix("-- Logs begin at ") || text.hasPrefix("-- Journal begins at ") || text.hasPrefix("# Logfile created on ")
            || text.hasPrefix("Timestamp ") || text.hasPrefix("Filtering the log data")
    }

    /// The words PostgreSQL follows an entry with, under the same prefix: they continue it.
    static let continuationWords: Set<String> = ["DETAIL:", "HINT:", "STATEMENT:", "CONTEXT:", "QUERY:", "LOCATION:"]

    /// A component as written: trimmed, empty as nil.
    static func component(_ bytes: ArraySlice<UInt8>) -> String? {
        let text = bytes.text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
