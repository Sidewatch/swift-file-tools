//
//  GitCheckIgnoreOutput.swift
//  FileTools
//
//  Reads `git check-ignore -v -z` output into the rule it names.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Reads the output of `git check-ignore -v -z --stdin` for one path.
enum GitCheckIgnoreOutput {
    /// The rule that ignores the path: the first record's source, line and pattern
    /// (`<source> NUL <line> NUL <pattern> NUL <path> NUL`). Nil when there is no record, it is
    /// malformed, or its pattern is a `!` rule (the path is put back, not ignored). A relative
    /// source is measured from the checkout git ran in; `prefix` (that checkout's directory
    /// from the scan root) is put in front so it reads from the scan root.
    static func reason(from output: String, prefix: String = "") -> IgnoreReason? {
        let fields = output.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4, !fields[0].isEmpty, let line = Int(fields[1]), line > 0, !fields[2].hasPrefix("!") else {
            return nil
        }
        let source = fields[0].hasPrefix("/") || prefix.isEmpty ? fields[0] : prefix + "/" + fields[0]
        return IgnoreReason(source: source, line: line, pattern: fields[2])
    }
}
