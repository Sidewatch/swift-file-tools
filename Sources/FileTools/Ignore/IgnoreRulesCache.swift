//
//  IgnoreRulesCache.swift
//  FileTools
//

import Foundation

/// Per-root cache with a short lifetime: a search re-runs on every keystroke and must not
/// spawn `git` each time, yet a `.gitignore` edit should be noticed within seconds. Hosts
/// that watch the tree can call ``invalidate(root:)`` the moment an ignore file changes.
public enum IgnoreRulesCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [URL: (rules: IgnoreRules, at: Date)] = [:]
    /// Bumps whenever a root's rules are (re)loaded or invalidated, so a consumer holding
    /// derived state (``IgnoreMatcher``'s per-directory stacks) knows to rebuild.
    nonisolated(unsafe) public private(set) static var generation = 0
    /// How long a loaded set stays fresh without an explicit invalidation.
    nonisolated(unsafe) public static var lifetime: TimeInterval = 10

    public static func rules(for root: URL, fileManager: FileManager = .default) -> IgnoreRules {
        let key = root.standardizedFileURL
        lock.lock()
        if let hit = entries[key], Date().timeIntervalSince(hit.at) < lifetime { lock.unlock(); return hit.rules }
        lock.unlock()
        let fresh = IgnoreRules.load(root: key, fileManager: fileManager)
        lock.lock(); entries[key] = (fresh, Date()); generation &+= 1; lock.unlock()
        return fresh
    }

    /// Drops the cached set for `root` (and any root above it, whose rules may include it).
    public static func invalidate(root: URL) {
        let path = root.standardizedFileURL.path
        lock.lock()
        entries = entries.filter { !path.hasPrefix($0.key.path) && !$0.key.path.hasPrefix(path) }
        generation &+= 1
        lock.unlock()
    }

    public static func invalidateAll() { lock.lock(); entries = [:]; generation &+= 1; lock.unlock() }
}
