//
//  IgnoreFile.swift
//  SwiftFileTools
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
//

import Foundation

/// One parsed ignore file (`.gitignore`, `.ignore`, `.rgignore`, `.fdignore`, …),
/// bound to the directory it lives in.
///
/// ```swift
/// let text = try String(contentsOf: url, encoding: .utf8)
/// let file = IgnoreFile(text: text, directory: "src/vendor")
/// ```
///
/// An `IgnoreFile` on its own only knows about its own patterns; combining
/// several files from root to leaf with correct precedence is ``IgnoreStack``'s
/// job.
public struct IgnoreFile: Sendable, Equatable {

    /// This file's directory, relative to the scan root, `/`-separated with no
    /// leading or trailing slash. `""` for the root directory itself.
    public let directory: String

    /// The file's patterns, in source order (parsing order matters: within one
    /// file, the LAST matching pattern wins).
    public let patterns: [IgnorePattern]

    /// Parses `text` as one ignore file.
    ///
    /// - Parameters:
    ///   - text: The file's raw contents. Split on `\n`; a trailing `\r` on each
    ///     line (Windows line endings) is trimmed.
    ///   - directory: The relative path (from the scan root) of the folder this
    ///     file lives in, e.g. `""` for the root or `"src/vendor"`. Leading and
    ///     trailing slashes are stripped if present.
    public init(text: String, directory: String) {
        self.directory = IgnoreFile.normalize(directory)
        self.patterns = text.components(separatedBy: "\n").compactMap { line in
            let trimmedCR = line.hasSuffix("\r") ? String(line.dropLast()) : line
            return IgnorePattern(line: trimmedCR)
        }
    }

    /// This file's own verdict for `relativePath`, or `nil` if none of its
    /// patterns say anything about it (either no pattern matched, or the path
    /// isn't under this file's directory at all).
    ///
    /// - Returns: `true` if the last matching pattern excludes the path,
    ///   `false` if the last matching pattern is a `!`-negation that re-includes
    ///   it, `nil` if no pattern in this file matched.
    func verdict(for relativePath: String, isDirectory: Bool) -> Bool? {
        guard let local = localPath(for: relativePath) else { return nil }
        var result: Bool?
        for pattern in patterns where pattern.matches(path: local, isDirectory: isDirectory) {
            result = !pattern.negated
        }
        return result
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
