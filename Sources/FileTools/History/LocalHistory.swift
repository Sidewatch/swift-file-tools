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
/// last version are not recorded; the whole store stays within `maxTotalSize` when the host
/// calls ``trimToTotalSize()``. No clock of its own: every write takes `at:`.
public struct LocalHistory: Sendable {
    /// The folder that holds every file's history folder.
    public let root: URL
    /// How many versions of one file are kept; older blobs are deleted.
    public var maxEntries: Int
    /// Seconds within which a save from the same source replaces the last entry.
    public var mergeWindow: TimeInterval
    /// The largest file, in bytes, that is kept at all.
    public var maxFileSize: Int
    /// The most the whole store holds, in bytes, across every file; ``trimToTotalSize()`` drops
    /// the oldest versions first until it fits.
    public var maxTotalSize: Int

    /// The source recorded for an ordinary save.
    public static let fileSavedSource = "File Saved"

    /// The store's default ceiling: 256 MB.
    public static let defaultMaxTotalSize = 256 * 1024 * 1024

    /// A history stored under `root`; the defaults are VS Code's, the ceiling this package's.
    public init(
        root: URL, maxEntries: Int = 50, mergeWindow: TimeInterval = 10, maxFileSize: Int = 256 * 1024,
        maxTotalSize: Int = LocalHistory.defaultMaxTotalSize
    ) {
        self.root = root
        self.maxEntries = maxEntries
        self.mergeWindow = mergeWindow
        self.maxFileSize = maxFileSize
        self.maxTotalSize = maxTotalSize
    }

    // MARK: - Where

    /// The file's history folder: `root/<first 16 hex of SHA-256 of the standardized path>`.
    /// Stable across launches and instances, so a file's versions are always found again.
    public func folder(for file: URL) -> URL {
        let key = file.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }

    private static let indexName = "entries.json"

    /// The `entries.json` index of one file's history folder.
    private struct Index: Codable {
        var path: String
        var entries: [LocalHistoryEntry]
    }

    /// The index in `folder`, or nil when there is none.
    private func readIndex(in folder: URL) -> Index? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.indexName)) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

    /// Writes `index` into `folder`; a folder left with no versions is removed whole.
    private func write(_ index: Index, in folder: URL) throws {
        guard !index.entries.isEmpty else {
            try? FileManager.default.removeItem(at: folder)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(index).write(to: folder.appendingPathComponent(Self.indexName), options: .atomic)
    }

    // MARK: - Read

    /// The kept versions, oldest first.
    public func entries(for file: URL) -> [LocalHistoryEntry] {
        readIndex(in: folder(for: file))?.entries ?? []
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
        var index = readIndex(in: dir) ?? Index(path: file.standardizedFileURL.path, entries: [])
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
        try write(index, in: dir)
        return entry
    }

    /// Forgets every version of `file`.
    public func clear(for file: URL) {
        try? FileManager.default.removeItem(at: folder(for: file))
    }

    // MARK: - Move

    /// A file renamed or moved keeps its versions: what was kept for `old` is kept for `new`.
    /// Versions `new` already had stay too, in time order, the newest `maxEntries` of them all.
    public func move(from old: URL, to new: URL) throws {
        let source = folder(for: old), destination = folder(for: new)
        guard source != destination, let moving = readIndex(in: source) else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var merged = readIndex(in: destination) ?? Index(path: new.standardizedFileURL.path, entries: [])
        merged.path = new.standardizedFileURL.path
        for entry in moving.entries {
            let blob = destination.appendingPathComponent(entry.id)
            guard !fm.fileExists(atPath: blob.path) else { continue }
            try fm.moveItem(at: source.appendingPathComponent(entry.id), to: blob)
            merged.entries.append(entry)
        }
        merged.entries.sort { $0.timestamp < $1.timestamp }
        while merged.entries.count > maxEntries {
            let dropped = merged.entries.removeFirst()
            try? fm.removeItem(at: destination.appendingPathComponent(dropped.id))
        }
        try write(merged, in: destination)
        try? fm.removeItem(at: source)
    }

    // MARK: - Bound the store

    /// Drops the oldest versions across every file until the store is within `maxTotalSize`;
    /// returns how many were dropped. It reads every file's index, so a host calls it at launch
    /// or now and then, never on each save.
    @discardableResult
    public func trimToTotalSize() -> Int {
        var folders = indexedFolders()
        var total = folders.reduce(0) { $0 + $1.index.entries.reduce(0) { $0 + $1.byteCount } }
        guard total > maxTotalSize else { return 0 }
        let oldestFirst = folders.indices
            .flatMap { i in folders[i].index.entries.map { (folder: i, entry: $0) } }
            .sorted { $0.entry.timestamp < $1.entry.timestamp }
        var touched = Set<Int>()
        var dropped = 0
        for item in oldestFirst where total > maxTotalSize {
            try? FileManager.default.removeItem(at: folders[item.folder].url.appendingPathComponent(item.entry.id))
            folders[item.folder].index.entries.removeAll { $0.id == item.entry.id }
            total -= item.entry.byteCount
            dropped += 1
            touched.insert(item.folder)
        }
        for i in touched { try? write(folders[i].index, in: folders[i].url) }
        return dropped
    }

    /// Every file's history folder under `root` with its index.
    private func indexedFolders() -> [(url: URL, index: Index)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { name in
            let url = root.appendingPathComponent(name, isDirectory: true)
            return readIndex(in: url).map { (url, $0) }
        }
    }
}
