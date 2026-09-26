//
//  GitIgnoredSet.swift
//  SwiftFileTools
//
//  For a git checkout, the exact ignored set — asked of git itself, rather
//  than re-derived by re-implementing gitignore semantics. Fast (one process
//  launch for the whole tree) and exact (it IS git's own answer, including
//  `.git/info/exclude`, `core.excludesFile`, and every gitignore-adjacent
//  detail this package's own parser might still get wrong).
//
//  Created by David Sherlock on 9/2/26.
//

import Foundation
import ProcessRunner
import FoundationExtensions

/// The exact set of ignored files and directories in a git working tree, as
/// reported by `git ls-files`.
///
/// This is the preferred path inside a git checkout: it can't drift from
/// git's own behaviour, because it IS git's own behaviour. ``IgnoreFile`` /
/// ``IgnoreStack`` remain necessary for two other cases: a folder that isn't a
/// git checkout at all, and `.ignore`/`.rgignore`/`.fdignore` files, which
/// this git-backed path never sees (git only ever reads `.gitignore` and its
/// own exclude files).
///
/// ```swift
/// guard let ignored = GitIgnoredSet.load(root: projectRoot) else {
///     // not a git checkout (or git failed) — fall back to IgnoreStack
///     return
/// }
/// ignored.isIgnored(relativePath: "build/output.log", isDirectory: false)
/// ```
public struct GitIgnoredSet: Sendable {

    /// Ignored regular files (and non-directory entries), as relative paths
    /// exactly as git reported them.
    private let files: Set<String>

    /// Ignored directories, as relative paths with the trailing `/` removed —
    /// git's `--directory` flag reports a whole ignored directory as one entry
    /// rather than listing its contents.
    private let directories: Set<String>

    init(files: Set<String>, directories: Set<String>) {
        self.files = files
        self.directories = directories
    }

    /// Runs `git -C <root> ls-files -z --others --ignored --exclude-standard
    /// --directory` and parses its output.
    ///
    /// - Parameters:
    ///   - root: The git working tree's root (or any directory inside it —
    ///     `-C` makes git find the tree itself).
    ///   - fileManager: Unused directly (git does its own filesystem access);
    ///     accepted for parity with ``IgnoreStack/load(directory:relativeDirectory:fileManager:)``
    ///     and so a caller can swap in a different manager without two call
    ///     shapes to remember.
    /// - Returns: `nil` if `git` can't be found, `root` isn't inside a work
    ///   tree, the process fails or times out (10 seconds), or its output
    ///   isn't valid UTF-8 — any of which mean "no exact answer available,
    ///   fall back to ``IgnoreStack``".
    public static func load(root: URL, fileManager: FileManager = .default) -> GitIgnoredSet? {
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

    /// Whether `relativePath` is ignored: it is itself a listed file, itself a
    /// listed directory, or lies beneath a listed directory.
    ///
    /// - Parameters:
    ///   - relativePath: `/`-separated path from `root`, no leading slash.
    ///   - isDirectory: Accepted for symmetry with ``IgnoreStack/isIgnored(relativePath:isDirectory:)``;
    ///     not required for correctness here, since git's own `--directory`
    ///     output already disambiguates files from directories via the
    ///     trailing slash.
    public func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        if files.contains(relativePath) { return true }
        if directories.contains(relativePath) { return true }
        for directory in directories where relativePath.hasPrefix(directory + "/") { return true }
        return false
    }

    // MARK: - Process

    private static let timeout: TimeInterval = 10

    /// Launches `git` via `/usr/bin/env` (so it's found on the caller's PATH regardless of
    /// where this process itself lives) and returns its stdout, or `nil` on any failure —
    /// including a `root` that isn't a git work tree, which makes `git ls-files` exit non-zero,
    /// and a git that hangs past `timeout`.
    private static func run(root: URL) -> String? {
        let result = ProcessRunner.run("/usr/bin/env",
                                       ["git", "-C", root.path, "ls-files", "-z",
                                        "--others", "--ignored", "--exclude-standard", "--directory"],
                                       augmentPATH: false, timeout: timeout)
        guard result.succeeded else { return nil }
        return result.stdout.utf8String
    }
}
