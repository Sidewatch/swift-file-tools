//
//  RecentItems.swift
//  FileTools
//
//  A small "recent files" / "recent folders" list backed by a `UserDefaults`
//  store (`.standard` unless one is set). Paths that no longer exist on disk are
//  filtered out on read.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A persistent list of recently-opened files and folders.
///
/// Backed by ``defaults`` (`UserDefaults.standard` unless set), capped (15 files, 5 folders)
/// and most-recent-first. Reads drop paths that no longer exist on disk.
public enum RecentItems {
    /// The store the lists are read from and written to. `.standard` by default; a test run sets a
    /// scratch suite so the files it opens never reach the person's Open Recent.
    nonisolated(unsafe) public static var defaults: UserDefaults = .standard

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
        defaults.removeObject(forKey: filesKey)
        defaults.removeObject(forKey: foldersKey)
    }

    // MARK: - Internal

    /// Reads the stored path list for `key`, dropping paths that no longer
    /// exist on disk.
    private static func paths(for key: String) -> [String] {
        (defaults.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Moves `path` to the front of the stored list for `key`, deduplicating
    /// and trimming to `max` entries.
    private static func add(_ path: String, to key: String, max: Int) {
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > max { list = Array(list.prefix(max)) }
        defaults.set(list, forKey: key)
    }
}
