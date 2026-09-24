//
//  FastDirectoryListing.swift
//  FileTools
//
//  A single directory listing, cheap enough to run on the main thread.
//
//  Created by David Sherlock on 8/1/26.
//

import Foundation

/// A single directory listing, cheap enough to run on the main thread.
///
/// `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` prefetching
/// `.isDirectoryKey` costs a `getattrlist` per entry: on a real 10,068-file folder
/// that measured **255 ms**, which is a visible hang when it happens on an outline
/// view's expand. `readdir` reports the entry type in `d_type` as part of the same
/// pass it already makes, so the same listing takes **5 ms** — a 50× difference for
/// identical output. That's the whole reason this exists.
///
/// - Note: The fast path is only taken when `d_type` is conclusive. `DT_LNK` and
///   `DT_UNKNOWN` fall back to a `stat` for that one entry, so symlinked
///   directories still report as directories (`node_modules/.bin` and pnpm's store
///   are full of them, and getting it wrong would make them un-expandable) and
///   filesystems that don't populate `d_type` still work.
public enum FastDirectoryListing {

    /// One entry: its URL and whether it is a directory (symlinks resolved).
    public struct Entry: Sendable, Equatable {
        public let url: URL
        public let isDirectory: Bool
        /// Whether the entry itself is a symbolic link. `isDirectory` already says what it
        /// points at; a recursive walker needs this to stop at the link — a symlinked
        /// directory can point at an ancestor (a cycle) or at a tree outside the root.
        public let isSymbolicLink: Bool
        /// Lowercased name, precomputed as a sort key — a comparator that lowercases
        /// per comparison does it O(n log n) times instead of O(n).
        public let sortKey: String

        public init(url: URL, isDirectory: Bool, isSymbolicLink: Bool = false, sortKey: String) {
            self.url = url
            self.isDirectory = isDirectory
            self.isSymbolicLink = isSymbolicLink
            self.sortKey = sortKey
        }
    }

    /// Lists `directory`, directories first then names in Finder order.
    ///
    /// Finder order means `localizedStandardCompare`: case-insensitive *and*
    /// natural-numeric, so `file2` sorts before `file10`. A plain `<` would be
    /// faster still but gets both wrong.
    ///
    /// - Parameters:
    ///   - directory: the folder to list.
    ///   - includeHidden: include dot-files.
    ///   - skipping: names to drop entirely (e.g. `node_modules`, `.git`).
    /// - Returns: the sorted entries, or `[]` if the directory can't be opened.
    public static func list(_ directory: URL,
                            includeHidden: Bool = false,
                            skipping: Set<String> = []) -> [Entry] {
        guard let dir = opendir(directory.path) else { return [] }
        defer { closedir(dir) }

        var out: [Entry] = []
        out.reserveCapacity(64)

        while let raw = readdir(dir) {
            var ent = raw.pointee
            let name = withUnsafePointer(to: &ent.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }
            if !includeHidden, name.hasPrefix(".") { continue }
            if skipping.contains(name) { continue }

            let url = directory.appendingPathComponent(name)
            let isDir: Bool
            var isLink = false
            switch Int32(ent.d_type) {
            case DT_DIR: isDir = true
            case DT_REG: isDir = false
            default:
                // DT_LNK / DT_UNKNOWN — `stat` follows symlinks, which is what an
                // outline view wants: a link to a folder should expand. `lstat` says
                // whether the entry is the link itself, for walkers that must not follow.
                var st = stat()
                isDir = stat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
                var lst = stat()
                isLink = lstat(url.path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK
            }
            out.append(Entry(url: url, isDirectory: isDir, isSymbolicLink: isLink, sortKey: name.lowercased()))
        }

        return out.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
        }
    }

    /// Whether any entry of `directory` satisfies `predicate` — a yes/no scan that stops at
    /// the first hit and never sorts. `list` pays a `localizedStandardCompare` sort, ~100 ms
    /// on ten thousand entries, which a gate ("does this folder hold a media file?") does not
    /// need; this answers the same folder in a few milliseconds, and the FIRST hit in a
    /// folder of photos in microseconds. The predicate sees the entry's name and whether it
    /// is a directory (symlinks resolved, as `list` does).
    ///
    /// - Parameters:
    ///   - directory: the folder to scan.
    ///   - includeHidden: include dot-files.
    ///   - skipping: names to drop entirely.
    ///   - predicate: `(name, isDirectory)`; return true to stop with a yes.
    /// - Returns: true on the first entry the predicate accepts; false otherwise, or if the
    ///   directory can't be opened.
    public static func contains(in directory: URL,
                                includeHidden: Bool = false,
                                skipping: Set<String> = [],
                                where predicate: (_ name: String, _ isDirectory: Bool) -> Bool) -> Bool {
        guard let dir = opendir(directory.path) else { return false }
        defer { closedir(dir) }
        while let raw = readdir(dir) {
            var ent = raw.pointee
            let name = withUnsafePointer(to: &ent.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }
            if !includeHidden, name.hasPrefix(".") { continue }
            if skipping.contains(name) { continue }
            let isDir: Bool
            switch Int32(ent.d_type) {
            case DT_DIR: isDir = true
            case DT_REG: isDir = false
            default:
                var st = stat()
                isDir = stat(directory.appendingPathComponent(name).path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
            }
            if predicate(name, isDir) { return true }
        }
        return false
    }
}
