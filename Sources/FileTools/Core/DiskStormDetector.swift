//
//  DiskStormDetector.swift
//  SwiftFileTools
//
//  Notices when the file system is changing faster than an editor can be
//  expected to keep up with, and names the folder responsible.
//
//  Created by David Sherlock on 9/2/26.
//

import Foundation

/// Detects a SUSTAINED flood of file-system change events and names the folder
/// it comes from, so a host can show the fact — "248 changes/s under
/// wp-content/cache/object" — and hand the user the lever (the skip list),
/// instead of silently spending CPU, memory and git spawns keeping up with a
/// cache directory.
///
/// Feed it every batch the watcher delivers (after the skip-list filter — a
/// folder already skipped is not a problem worth reporting) and ask for the
/// current ``Storm`` whenever you would show one. Pure and clock-injected, so
/// the thresholds are testable without a file system.
///
/// **The rule, with the judgement written down.** Events are bucketed per
/// second. A storm is ``hotSeconds`` (3) of the last ``window`` (5) seconds
/// each holding at least ``perSecond`` (60) events. *Sustained* is the point:
/// a `git checkout` that touches two thousand files lands in one or two seconds
/// and is not a storm, while a cache writer at a hundred files a second is one
/// after three. A storm's ``Storm/folder`` is the DEEPEST directory holding at
/// least ``share`` (80%) of the window's events — `wp-content/cache/object`,
/// not `wp-content` — and nil when the events are spread across the root.
public struct DiskStormDetector: Sendable {

    /// A sustained flood in progress.
    public struct Storm: Equatable, Sendable {
        /// Events seen in the window.
        public let events: Int
        /// The window the count covers, in seconds.
        public let window: TimeInterval
        /// The root (primary or reference) the flood is under.
        public let root: URL
        /// The deepest directory holding at least the detector's `share` of the
        /// events, or nil when they are spread across `root` itself.
        public let folder: URL?

        /// Events per second, averaged over the window.
        public var perSecond: Int { Int((Double(events) / max(window, 1)).rounded()) }

        /// `folder` relative to `root`; "" when there is no folder.
        public var relativeFolder: String {
            guard let folder else { return "" }
            let r = root.path.hasSuffix("/") ? root.path : root.path + "/"
            return folder.path.hasPrefix(r) ? String(folder.path.dropFirst(r.count)) : folder.lastPathComponent
        }

        /// The folder's own name and each ancestor's, up to but not including
        /// the root, deepest first — the candidates for "skip folders named …".
        /// The USER picks the level; the detector does not guess which name is
        /// safe to skip everywhere. Empty when there is no folder.
        public var ancestorNames: [String] {
            relativeFolder.split(separator: "/").map(String.init).reversed()
        }
    }

    /// Seconds of history a storm is judged over.
    public var window: TimeInterval = 5
    /// Events a single second must hold to count as hot.
    public var perSecond = 60
    /// Hot seconds within the window that make a storm.
    public var hotSeconds = 3
    /// The fraction of the window's events a directory must hold to be named.
    public var share = 0.8

    /// One second of events: how many, how many per root, and how many under
    /// each ancestor directory (keyed by absolute path with a trailing slash).
    private struct Bucket: Sendable {
        var count = 0
        var roots: [String: Int] = [:]
        var dirs: [String: Int] = [:]
    }

    /// Live buckets keyed by whole seconds since the reference date.
    private var buckets: [Int: Bucket] = [:]

    public init() {}

    /// Records one watcher batch. `roots` are the watched folders (primary and
    /// reference); a path outside all of them still counts toward the rate but
    /// can name no folder.
    public mutating func ingest<S: Sequence>(paths: S, roots: [URL], at now: Date) where S.Element == String {
        let key = Self.second(of: now)
        var bucket = buckets[key] ?? Bucket()
        // Longest root first, so a reference root nested inside the primary folder
        // claims its own paths.
        let rootPaths = roots.map { Self.slashed($0.standardizedFileURL.path) }.sorted { $0.count > $1.count }
        for path in paths {
            bucket.count += 1
            guard let root = rootPaths.first(where: { path.hasPrefix($0) }) else { continue }
            bucket.roots[root, default: 0] += 1
            // Every ancestor directory strictly below the root: "a/b/c/f" → a/, a/b/, a/b/c/.
            var dir = root
            for component in path.dropFirst(root.count).split(separator: "/").dropLast() {
                dir += component + "/"
                bucket.dirs[dir, default: 0] += 1
            }
        }
        buckets[key] = bucket
        let oldest = key - Int(window) + 1
        buckets = buckets.filter { $0.key >= oldest }
    }

    /// The storm in progress at `now`, or nil.
    public func storm(at now: Date) -> Storm? {
        let key = Self.second(of: now)
        let live = buckets.filter { $0.key > key - Int(window) && $0.key <= key }
        let hot = live.values.filter { $0.count >= perSecond }.count
        guard hot >= hotSeconds else { return nil }
        var total = 0
        var roots: [String: Int] = [:]
        var dirs: [String: Int] = [:]
        for bucket in live.values {
            total += bucket.count
            for (root, n) in bucket.roots { roots[root, default: 0] += n }
            for (dir, n) in bucket.dirs { dirs[dir, default: 0] += n }
        }
        // Nothing under any root: a flood with no folder to name is not reportable.
        guard let rootPath = roots.max(by: { $0.value < $1.value })?.key else { return nil }
        let need = Int((Double(total) * share).rounded(.up))
        // Ancestors are prefixes of one another, so among the qualifying
        // directories the longest path is the deepest.
        let folder = dirs
            .filter { $0.key.hasPrefix(rootPath) && $0.value >= need }
            .max { $0.key.count < $1.key.count }?.key
        return Storm(events: total, window: window,
                     root: Self.url(rootPath), folder: folder.map(Self.url))
    }

    /// Forgets the window — after the user acts on a storm, so the notice clears
    /// without waiting for the buckets to age out.
    public mutating func reset() { buckets = [:] }

    private static func second(of date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private static func slashed(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private static func url(_ slashedPath: String) -> URL {
        URL(fileURLWithPath: String(slashedPath.dropLast()), isDirectory: true)
    }
}
