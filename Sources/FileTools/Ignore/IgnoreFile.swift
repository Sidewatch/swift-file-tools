//
//  IgnoreFile.swift
//  FileTools
//
//  A pure-Swift implementation of `.gitignore` pattern syntax, as documented at
//  https://git-scm.com/docs/gitignore — blank lines and `#` comments, trailing
//  whitespace, `!` negation, anchoring, directory-only patterns, `*`/`?`/`[...]`
//  globs and the `**` double-asterisk forms, and backslash escaping. This is the
//  fallback matcher for folders that aren't a git checkout (and for `.ignore`
//  files, which git itself never reads); see ``GitIgnoredSet`` for the exact,
//  git-backed answer inside a checkout.
//
//  Created by David Sherlock on 9/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One parsed ignore file (`.gitignore`, `.ignore`, `.rgignore`, `.fdignore`, …), bound to the
/// directory it lives in. It knows only its own patterns; combining files from root to leaf
/// with the right precedence is ``IgnoreStack``'s job.
public struct IgnoreFile: Sendable, Equatable {

    /// This file's directory, relative to the scan root, `/`-separated with no
    /// leading or trailing slash. `""` for the root directory itself.
    public let directory: String

    /// The file's patterns, in source order (parsing order matters: within one
    /// file, the LAST matching pattern wins).
    public let patterns: [IgnorePattern]

    /// The file's name (`.gitignore`, `.ignore`, …); empty when parsed from text alone.
    public let name: String

    /// Each pattern's line in the file, counted from 1, in step with ``patterns``.
    public let lineNumbers: [Int]

    /// Parses `text` as one ignore file.
    ///
    /// - Parameters:
    ///   - text: The file's raw contents. Split on `\n`; a trailing `\r` on each
    ///     line (Windows line endings) is trimmed.
    ///   - directory: The relative path (from the scan root) of the folder this
    ///     file lives in, e.g. `""` for the root or `"src/vendor"`. Leading and
    ///     trailing slashes are stripped if present.
    ///   - name: The file's name, for ``IgnoreStack/reason(relativePath:isDirectory:)``.
    public init(text: String, directory: String, name: String = "") {
        self.directory = IgnoreFile.normalize(directory)
        self.name = name
        var patterns: [IgnorePattern] = []
        var lineNumbers: [Int] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmedCR = line.hasSuffix("\r") ? String(line.dropLast()) : line
            guard let pattern = IgnorePattern(line: trimmedCR) else { continue }
            patterns.append(pattern)
            lineNumbers.append(index + 1)
        }
        self.patterns = patterns
        self.lineNumbers = lineNumbers
    }

    /// The last of this file's patterns to match `relativePath`, with its line; nil when none
    /// does or the path is not under this file's directory.
    func lastMatch(for relativePath: String, isDirectory: Bool) -> (pattern: IgnorePattern, line: Int)? {
        guard let local = localPath(for: relativePath) else { return nil }
        guard let index = patterns.lastIndex(where: { $0.matches(path: local, isDirectory: isDirectory) }) else { return nil }
        return (patterns[index], lineNumbers[index])
    }

    /// This file's path from the scan root: its directory, then its name.
    var sourcePath: String { directory.isEmpty ? name : directory + "/" + name }

    /// This file's own verdict for `relativePath`, or `nil` if none of its
    /// patterns say anything about it (either no pattern matched, or the path
    /// isn't under this file's directory at all).
    ///
    /// - Returns: `true` if the last matching pattern excludes the path,
    ///   `false` if the last matching pattern is a `!`-negation that re-includes
    ///   it, `nil` if no pattern in this file matched.
    func verdict(for relativePath: String, isDirectory: Bool) -> Bool? {
        lastMatch(for: relativePath, isDirectory: isDirectory).map { !$0.pattern.negated }
    }

    /// `relativePath` made relative to this file's own directory, or `nil` when
    /// `relativePath` doesn't lie under that directory at all.
    private func localPath(for relativePath: String) -> String? {
        if directory.isEmpty { return relativePath }
        guard relativePath == directory || relativePath.hasPrefix(directory + "/") else { return nil }
        if relativePath == directory { return "" }
        return String(relativePath.dropFirst(directory.count + 1))
    }

    private static func normalize(_ directory: String) -> String {
        var d = Substring(directory)
        while d.first == "/" { d.removeFirst() }
        while d.last == "/" { d.removeLast() }
        return String(d)
    }
}
