//
//  LocalHistory.swift
//  FileTools
//
//  Kept versions of files on save — VS Code's local history, the rules ported.
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import CryptoKit
import Foundation

/// Versions of files kept on save, outside git, ported from VS Code's local history
/// (`workingCopyHistoryService.ts`). Each file gets a folder under `root` (blobs plus an
/// `entries.json` index); a save within `mergeWindow` of the last same-source entry REPLACES it;
/// only the newest `maxEntries` are kept; files over `maxFileSize` and saves identical to the
/// last version are not recorded. No clock of its own: every write takes `at:`.
public struct LocalHistory: Sendable {
    /// The folder that holds every file's history folder.
    public let root: URL
    /// How many versions of one file are kept; older blobs are deleted.
    public var maxEntries: Int
    /// Seconds within which a save from the same source replaces the last entry.
    public var mergeWindow: TimeInterval
    /// The largest file, in bytes, that is kept at all.
    public var maxFileSize: Int

    /// The source recorded for an ordinary save.
    public static let fileSavedSource = "File Saved"

    /// A history stored under `root`; the defaults are VS Code's.
    public init(root: URL, maxEntries: Int = 50, mergeWindow: TimeInterval = 10, maxFileSize: Int = 256 * 1024) {
        self.root = root
        self.maxEntries = maxEntries
        self.mergeWindow = mergeWindow
        self.maxFileSize = maxFileSize
    }

    // MARK: - Where

    /// The file's history folder: `root/<first 16 hex of SHA-256 of the standardized path>`.
    /// Stable across launches and instances, so a file's versions are always found again.
    public func folder(for file: URL) -> URL {
        let key = file.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }

    private func indexURL(for file: URL) -> URL { folder(for: file).appendingPathComponent("entries.json") }

    /// The `entries.json` index of one file's history folder.
    private struct Index: Codable {
        var path: String
        var entries: [LocalHistoryEntry]
    }

    // MARK: - Read

    /// The kept versions, oldest first.
    public func entries(for file: URL) -> [LocalHistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL(for: file)),
            let index = try? JSONDecoder().decode(Index.self, from: data)
        else { return [] }
        return index.entries
    }

    /// A kept version's bytes.
    public func data(of entry: LocalHistoryEntry, for file: URL) -> Data? {
        try? Data(contentsOf: folder(for: file).appendingPathComponent(entry.id))
    }

    // MARK: - Write

    /// Keeps `data` as a version of `file`. Returns the entry, or nil when nothing was kept:
    /// the file is over `maxFileSize`, or the bytes equal the last kept version.
    @discardableResult
    public func record(_ data: Data, for file: URL, source: String = LocalHistory.fileSavedSource, at time: Date = Date()) throws
        -> LocalHistoryEntry?
    {
        guard data.count <= maxFileSize else { return nil }
        let dir = folder(for: file)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var index =
            (try? JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL(for: file))))
            ?? Index(path: file.standardizedFileURL.path, entries: [])
        if let last = index.entries.last, last.byteCount == data.count, self.data(of: last, for: file) == data {
            return nil  // an unchanged save is not a new version
        }
        let id =
            "\(Int(time.timeIntervalSince1970 * 1000))-\(String(UInt32.random(in: 0...0xffff), radix: 16))"
            + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension)
        try data.write(to: dir.appendingPathComponent(id), options: .atomic)
        let entry = LocalHistoryEntry(id: id, timestamp: time, source: source, byteCount: data.count)
        if let last = index.entries.last, last.source == source, time.timeIntervalSince(last.timestamp) <= mergeWindow,
            time >= last.timestamp
        {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(last.id))
            index.entries[index.entries.count - 1] = entry
        } else {
            index.entries.append(entry)
        }
        while index.entries.count > maxEntries {
            let dropped = index.entries.removeFirst()
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(dropped.id))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(index).write(to: indexURL(for: file), options: .atomic)
        return entry
    }

    /// Forgets every version of `file`.
    public func clear(for file: URL) {
        try? FileManager.default.removeItem(at: folder(for: file))
    }
}
