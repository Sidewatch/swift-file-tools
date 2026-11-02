//
//  LogInstant.swift
//  LogReader
//
//  When a log entry happened, as far as its line says.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// When an entry happened: seconds since 1970-01-01T00:00:00Z. A time written without a zone is
/// taken as UTC (`zoned` false), so one file's times still order and filter among themselves; a
/// format that leaves out the year or the date takes them from the reading's reference date.
public struct LogInstant: Equatable, Sendable {
    /// Seconds since the Unix epoch.
    public let seconds: Double
    /// Whether the line said which zone the time is in.
    public let zoned: Bool

    /// Creates an instant.
    public init(seconds: Double, zoned: Bool) {
        self.seconds = seconds
        self.zoned = zoned
    }
}
