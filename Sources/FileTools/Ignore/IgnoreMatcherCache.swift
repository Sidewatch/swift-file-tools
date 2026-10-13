//
//  IgnoreMatcherCache.swift
//  FileTools
//
//  One ignore matcher per scan root, built off-main on first request and shared.
//
//  Created by David Sherlock on 9/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One `IgnoreMatcher` per scan root, built off-main on first request and shared by the file
/// tree, the symbol index and project search, so each root's ignore rules are parsed once.
public final class IgnoreMatcherCache: @unchecked Sendable {
    /// The cache an app's scanners share.
    public static let shared = IgnoreMatcherCache()

    /// Creates an empty cache; most callers share ``shared``.
    public init() {}

    private let lock = NSLock()
    private var matchers: [URL: IgnoreMatcher] = [:]
    private var loading: Set<URL> = []
    private let queue = DispatchQueue(label: "filetools.ignore-matchers", qos: .utility)

    /// The matcher for `root`, loading its rules synchronously if needed. Off-main callers.
    public func matcher(for root: URL) -> IgnoreMatcher {
        let key = root.standardizedFileURL
        lock.lock()
        if let m = matchers[key] { lock.unlock(); return m }
        lock.unlock()
        let m = IgnoreMatcher(root: key)
        _ = IgnoreRulesCache.rules(for: key)  // the git call, here and now
        lock.lock(); matchers[key] = m; lock.unlock()
        return m
    }

    /// The matcher for `root` if its rules are loaded; otherwise starts loading them in the
    /// background, calls `onReady` on the main queue when done, and returns nil. The file tree
    /// uses this so opening a folder never waits on git.
    public func matcher(for root: URL, onReady: @escaping @Sendable () -> Void) -> IgnoreMatcher? {
        let key = root.standardizedFileURL
        lock.lock()
        if let m = matchers[key] { lock.unlock(); return m }
        let alreadyLoading = loading.contains(key)
        loading.insert(key)
        lock.unlock()
        if !alreadyLoading {
            queue.async { [self] in
                _ = matcher(for: key)
                lock.lock(); loading.remove(key); lock.unlock()
                DispatchQueue.main.async(execute: onReady)
            }
        }
        return nil
    }

    /// An ignore file under `root` changed: reload its rules off-main, then `onReady`.
    public func noteChanged(under root: URL, onReady: @escaping @Sendable () -> Void) {
        let key = root.standardizedFileURL
        lock.lock(); matchers[key] = nil; lock.unlock()
        IgnoreRulesCache.invalidate(root: key)
        _ = matcher(for: key, onReady: onReady)
    }
}
