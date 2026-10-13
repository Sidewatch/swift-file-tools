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
    /// (`…/node_modules/mylib`), since every event carries the skipped component.
    public static func relevant(_ paths: some Sequence<String>, root: String, skipping skipped: Set<String>) -> Set<String> {
        var changed = Set<String>()
        for path in paths {
            let relative = path.hasPrefix(root) ? path.dropFirst(root.count) : Substring(path)
            guard !relative.split(separator: "/").contains(where: { skipped.contains(String($0)) }) else { continue }
            changed.insert(path)
        }
        return changed
    }
}
