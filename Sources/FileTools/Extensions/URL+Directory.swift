//
//  URL+Directory.swift
//  FileTools
//
//  Whether the URL names a directory, per the file system (false when unreadable).
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

extension URL {
    /// Whether the URL names a directory, per the file system (false when unreadable).
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
