//
//  LogLevel.swift
//  LogReader
//
//  The severities every log format's levels map onto.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// One severity scale for every format: each format's own words, letters and numbers map onto it
/// (LogLevel+Parsing).
public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case trace, debug, info, notice, warning, error, fatal

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
}
