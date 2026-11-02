//
//  LogFilter.swift
//  LogReader
//
//  Which entries to show: by level, time, component and text.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// Which entries to show. Every condition must hold; an empty filter shows everything.
public struct LogFilter: Equatable, Sendable {
    /// The levels shown; an entry with no level is shown by `showsUnleveled`.
    public var levels: Set<LogLevel>
    /// Whether entries with no level are shown.
    public var showsUnleveled: Bool
    /// The earliest time shown (seconds since the epoch); entries with no time pass a time bound.
    public var from: Double?
    /// The latest time shown.
    public var to: Double?
    /// The components shown; nil for all. An entry with no component is shown only when all are.
    public var components: Set<String>?
    /// Text the entry must contain, anywhere in its lines; empty for none.
    public var text: String
    public var caseSensitive: Bool
    public var isRegex: Bool

    /// Creates a filter (by default: everything).
    public init(
        levels: Set<LogLevel> = Set(LogLevel.allCases), showsUnleveled: Bool = true, from: Double? = nil, to: Double? = nil,
        components: Set<String>? = nil, text: String = "", caseSensitive: Bool = false, isRegex: Bool = false
    ) {
        self.levels = levels
        self.showsUnleveled = showsUnleveled
        self.from = from
        self.to = to
        self.components = components
        self.text = text
        self.caseSensitive = caseSensitive
        self.isRegex = isRegex
    }

    /// Whether it lets every entry through.
    public var isEmpty: Bool {
        levels.count == LogLevel.allCases.count && showsUnleveled && from == nil && to == nil && components == nil && text.isEmpty
    }
}
