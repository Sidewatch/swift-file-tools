//
//  SearchStreamBuffer.swift
//  FileTools
//
//  The files a search walk found since the last hand-off to the main thread.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The files a search walk found since the last hand-off to the main thread. Locked: the walk
/// appends on its queue while the flush drains.
public final class SearchStreamBuffer: @unchecked Sendable {
    /// Creates an empty buffer.
    public init() {}

    private let lock = NSLock()
    private var pending: [SearchFileResult] = []

    /// Adds one matching file.
    public func append(_ result: SearchFileResult) { lock.lock(); pending.append(result); lock.unlock() }

    /// When the last batch went to main; zero, so the first file found goes at once.
    private var lastHandOff: TimeInterval = 0
    /// Set by the final hand-off: a timer tick racing the end of the walk gets nothing.
    private var closed = false

    /// The files gathered since the last hand-off, when one is due: there are some and `interval`
    /// has passed since the last, or `force` (the end of the walk, which always hands off, even
    /// nothing). Nil when nothing is due.
    public func drainIfDue(interval: TimeInterval, force: Bool) -> [SearchFileResult]? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || (!pending.isEmpty && now - lastHandOff >= interval) else { return nil }
        lastHandOff = now
        if force { closed = true }
        let out = pending
        pending = []
        return out
    }
}
