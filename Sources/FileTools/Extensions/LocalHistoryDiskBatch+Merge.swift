//
//  LocalHistoryDiskBatch+Merge.swift
//  FileTools
//
//  Folding a later batch into one still waiting.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension LocalHistoryDiskBatch {
    /// The most paths a waiting batch holds: a storm past it records what fits and moves on.
    static let pendingLimit = 1_000

    /// `later` folded in: its paths join (up to ``pendingLimit``), the EARLIER "before" of a path wins
    /// (it is the older content), and the later source and roots describe the window now.
    mutating func merge(_ later: LocalHistoryDiskBatch) {
        for path in later.paths where paths.count < Self.pendingLimit { paths.insert(path) }
        previous.merge(later.previous) { earlier, _ in earlier }
        source = later.source
        ignoreRoots = later.ignoreRoots
        repoRoots = later.repoRoots
    }
}
