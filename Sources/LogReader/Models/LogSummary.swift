//
//  LogSummary.swift
//  LogReader
//
//  What a log holds, as far as it has been read: counts by level, the components, the time span, the formats.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// What a log holds so far, for a filter bar's choices and counts.
public struct LogSummary: Equatable, Sendable {
    /// Entries read.
    public let entryCount: Int
    /// Entries at each level.
    public let levelCounts: [LogLevel: Int]
    /// Entries with no level.
    public let unleveledCount: Int
    /// Each component and how many entries it wrote, most first.
    public let components: [(name: String, count: Int)]
    /// The earliest and latest times read.
    public let firstTime: Double?
    public let lastTime: Double?
    /// The formats the entries were read as, most first.
    public let formats: [LogFormat]
    /// Whether the whole file has been read.
    public let isComplete: Bool

    /// Creates a summary.
    public init(
        entryCount: Int, levelCounts: [LogLevel: Int], unleveledCount: Int, components: [(name: String, count: Int)], firstTime: Double?,
        lastTime: Double?, formats: [LogFormat], isComplete: Bool
    ) {
        self.entryCount = entryCount
        self.levelCounts = levelCounts
        self.unleveledCount = unleveledCount
        self.components = components
        self.firstTime = firstTime
        self.lastTime = lastTime
        self.formats = formats
        self.isComplete = isComplete
    }

    public static func == (a: LogSummary, b: LogSummary) -> Bool {
        a.entryCount == b.entryCount && a.levelCounts == b.levelCounts && a.unleveledCount == b.unleveledCount
            && a.components.elementsEqual(b.components, by: { $0.name == $1.name && $0.count == $1.count }) && a.firstTime == b.firstTime
            && a.lastTime == b.lastTime && a.formats == b.formats && a.isComplete == b.isComplete
    }
}
