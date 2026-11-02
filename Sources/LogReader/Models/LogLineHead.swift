//
//  LogLineHead.swift
//  LogReader
//
//  What the start of a log line says: when, how severe, from where, and where its message starts.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// The header of a line that starts an entry.
public struct LogLineHead: Equatable, Sendable {
    /// The shape the line was read as.
    public var format: LogFormat
    /// Its severity, when the line carries one.
    public var level: LogLevel?
    /// When it happened, when the line says.
    public var time: LogInstant?
    /// The logger, module, service, program or tag that wrote it.
    public var component: String?
    /// Where the message starts, in bytes from the line's start.
    public var messageStart: Int
    /// The message itself where the line is structured (a JSON line's `msg`), else nil and the message is the
    /// line from `messageStart` on.
    public var message: String?
    /// The level comes on the next line (java.util.logging writes `INFO: …` under the time).
    public var levelOnNextLine: Bool

    /// Creates a header.
    public init(
        format: LogFormat, level: LogLevel? = nil, time: LogInstant? = nil, component: String? = nil, messageStart: Int = 0,
        message: String? = nil, levelOnNextLine: Bool = false
    ) {
        self.format = format
        self.level = level
        self.time = time
        self.component = component
        self.messageStart = messageStart
        self.message = message
        self.levelOnNextLine = levelOnNextLine
    }
}
