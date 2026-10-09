//
//  FileRewrite.swift
//  FileTools
//
//  Replaces a file's bytes atomically while keeping the file's own permissions, group and
//  extended attributes, writing through a symbolic link to its target.
//
//  Created by David Sherlock on 9/18/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Replaces a file's bytes atomically while keeping the file's own permissions, group and
/// extended attributes.
///
/// `Data.write(to:options: .atomic)` drops every extended attribute (Finder tags,
/// `com.apple.TextEncoding`) and, on a hard-linked file, resets the mode (`755` becomes `644`).
/// `FileManager.replaceItemAt` keeps the mode but not every attribute (`com.apple.TextEncoding`
/// is lost) and gives the new file the staging folder's group, so both are put back by hand.
/// The path is resolved first: a write to a symbolic link lands on its target and the link
/// survives, where `replaceItemAt` on the link itself fails and `.atomic` would replace the link
/// with a file. Either way the result is a new inode, so another hard link to the old file keeps
/// the old bytes.
public enum FileRewrite {

    /// Extended attributes never carried onto the new file: the quarantine flag describes the
    /// download the old bytes were, not the bytes written now.
    static let droppedAttributes: Set<String> = ["com.apple.quarantine"]

    /// Writes `data` over `url`, atomically, keeping the existing file's permission bits, group
    /// and extended attributes (`com.apple.quarantine` excepted). A link is followed to its
    /// target; a link to nothing throws ``FileRewriteError/danglingSymbolicLink(_:)`` and an
    /// unwritable file ``FileRewriteError/fileNotWritable(_:)``. A path with nothing at it
    /// becomes a new file.
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard let target = try existingTarget(of: url) else {
            try data.write(to: url, options: .atomic)
            return
        }
        guard fm.isWritableFile(atPath: target.path) else { throw FileRewriteError.fileNotWritable(url) }
        let attributes = extendedAttributes(of: target)
        let group = groupID(of: target)
        let staging = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: target, create: true)
        let temporary = staging.appendingPathComponent(target.lastPathComponent)
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: temporary)
        _ = try fm.replaceItemAt(target, withItemAt: temporary)
        restore(attributes, on: target)
        restoreGroup(group, on: target)
    }

    /// The file a write to `url` lands on: `url` itself or, through a link, its target; nil when
    /// nothing exists there. A link whose target is gone is refused rather than overwritten.
    static func existingTarget(of url: URL) throws -> URL? {
        if let real = url.realPath { return URL(fileURLWithPath: real) }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw FileRewriteError.danglingSymbolicLink(url)
        }
        return nil
    }

    // MARK: - Extended attributes

    /// Every extended attribute of the file at `url` but the dropped ones, with its bytes.
    static func extendedAttributes(of url: URL) -> [(name: String, value: Data)] {
        attributeNames(of: url.path)
            .filter { !droppedAttributes.contains($0) }
            .compactMap { name in attributeValue(name, at: url.path).map { (name, $0) } }
    }

    /// The names `listxattr` reports, NUL-separated in its buffer.
    private static func attributeNames(of path: String) -> [String] {
        let length = listxattr(path, nil, 0, 0)
        guard length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(length))
        let read = listxattr(path, &buffer, buffer.count, 0)
        guard read > 0 else { return [] }
        return buffer[0..<Int(read)].split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }

    /// One attribute's bytes, or nil when it cannot be read.
    private static func attributeValue(_ name: String, at path: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        var data = Data(count: Int(size))
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, Int(size), 0, 0) }
        return read >= 0 ? data.prefix(Int(read)) : nil
    }

    /// Sets each attribute on the new file. Best effort: one the system refuses is left off.
    private static func restore(_ attributes: [(name: String, value: Data)], on url: URL) {
        for (name, value) in attributes {
            _ = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
        }
    }

    // MARK: - Group

    /// The file's group, or nil when it cannot be read.
    static func groupID(of url: URL) -> gid_t? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return info.st_gid
    }

    /// Puts the original group back when the new inode took the staging folder's. Best effort:
    /// a group the user does not belong to cannot be set and the write stands.
    private static func restoreGroup(_ group: gid_t?, on url: URL) {
        guard let group, groupID(of: url) != group else { return }
        _ = chown(url.path, uid_t.max, group)
    }
}
