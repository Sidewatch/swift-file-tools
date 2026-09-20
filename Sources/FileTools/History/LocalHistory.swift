//
//  LocalHistory.swift
//  FileTools
//
//  Kept versions of files on save — VS Code's local history, the rules ported.
//
//  Created by David Sherlock on 9/20/26.
//

import CryptoKit
import Foundation

/// Versions of files kept on save, outside git — what a file looked like before the agent, or
/// you, touched it, even when nothing was committed. VS Code's local history
/// (`workingCopyHistoryService.ts`), the rules ported:
///
/// - each file has a folder under `root`, named by a hash of its path, holding the blobs and an
///   `entries.json` index;
/// - a save within `mergeWindow` of the last entry from the same source REPLACES that entry
///   (ten quick ⌘S presses are one version), otherwise it adds one;
/// - only the newest `maxEntries` are kept, older blobs deleted;
/// - a file over `maxFileSize` is not kept at all;
/// - and, ours: a save whose bytes equal the last kept version records nothing — no fact changed.
///
/// Pure file-system logic with no clock of its own: every write takes `at:`, so the tests can
/// place saves in time.
public struct LocalHistory: Sendable {
    public let root: URL
    public var maxEntries: Int
    public var mergeWindow: TimeInterval
    public var maxFileSize: Int

    public static let fileSavedSource = "File Saved"

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

    private struct Index: Codable {
        var path: String
        var entries: [LocalHistoryEntry]
    }

    // MARK: - Read

    /// The kept versions, oldest first.
    public func entries(for file: URL) -> [LocalHistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL(for: file)),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return [] }
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
    public func record(_ data: Data, for file: URL, source: String = LocalHistory.fileSavedSource, at time: Date = Date()) throws -> LocalHistoryEntry? {
        guard data.count <= maxFileSize else { return nil }
        let dir = folder(for: file)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var index = (try? JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL(for: file))))
            ?? Index(path: file.standardizedFileURL.path, entries: [])
        if let last = index.entries.last, last.byteCount == data.count, self.data(of: last, for: file) == data {
            return nil   // an unchanged save is not a new version
        }
        let id = "\(Int(time.timeIntervalSince1970 * 1000))-\(String(UInt32.random(in: 0...0xffff), radix: 16))" + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension)
        try data.write(to: dir.appendingPathComponent(id), options: .atomic)
        let entry = LocalHistoryEntry(id: id, timestamp: time, source: source, byteCount: data.count)
        if let last = index.entries.last, last.source == source, time.timeIntervalSince(last.timestamp) <= mergeWindow, time >= last.timestamp {
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
