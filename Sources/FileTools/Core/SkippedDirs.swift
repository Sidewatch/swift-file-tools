//
//  SkippedDirs.swift
//  SwiftFileTools
//
//  The set of "noise" directory names (version-control metadata, build output,
//  dependency caches) that scanners should skip when walking a project tree.
//  Matching is by NAME, so the list is configurable: a project with a real
//  `dist/` or `build/` source directory must be able to get it back.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A shared, configurable set of directory names that file scanners ignore.
///
/// These are the usual noise folders — version-control metadata, package
/// managers, build output and caches — that you almost never want to descend
/// into when searching or rendering a project's structure.
///
/// ```swift
/// if SkippedDirs.names.contains(url.lastPathComponent) { continue }
/// ```
///
/// Matching is by name, not by path, so the defaults are a heuristic rather
/// than a fact: a project that keeps real sources in `dist/` or `build/` would
/// lose them from every scan. Assign ``names`` to override the list, and
/// ``resetToDefault()`` to restore ``defaultNames``:
///
/// ```swift
/// SkippedDirs.names = SkippedDirs.defaultNames.subtracting(["dist"])
/// SkippedDirs.resetToDefault()
/// ```
///
/// - Important: ``names`` is global mutable state read by every scan in this
///   module (``FileTree`` and ``ProjectSearch``). Set it once during start-up,
///   before any scan runs, rather than mutating it concurrently with a walk.
public enum SkippedDirs {

    /// The built-in noise list: version-control metadata, package managers,
    /// build output and caches (e.g. `.git`, `node_modules`, `.build`,
    /// `DerivedData`).
    ///
    /// Use this as the baseline when presenting an editable list to a user, and
    /// as the target of a "Restore Defaults" action.
    public static let defaultNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm",
        "Pods", "DerivedData", ".next", "__pycache__", ".cache",
        "build", "dist", "vendor", ".DS_Store", ".Trash",
    ]

    /// Directory names to skip when scanning a project. Defaults to
    /// ``defaultNames``; assign to override (e.g. from a user preference).
    ///
    /// Lock-guarded because the access pattern genuinely crosses threads: this is written
    /// from a settings pane on the main thread and read by directory scans running on
    /// background queues. A `Set` is not atomic, so an unsynchronized write during a scan
    /// could be read torn — rare, but a crash rather than a wrong answer.
    public static var names: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return storedNames }
        set { lock.lock(); defer { lock.unlock() }; storedNames = newValue }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedNames: Set<String> = defaultNames

    /// Restores ``names`` to ``defaultNames``, discarding any override.
    public static func resetToDefault() {
        names = defaultNames
    }
}
