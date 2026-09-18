//
//  FileRewrite.swift
//  FileTools
//
//  Replaces a file's bytes atomically while keeping the file's own permissions and
//  extended attributes.
//
//  Created by David Sherlock on 9/18/26.
//

import Foundation

/// Replaces a file's bytes atomically while keeping the file's own permissions and extended
/// attributes.
///
/// `Data.write(to:options: .atomic)` writes a temporary file and renames it over the
/// original, and the temporary carries DEFAULT permissions: measured on macOS 26, a
/// rewrite of a `755` shell script left a `644` file. A Replace All across a project
/// stripped the executable bit from every script it touched. `FileManager.replaceItemAt`
/// is the same rename with the original's metadata carried over, which is what a rewrite
/// of an existing file wants; a file that does not exist yet is simply written.
public enum FileRewrite {

    /// Writes `data` over `url`, atomically, keeping the existing file's permission bits
    /// and extended attributes.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: url, create: true)
        let temporary = staging.appendingPathComponent(url.lastPathComponent)
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: temporary)
        _ = try fm.replaceItemAt(url, withItemAt: temporary)
    }
}
