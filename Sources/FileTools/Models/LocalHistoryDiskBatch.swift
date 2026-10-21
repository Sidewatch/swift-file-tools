//
//  LocalHistoryDiskBatch.swift
//  FileTools
//
//  The files that changed on disk, waiting to be kept in local history.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Files that changed on disk (an agent's writes, a checkout), to be kept by
/// ``LocalHistory/recordDiskBatch(_:limit:)`` — with what decides which of them are kept and what
/// each one held before.
public struct LocalHistoryDiskBatch: Sendable, Equatable {
    /// The changed paths, as the window names them.
    public var paths: Set<String>
    /// Why they changed: ``LocalHistorySource/agent`` while an agent is live, else
    /// ``LocalHistorySource/changedOnDisk``.
    public var source: LocalHistorySource
    /// What a file held before the change, by path, where a clean open buffer knew it.
    public var previous: [String: Data]
    /// The folders whose ignore rules apply (the opened roots and every repository root); the deepest
    /// one holding a path governs it.
    public var ignoreRoots: [URL]
    /// The repositories whose `HEAD` gives a first-seen file its "before".
    public var repoRoots: [URL]

    /// A batch of `paths` changed for `source`.
    public init(paths: Set<String>, source: LocalHistorySource, previous: [String: Data], ignoreRoots: [URL], repoRoots: [URL]) {
        self.paths = paths
        self.source = source
        self.previous = previous
        self.ignoreRoots = ignoreRoots
        self.repoRoots = repoRoots
    }
}
