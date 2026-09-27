//
//  FastDirectoryListing.swift
//  FileTools
//
//  A single directory listing, cheap enough to run on the main thread.
//
//  Created by David Sherlock on 8/1/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A single directory listing, cheap enough to run on the main thread.
///
/// `FileManager.contentsOfDirectory` with `.isDirectoryKey` costs a `getattrlist` per entry
/// (255 ms on a 10,068-file folder); `readdir`'s `d_type` gives the same answer in 5 ms.
/// `DT_LNK` and `DT_UNKNOWN` fall back to a `stat` for that entry, so symlinked directories
/// still expand and filesystems without `d_type` still work.
public enum FastDirectoryListing {

    /// One entry: its URL and whether it is a directory (symlinks resolved).
    public struct Entry: Sendable, Equatable {
        /// The entry's location.
        public let url: URL
        /// Whether it is, or links to, a directory.
        public let isDirectory: Bool
        /// Whether the entry itself is a symbolic link. `isDirectory` already says what it
        /// points at; a recursive walker needs this to stop at the link — a symlinked
        /// directory can point at an ancestor (a cycle) or at a tree outside the root.
        public let isSymbolicLink: Bool
        /// Lowercased name, precomputed as a sort key — a comparator that lowercases
        /// per comparison does it O(n log n) times instead of O(n).
        public let sortKey: String

        /// Creates an entry.
        public init(url: URL, isDirectory: Bool, isSymbolicLink: Bool = false, sortKey: String) {
            self.url = url
            self.isDirectory = isDirectory
            self.isSymbolicLink = isSymbolicLink
            self.sortKey = sortKey
        }
    }

    /// Lists `directory`, directories first then names in Finder order (`localizedStandardCompare`:
    /// case-insensitive and natural-numeric, so `file2` precedes `file10`). Names in `skipping`
    /// are dropped; empty when the directory can't be opened.
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

    /// Whether any entry of `directory` satisfies `predicate`: stops at the first hit and never
    /// sorts, so a gate ("does this folder hold a media file?") skips `list`'s ~100 ms sort.
    ///
    /// - Parameter predicate: `(name, isDirectory, isSymbolicLink)`, symlinks resolved as `list`
    ///   does; the link flag lets a caller agree with a listing that drops symlinks.
    public static func contains(in directory: URL,
                                includeHidden: Bool = false,
                                skipping: Set<String> = [],
                                where predicate: (_ name: String, _ isDirectory: Bool, _ isSymbolicLink: Bool) -> Bool) -> Bool {
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
            var isLink = false
            switch Int32(ent.d_type) {
            case DT_DIR: isDir = true
            case DT_REG: isDir = false
            default:
                let path = directory.appendingPathComponent(name).path
                var st = stat()
                isDir = stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
                var lst = stat()
                isLink = lstat(path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK
            }
            if predicate(name, isDir, isLink) { return true }
        }
        return false
    }
}
