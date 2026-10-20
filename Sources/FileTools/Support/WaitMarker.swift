//
//  WaitMarker.swift
//  FileTools
//
//  The `--wait` handshake between a command-line wrapper and its app: an empty file the wrapper
//  waits on and the app deletes when the file it opened is closed.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The `--wait` handshake, the shape of VS Code's wait marker: the wrapper makes an empty file in
/// the per-user temporary folder (`getconf DARWIN_USER_TEMP_DIR`), names it in the link's `wait`
/// item and blocks while it exists; the app deletes it once the file is no longer open. That is
/// what lets the app stand in as `$EDITOR` for git or an agent's "edit in your editor".
///
/// The link reaches the app from any page or app, and the app DELETES what it names, so a marker
/// is accepted only straight inside the given folder (compared by real path, so `..` and links
/// cannot leave it), under the given name prefix, as a regular file this user owns.
public enum WaitMarker {
    /// The query item a link carries the marker's path in.
    public static let queryItem = "wait"

    /// The marker `url`'s `wait` item names, when ``accept(_:directory:prefix:)`` takes it.
    public static func marker(in url: URL, directory: String, prefix: String) -> URL? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let path = items.first(where: { $0.name == queryItem })?.value
        else { return nil }
        return accept(path, directory: directory, prefix: prefix)
    }

    /// `path` as a marker the app may delete: absolute, without a NUL, directly inside
    /// `directory`, named `prefix…`, and a regular file (not a link) owned by this user. Nil
    /// otherwise.
    public static func accept(_ path: String, directory: String, prefix: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent.hasPrefix(prefix), url.lastPathComponent.count > prefix.count,
            let parent = url.deletingLastPathComponent().realPath,
            parent == URL(fileURLWithPath: directory).realPath
        else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else { return nil }
        return url
    }

    /// Deletes `marker`, which ends the wrapper's wait; true when it was there to delete. A path
    /// that has since become anything but a regular file is left alone.
    @discardableResult
    public static func release(_ marker: URL) -> Bool {
        var info = stat()
        guard lstat(marker.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        return unlink(marker.path) == 0
    }
}
