//
//  IgnoreFileNames.swift
//  FileTools
//
//  The ignore-file names a directory walker should look for, in ripgrep's precedence order: a
//  name later in this list wins over an earlier one when both exist in the SAME directory (e.g.
//
//  Created by David Sherlock on 9/5/26.
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
}
