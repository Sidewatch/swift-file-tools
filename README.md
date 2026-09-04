# Swift File Tools

A small bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher. Pure Foundation, zero dependencies.

## Features

- 🌳 **ASCII tree** — `FileTree.ascii(of:maxDepth:maxEntries:)` renders a folder as a `tree`-style diagram, directories first, depth- and entry-bounded so a huge tree can't run away
- 🔍 **Project search** — `ProjectSearch.search(query:in:caseSensitive:regex:isCancelled:)` recursively finds text or regex matches, skipping oversized files, binaries, symlinks and special files, with per-file and total match caps
- 🕒 **Recent items** — `RecentItems.addFile` / `addFolder` / `files` / `folders`: a persistent, capped, most-recent-first list that drops paths no longer on disk
- 👀 **Directory watching** — `DirectoryEventStream` streams debounced FSEvents batches as `[Event]` of typed `FSEvent` kinds; `cancel()` is thread-safe and idempotent
- 🏃 **Project scripts** — `ProjectScripts.detect(root:)` lists the runnable tasks in a project's manifests — `package.json` scripts (with the runner picked from the lockfile: npm/pnpm/yarn/bun), `composer.json` scripts (reserved lifecycle hooks filtered out), and `Makefile` targets — each as a `ProjectScript { name, command, source }`. Read-only: it reflects the project, it doesn't run anything
- 🚫 **Noise-aware, and configurable** — both scanners honor the one `SkippedDirs.names` set (`.git`, `node_modules`, `.build`, `DerivedData`, …). Matching is by *name*, so the list is settable: a project with real sources in `dist/` can take it off the list, and `SkippedDirs.resetToDefault()` restores `SkippedDirs.defaultNames`
- 🪶 **Zero dependencies** — Foundation only
- 🧪 **Tested** — tree rendering, search caps/cancellation/symlink handling, recents persistence, watcher lifecycle + flag mapping, and manifest script detection (runner choice, reserved-hook filtering, Makefile heuristics)

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)

> **Platform note:** `DirectoryEventStream` wraps the FSEvents/CoreServices API, so the package is macOS-only.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-file-tools.git", from: "0.1.0")
]
```

## Usage

```swift
import FileTools

// Render a project as an ASCII tree (bounded: default maxDepth 8, maxEntries 800).
print(FileTree.ascii(of: projectURL))
// MyApp/
// ├── Sources/
// │   └── main.swift
// └── README.md

// Search the project for a query. Runs synchronously — dispatch it to a
// background queue yourself, and use `isCancelled` to stop early.
let hits = ProjectSearch.search(query: "TODO", in: projectURL,
                                caseSensitive: false, regex: false,
                                isCancelled: { false })
for file in hits {                    // [SearchFileResult], sorted by path
    for match in file.matches {       // [SearchMatch]
        print("\(file.url.lastPathComponent):\(match.line): \(match.lineText)")
    }
}

// Track recently-opened files and folders.
RecentItems.addFile(fileURL)
RecentItems.addFolder(folderURL)
let recent = RecentItems.files        // [URL], newest first, missing paths dropped
RecentItems.clearAll()

// Watch a directory for changes. The stream starts immediately; events arrive
// batched every `debounceDuration` (default 0.1 s), on no particular queue.
let watcher = DirectoryEventStream(directory: projectURL.path) { events in
    for event in events {
        print(event.eventType, event.path)   // e.g. itemModified /path/to/file
    }
}
watcher.cancel()   // thread-safe, idempotent; also runs on deinit

// Reuse the shared noise-directory set in your own scanners.
if SkippedDirs.names.contains(url.lastPathComponent) { /* skip it */ }

// Override it — this project keeps real sources in dist/, so stop hiding them.
SkippedDirs.names = SkippedDirs.defaultNames.subtracting(["dist"])
SkippedDirs.resetToDefault()   // back to the shipped list
```

## Notes

- `ProjectSearch.search` and `FileTree.ascii` are **synchronous** and do blocking file I/O — keep them off the main queue for large projects.
- Search caps: files over 2 MB are skipped, at most 200 matches per file and 5,000 in total.
- `SkippedDirs.names` is global mutable state read by both scanners. Set it once during start-up rather than mutating it concurrently with a walk; `FileTree.ascii` snapshots it per render.
- `DirectoryEventStream` callbacks may arrive on an unpredictable dispatch queue; hop to the main queue before touching UI. Unrecognized or coalesced FSEvents flags are surfaced as `.changeInDirectory` rather than dropped.
- `RecentItems` persists to `UserDefaults.standard` (caps: 15 files, 5 folders).

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT
