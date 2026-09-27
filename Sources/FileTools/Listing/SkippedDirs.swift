//
//  SkippedDirs.swift
//  FileTools
//
//  The set of "noise" directory names (version-control metadata, build output,
//  dependency caches) that scanners should skip when walking a project tree.
//  Matching is by NAME, so the list is configurable: a project with a real
//  `dist/` or `build/` source directory must be able to get it back.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A shared, configurable set of directory names that file scanners ignore: version-control
/// metadata, package managers, build output and caches.
///
/// Matching is by name, so the defaults are a heuristic: a project with real sources in `dist/`
/// can take it off by assigning ``names``. ``names`` is global state read by ``FileTree`` and
/// ``ProjectSearch``; set it at start-up rather than during a walk.
public enum SkippedDirs {

    /// The built-in noise list: the baseline for an editable list and the target of
    /// "Restore Defaults".
    public static let defaultNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm",
        "Pods", "DerivedData", ".next", "__pycache__", ".cache",
        "build", "dist", "vendor", ".DS_Store", ".Trash",
    ]

    /// Directory names to skip when scanning a project. Defaults to
    /// ``defaultNames``; assign to override (e.g. from a user preference).
    ///
    /// Lock-guarded: written from settings on the main thread and read by scans on background
    /// queues, and a torn `Set` read is a crash rather than a wrong answer.
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
