//
//  DirectoryChildren.swift
//  FileTools
//
//  The children of a directory the way a listing shows them.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// The children of a directory the way a listing shows them.
enum DirectoryChildren {
    /// Visible entries of `directory`, minus `skipping` names, directories first, then
    /// case-insensitively by name. Empty when the directory cannot be read.
    static func sorted(in directory: URL, skipping: Set<String> = []) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { !skipping.contains($0.lastPathComponent) }.sorted { a, b in
            let ad = a.isDirectory, bd = b.isDirectory
            if ad != bd { return ad }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
    }
}
