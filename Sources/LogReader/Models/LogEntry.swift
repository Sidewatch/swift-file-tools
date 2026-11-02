//
//  LogEntry.swift
//  LogReader
//
//  One entry of a log: where it is in the file, and what its header said.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// One entry: a header line and the lines that continue it (a stack trace, a wrapped message).
public struct LogEntry: Equatable, Sendable {
    /// Its place among the file's entries, from 0.
    public let index: Int
    /// The bytes it covers in the file, its last line break left out.
    public let bytes: Range<Int>
    /// Its first line, from 0.
    public let firstLine: Int
    /// How many lines it spans.
    public let lineCount: Int
    public let level: LogLevel?
    public let time: LogInstant?
    public let component: String?
    public let format: LogFormat

    /// Creates an entry.
    public init(
        index: Int, bytes: Range<Int>, firstLine: Int, lineCount: Int, level: LogLevel?, time: LogInstant?, component: String?,
        format: LogFormat
    ) {
        self.index = index
        self.bytes = bytes
        self.firstLine = firstLine
        self.lineCount = lineCount
        self.level = level
        self.time = time
        self.component = component
        self.format = format
    }
}
