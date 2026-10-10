//
//  LocalHistoryDiskRecord.swift
//  FileTools
//
//  What one pass of LocalHistory.recordFromDisk did.
//
//  Created by David Sherlock on 10/10/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The outcome of ``LocalHistory/recordFromDisk(_:source:limit:at:previous:)``.
public struct LocalHistoryDiskRecord: Equatable, Sendable {
    /// The files a new version was kept for, in the order they were examined.
    public var recorded: [URL]
    /// The files whose earlier content was kept first, under ``LocalHistorySource/previous``.
    public var previousKept: [URL]
    /// Files examined and left out: missing, not a regular file, over the size ceiling, binary,
    /// or the same bytes as the last kept version.
    public var skipped: Int
    /// Files past the limit, never looked at.
    public var unexamined: Int

    /// Creates an outcome.
    public init(recorded: [URL] = [], previousKept: [URL] = [], skipped: Int = 0, unexamined: Int = 0) {
        self.recorded = recorded
        self.previousKept = previousKept
        self.skipped = skipped
        self.unexamined = unexamined
    }
}
