//
//  ReplaceSummary.swift
//  SwiftFileTools
//
//  The outcome of a project-wide replace, produced by ``ProjectSearch/replaceAll``.
//
//  Created by David Sherlock on 7/19/26.
//

import Foundation

/// The result of a project-wide replace: how many files were rewritten, how many
/// individual occurrences were replaced, and how many matching files could not be
/// written (permissions, disk error).
public struct ReplaceSummary: Equatable, Sendable {

    /// Number of files that were actually rewritten on disk.
    public let filesChanged: Int

    /// Total individual occurrences replaced across all changed files.
    public let replacements: Int

    /// Number of files that had matches but could not be written.
    public let filesFailed: Int

    /// Creates a replace summary.
    public init(filesChanged: Int, replacements: Int, filesFailed: Int) {
        self.filesChanged = filesChanged
        self.replacements = replacements
        self.filesFailed = filesFailed
    }

    /// A summary with nothing changed (empty query, invalid regex, or no matches).
    public static let empty = ReplaceSummary(filesChanged: 0, replacements: 0, filesFailed: 0)
}
