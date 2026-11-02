//
//  LogFormat.swift
//  LogReader
//
//  The log line shapes the reader knows.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// The shape a line was read as. One file can hold several (a service writing plain lines and JSON).
public enum LogFormat: String, CaseIterable, Sendable {
    /// A timestamp, then a level and a component in some order: plain service logs, Python's logging, log4j and
    /// logback, Rust's env_logger and tracing, PostgreSQL, MySQL, kubectl's timestamp prefix.
    case plain
    /// One JSON object a line: pino, bunyan, winston, zap, logrus, zerolog, structlog, slog, ECS, Serilog.
    case json
    /// Docker's json-file driver: `{"log": …, "stream": …, "time": …}`.
    case dockerJSON
    /// `key=value` pairs: logfmt, Go's slog TextHandler, Heroku.
    case logfmt
    /// RFC 5424 syslog, `<pri>1 time host app …`.
    case syslog5424
    /// BSD syslog (RFC 3164) and journald's short forms: `Oct  1 00:00:00 host program[pid]: …`.
    case syslog
    /// macOS's `log show`.
    case appleUnified
    /// Ruby's Logger (and Rails): `I, [time #pid]  INFO -- progname: …`.
    case rubyLogger
    /// Kubernetes' klog: `I1001 00:00:00.123456 12345 file.go:123] …`.
    case klog
    /// Android's logcat, threadtime: `10-01 00:00:00.123 1234 5678 I Tag: …`.
    case logcat
    /// Laravel and Monolog: `[time] channel.LEVEL: …`.
    case monolog
    /// PHP's own error log: `[01-Oct-2026 00:00:00 UTC] PHP Warning: …`.
    case phpError
    /// Apache httpd's error log: `[Wed Oct 01 …] [module:level] …`.
    case apacheError
    /// The Common and Combined Log Formats (Apache, nginx access logs): the status code is the level.
    case accessLog
    /// nginx's error log: `2026/10/01 00:00:00 [error] …`.
    case nginxError
    /// Go's log package: `2026/10/01 00:00:00 …`, no level.
    case goLog
    /// Redis: `123:M 01 Oct 2026 00:00:00.123 * …`.
    case redis
    /// Elixir's Logger: `00:00:00.123 [info] …`.
    case elixir
    /// java.util.logging's SimpleFormatter: a time-and-source line, the level on the next.
    case javaUtilLogging
    /// Python's logging with no format set: `INFO:root:…`.
    case pythonBasic
    /// A line that is no format: a log with no headers at all, read a line at a time.
    case text
}
