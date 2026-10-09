//
//  GitIgnoredSet.swift
//  FileTools
//
//  For a git checkout, the exact ignored set — asked of git itself, rather
//  than re-derived by re-implementing gitignore semantics. Fast (one process
//  launch for the whole tree) and exact (it IS git's own answer, including
//  `.git/info/exclude`, `core.excludesFile`, and every gitignore-adjacent
//  detail this package's own parser might still get wrong).
//
//  Created by David Sherlock on 9/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import ProcessRunner
import FoundationExtensions

/// The exact set of ignored files and directories in a git working tree, as reported by
/// `git ls-files`: the preferred answer inside a checkout, since it IS git's behaviour.
///
/// ``IgnoreStack`` still covers folders that are not checkouts and the `.ignore`/`.rgignore`/
/// `.fdignore` files git never reads.
///
/// - Note: `git ls-files` never descends into a nested repository: a checkout inside the work
///   tree comes back as one untracked directory entry, so nothing beneath it is in this set.
///   ``IgnoreMatcher`` answers such paths from the nested checkout's own set.
public struct GitIgnoredSet: Sendable {

    /// Ignored regular files (and non-directory entries), as relative paths
    /// exactly as git reported them.
    private let files: Set<String>

    /// Ignored directories, as relative paths with the trailing `/` removed —
    /// git's `--directory` flag reports a whole ignored directory as one entry
    /// rather than listing its contents.
    private let directories: Set<String>

    /// A set from already-parsed `git ls-files` entries.
    init(files: Set<String>, directories: Set<String>) {
        self.files = files
        self.directories = directories
    }

    /// Runs `git -C <root> ls-files -z --others --ignored --exclude-standard --directory` and
    /// parses its output.
    ///
    /// - Returns: nil when git is missing, `root` is not in a work tree, the process fails or
    ///   times out (10 seconds), or the output is not UTF-8: fall back to ``IgnoreStack``.
    public static func load(root: URL) -> GitIgnoredSet? {
        guard let output = run(root: root) else { return nil }
        var files: Set<String> = []
        var directories: Set<String> = []
        for entry in output.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            if entry.hasSuffix("/") {
                directories.insert(String(entry.dropLast()))
            } else {
                files.insert(String(entry))
            }
        }
        return GitIgnoredSet(files: files, directories: directories)
    }

    /// Whether `relativePath` (`/`-separated, no leading slash) is a listed file, a listed
    /// directory, or beneath one. `isDirectory` is unused, accepted for symmetry with
    /// ``IgnoreStack/isIgnored(relativePath:isDirectory:)``: git's trailing slash already tells.
    ///
    /// Costs one set lookup per path component: the path's own ancestors are looked up, the
    /// listing is never scanned, so a tree with thousands of ignored directories answers a row
    /// as fast as a tree with one.
    public func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        if files.contains(relativePath) || directories.contains(relativePath) { return true }
        var from = relativePath.startIndex
        while let slash = relativePath[from...].firstIndex(of: "/") {
            if directories.contains(String(relativePath[..<slash])) { return true }
            from = relativePath.index(after: slash)
        }
        return false
    }

    // MARK: - Process

    private static let timeout: TimeInterval = 10

    /// Launches `git` via `/usr/bin/env` (so it's found on the caller's PATH regardless of
    /// where this process itself lives) and returns its stdout, or `nil` on any failure —
    /// including a `root` that isn't a git work tree, which makes `git ls-files` exit non-zero,
    /// and a git that hangs past `timeout`.
    private static func run(root: URL) -> String? {
        let result = ProcessRunner.run(
            "/usr/bin/env",
            [
                "git", "-C", root.path, "ls-files", "-z",
                "--others", "--ignored", "--exclude-standard", "--directory",
            ],
            augmentPATH: false, timeout: timeout)
        guard result.succeeded else { return nil }
        return result.stdout.utf8String
    }
}
