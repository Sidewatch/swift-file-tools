//
//  FileRewrite.swift
//  FileTools
//
//  Replaces a file's bytes atomically while keeping the file's own permissions and
//  extended attributes.
//
//  Created by David Sherlock on 9/18/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Replaces a file's bytes atomically while keeping the file's own permissions and extended
/// attributes.
///
/// `Data.write(to:options: .atomic)` drops every extended attribute (Finder tags,
/// `com.apple.TextEncoding`) and, on a hard-linked file, resets the mode (`755` becomes `644`).
/// `FileManager.replaceItemAt` carries the metadata over. Either way the result is a new inode,
/// so another hard link to the old file keeps the old bytes.
public enum FileRewrite {

    /// Writes `data` over `url`, atomically, keeping the existing file's permission bits
    /// and extended attributes.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }
        let staging = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: url, create: true)
        let temporary = staging.appendingPathComponent(url.lastPathComponent)
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: temporary)
        _ = try fm.replaceItemAt(url, withItemAt: temporary)
    }
}
