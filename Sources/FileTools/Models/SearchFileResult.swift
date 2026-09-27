//
//  SearchFileResult.swift
//  FileTools
//
//  All matches found within a single file, produced by ``ProjectSearch``.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// All matches found within a single file during a project search.
public struct SearchFileResult {

    /// The file the matches were found in.
    public let url: URL

    /// Every match within the file, in the order they appear.
    public let matches: [SearchMatch]

    /// Creates a per-file search result.
    /// - Parameters:
    ///   - url: The file the matches were found in.
    ///   - matches: The matches within the file.
    public init(url: URL, matches: [SearchMatch]) {
        self.url = url
        self.matches = matches
    }
}
