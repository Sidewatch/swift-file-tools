//
//  SearchMatch.swift
//  FileTools
//
//  A single text match within one line of a file, produced by ``ProjectSearch``.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A single match of a search query within one line of a file.
public struct SearchMatch {

    /// The 1-based line number the match was found on.
    public let line: Int

    /// The full text of the matching line (trailing newline trimmed).
    public let lineText: String

    /// The range of the match within ``lineText``.
    public let range: NSRange

    /// Creates a search match.
    /// - Parameters:
    ///   - line: The 1-based line number.
    ///   - lineText: The full line of text the match sits on.
    ///   - range: The range of the match within `lineText`.
    public init(line: Int, lineText: String, range: NSRange) {
        self.line = line
        self.lineText = lineText
        self.range = range
    }
}
