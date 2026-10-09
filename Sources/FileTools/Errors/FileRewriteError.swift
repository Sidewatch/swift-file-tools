//
//  FileRewriteError.swift
//  FileTools
//
//  Why a rewrite refused to touch a file: a link to nothing, or a file that cannot be written.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A rewrite ``FileRewrite`` refused, named so a host can show the reason in its own words.
public enum FileRewriteError: LocalizedError, Equatable {
    /// The path is a symbolic link whose target no longer exists. Writing there would replace the
    /// link with a regular file, so nothing is written.
    case danglingSymbolicLink(URL)
    /// The file's permissions deny writing to it.
    case fileNotWritable(URL)

    public var errorDescription: String? {
        switch self {
        case .danglingSymbolicLink(let url): return "“\(url.lastPathComponent)” is a link to a file that no longer exists."
        case .fileNotWritable(let url): return "“\(url.lastPathComponent)” is read-only."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .danglingSymbolicLink: return "Restore the link's target, or replace the link with a file, before saving."
        case .fileNotWritable: return "The file's permissions do not allow writing to it."
        }
    }
}
