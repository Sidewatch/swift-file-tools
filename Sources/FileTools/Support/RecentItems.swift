//
//  RecentItems.swift
//  SwiftFileTools
//
//  A small "recent files" / "recent folders" list backed by
//  `UserDefaults.standard`. Paths that no longer exist on disk are filtered out
//  on read.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// A persistent list of recently-opened files and folders.
///
/// Backed by `UserDefaults.standard`, capped at a fixed number of entries, and
/// most-recent-first. Reads automatically drop paths that no longer exist on
/// disk.
///
/// ```swift
/// RecentItems.addFile(url)
/// let recent = RecentItems.files   // [URL], newest first
/// ```
public enum RecentItems {
    private static let filesKey = "RecentFiles"
    private static let foldersKey = "RecentFolders"
    private static let maxFiles = 15
    private static let maxFolders = 5

    // MARK: - Read

    /// The recently-opened files, newest first (missing paths filtered out).
    public static var files: [URL] {
        paths(for: filesKey).map { URL(fileURLWithPath: $0) }
    }

    /// The recently-opened folders, newest first (missing paths filtered out).
    public static var folders: [URL] {
        paths(for: foldersKey).map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Write

    /// Records `url` as the most recently-opened file, moving it to the front.
    public static func addFile(_ url: URL) {
        add(url.path, to: filesKey, max: maxFiles)
    }

    /// Records `url` as the most recently-opened folder, moving it to the front.
    public static func addFolder(_ url: URL) {
        add(url.path, to: foldersKey, max: maxFolders)
    }

    /// Clears both the recent-files and recent-folders lists.
    public static func clearAll() {
        UserDefaults.standard.removeObject(forKey: filesKey)
        UserDefaults.standard.removeObject(forKey: foldersKey)
    }

    // MARK: - Internal

    /// Reads the stored path list for `key`, dropping paths that no longer
    /// exist on disk.
    private static func paths(for key: String) -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Moves `path` to the front of the stored list for `key`, deduplicating
    /// and trimming to `max` entries.
    private static func add(_ path: String, to key: String, max: Int) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > max { list = Array(list.prefix(max)) }
        UserDefaults.standard.set(list, forKey: key)
    }
}
