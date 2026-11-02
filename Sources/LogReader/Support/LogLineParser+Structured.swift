//
//  LogLineParser+Structured.swift
//  LogReader
//
//  Structured lines: one JSON object a line (and Docker's json-file wrapping), and logfmt.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension LogLineParser {
    /// One JSON object: the level from `level` / `lvl` / `severity` / `levelname` / `log.level` / `@l` (a word, or
    /// pino's and bunyan's numbers), the time from `time` / `ts` / `timestamp` / `@timestamp` / `@t` / `t` (text,
    /// or seconds or milliseconds since the epoch), the component from `name` / `logger` / `service` /
    /// `component` / `module`, the message from `msg` / `message` / `@m` / `@mt` / `event`. Docker's json-file
    /// lines (`log`, `stream`, `time`) are read through to the line they carry; the stream is the component.
    static func json(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { return nil }
        if let inner = object["log"] as? String, let stream = object["stream"] as? String {
            let text = inner.hasSuffix("\n") ? String(inner.dropLast()) : inner
            let carried = head(of: text, reference: ref)
            return LogLineHead(
                format: .dockerJSON, level: carried?.level, time: (object["time"] as? String).flatMap(instant) ?? carried?.time,
                component: stream, message: text)
        }
        var head = LogLineHead(format: .json)
        head.level = jsonLevel(object)
        head.time = first(of: Self.timeKeys, in: object).flatMap(jsonInstant)
        head.component = first(of: Self.componentKeys, in: object).flatMap { $0 as? String }.flatMap { $0.isEmpty ? nil : $0 }
        head.message = first(of: Self.messageKeys, in: object).flatMap { $0 as? String }
        guard head.level != nil || head.time != nil || head.message != nil else { return nil }
        return head
    }

    /// winston's npm levels that are not names elsewhere: `http` between info and verbose, `silly` below debug.
    private static let npmLevels: [String: LogLevel] = ["http": .info, "silly": .trace]

    private static let levelKeys = ["level", "lvl", "severity", "levelname", "log.level", "@l", "loglevel", "log_level"]
    private static let timeKeys = ["time", "ts", "timestamp", "@timestamp", "@t", "t", "datetime", "date", "asctime"]
    private static let componentKeys = ["name", "logger", "service", "component", "module", "logger_name"]
    private static let messageKeys = ["msg", "message", "@m", "@mt", "event", "text"]

    private static func first(of keys: [String], in object: [String: Any]) -> Any? {
        for key in keys { if let value = object[key] { return value } }
        return nil
    }

    private static func jsonLevel(_ object: [String: Any]) -> LogLevel? {
        let value = first(of: levelKeys, in: object) ?? (object["log"] as? [String: Any])?["level"]
        if let word = value as? String { return LogLevel.named(word) ?? Self.npmLevels[word] }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return LogLevel.numbered(number.intValue) }
        return nil
    }

    private static func jsonInstant(_ value: Any) -> LogInstant? {
        if let text = value as? String { return instant(text) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return LogTimeParser.epoch(number.doubleValue) }
        return nil
    }

    /// A time written as text in a structured line: ISO 8601 first, then the other shapes a whole line can start with.
    static func instant(_ text: String) -> LogInstant? {
        let bytes = Array(text.utf8)[...]
        var c = ByteCursor(bytes)
        if let t = LogTimeParser.iso(&c) ?? LogTimeParser.slashDate(&c) ?? LogTimeParser.commonLog(&c) { return t }
        if let seconds = Double(text) { return LogTimeParser.epoch(seconds) }
        return nil
    }

    /// `time=2026-10-01T00:00:00Z level=info msg="…" component=api` (logfmt, Go's slog TextHandler): `level` /
    /// `lvl` / `severity` / `at`, `time` / `ts` / `t` / `timestamp`, `component` / `logger` / `module` /
    /// `service` / `name`, `msg` / `message`.
    static func logfmt(_ line: ArraySlice<UInt8>, _ ref: LogReference) -> LogLineHead? {
        guard let pairs = LogfmtPairs(line) else { return nil }
        let level = ["level", "lvl", "severity", "at"].lazy.compactMap { pairs[$0] }.first.flatMap(LogLevel.named)
        let time = ["time", "ts", "t", "timestamp"].lazy.compactMap { pairs[$0] }.first.flatMap(instant)
        let component = ["component", "logger", "module", "service", "name"].lazy.compactMap { pairs[$0] }.first
        let message = pairs["msg"] ?? pairs["message"]
        guard level != nil || time != nil else { return nil }
        return LogLineHead(format: .logfmt, level: level, time: time, component: component, message: message)
    }
}
