//
//  IgnoreReason.swift
//  FileTools
//
//  The rule that ignores a path: the file it is written in, its line and its text.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The rule that ignores a path, as `git check-ignore -v` names it: the file the pattern is
/// written in, the pattern's line in that file and the pattern itself.
public struct IgnoreReason: Sendable, Equatable {
    /// The file the rule is in: relative to the scan root (`.gitignore`, `src/.ignore`,
    /// `.git/info/exclude`), or absolute for a file outside it (git's `core.excludesFile`).
    public let source: String
    /// The rule's line in `source`, counted from 1.
    public let line: Int
    /// The rule as written, e.g. `build/` or `*.log`.
    public let pattern: String

    /// A reason from its parts.
    public init(source: String, line: Int, pattern: String) {
        self.source = source
        self.line = line
        self.pattern = pattern
    }
}
