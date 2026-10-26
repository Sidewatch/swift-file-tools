//
//  EventPaths.swift
//  FileTools
//
//  What a file-event batch means to a host that opened folders by name: paths renamed back under
//  the folders as they were opened, and only the paths a tree cares about.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Turns the paths a `DirectoryEventStream` reports into the paths a host's views hold.
public enum EventPaths {
    /// `paths` with every one under a root's REAL path renamed under the root as it was opened.
    /// FSEvents names a file by its real path (`/private/var/…`, a symlink's target) while a host's
    /// tree and tabs name it by the folder it was opened through; a root that is its own real path
    /// costs one `realpath` and changes nothing.
    public static func namedByOpenedRoots(_ paths: Set<String>, roots: [URL]) -> Set<String> {
        var out = paths
        for root in roots {
            let opened = root.path
            guard let real = root.realPath, real != opened else { continue }
            let realPrefix = real + "/"
            for path in paths where path == real || path.hasPrefix(realPrefix) {
                out.remove(path)
                out.insert(path == real ? opened : opened + "/" + path.dropFirst(realPrefix.count))
            }
        }
        return out
    }

    /// The paths a tree cares about: all but those under a skipped directory (`.git`,
    /// `node_modules`, …), tested only BELOW `root` (with its trailing slash) — testing the whole
    /// path would black out a root that itself lives inside a skipped folder
    /// (`…/node_modules/mylib`), since every event carries the skipped component. When `skipped` is
    /// not empty, a game engine's cache folder below `root` is skipped too (``EngineCaches``): a
    /// running Unity editor rewrites its `Library` without pause.
    public static func relevant(_ paths: some Sequence<String>, root: String, skipping skipped: Set<String>) -> Set<String> {
        var changed = Set<String>()
        var caches: [String: Bool] = [:]
        for path in paths {
            let below = path.hasPrefix(root)
            let relative = below ? path.dropFirst(root.count) : Substring(path)
            let parts = relative.split(separator: "/")
            guard !parts.contains(where: { skipped.contains(String($0)) }) else { continue }
            if !skipped.isEmpty, below, passesThroughCache(parts, under: root, known: &caches) { continue }
            changed.insert(path)
        }
        return changed
    }

    /// Whether a path, as its components below `root`, is or lies inside an engine's cache folder;
    /// each candidate folder is looked up on disk once per batch (`known`, by path).
    private static func passesThroughCache(_ parts: [Substring], under root: String, known: inout [String: Bool]) -> Bool {
        var folder = root.hasSuffix("/") ? String(root.dropLast()) : root
        for part in parts {
            folder += "/" + part
            guard EngineCaches.folderNames.contains(String(part)) else { continue }
            if let isCache = known[folder] {
                if isCache { return true }
                continue
            }
            let isCache = EngineCaches.isCache(URL(fileURLWithPath: folder))
            known[folder] = isCache
            if isCache { return true }
        }
        return false
    }
}
