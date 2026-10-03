//
//  ParallelSearchState.swift
//  FileTools
//
//  The parallel search's shared tally: its results, the global match cap, serialised delivery.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The parallel search's shared tally: results, the global match cap, and serialised delivery.
nonisolated final class ParallelSearchState: @unchecked Sendable {
    private let lock = NSLock()
    private let deliverLock = NSLock()
    private var found: [SearchFileResult] = []
    /// Every file added so far.
    var results: [SearchFileResult] { lock.lock(); defer { lock.unlock() }; return found }
    private var total = 0
    /// Whether the global match cap has been reached.
    func isFull(cap: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return total >= cap }

    /// Adds a file's matches unless the cap was already reached; true when it was added.
    func add(_ result: SearchFileResult, cap: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard total < cap else { return false }
        found.append(result)
        total += result.matches.count
        return true
    }

    /// Calls `onFile` with one result at a time, whichever thread found it.
    func deliver(_ result: SearchFileResult, to onFile: (SearchFileResult) -> Void) {
        deliverLock.lock(); defer { deliverLock.unlock() }
        onFile(result)
    }
}
