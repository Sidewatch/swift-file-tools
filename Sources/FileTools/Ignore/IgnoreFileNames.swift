//
//  IgnoreFileNames.swift
//  FileTools
//
//  The ignore-file names a directory walker should look for, in ripgrep's precedence order: a
//  name later in this list wins over an earlier one when both exist in the SAME directory (e.g.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The ignore-file names a directory walker should look for, in ripgrep's
/// precedence order: a name later in this list wins over an earlier one when
/// both exist in the SAME directory (e.g. an `.ignore` entry beats a
/// `.gitignore` entry for the same path, in that directory).
///
/// ```swift
/// for name in IgnoreFileNames.orderedNames { … }
/// ```
public enum IgnoreFileNames {

    /// `.gitignore`, `.ignore`, `.rgignore`, `.fdignore`, in that precedence
    /// order (later wins).
    public static let orderedNames: [String] = [".gitignore", ".ignore", ".rgignore", ".fdignore"]

    /// Whether `path` names one of the ignore files, by its last component — so a watcher can
    /// tell which changes should reload the rules.
    public static func names(_ path: String) -> Bool {
        orderedNames.contains((path as NSString).lastPathComponent)
    }
}
