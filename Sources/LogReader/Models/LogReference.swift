//
//  LogReference.swift
//  LogReader
//
//  The date a format that leaves out the year, or the whole date, is read against.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// The day a log is read against: syslog and klog lines carry no year, an Elixir line no date at all.
/// A reader passes the file's modification date; a test passes a fixed one.
public struct LogReference: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a reference day.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}
