# Swift File Tools

A small bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher. Pure Foundation, zero dependencies.

## Features

- 🌳 **ASCII tree** — `FileTree.ascii(of:maxDepth:maxEntries:)` renders a folder as a `tree`-style diagram, directories first, depth- and entry-bounded so a huge tree can't run away
- 🔍 **Project search** — `ProjectSearch.search(query:in:caseSensitive:regex:isCancelled:)` recursively finds text or regex matches, skipping oversized files, binaries, symlinks and special files, with per-file and total match caps
- 🕒 **Recent items** — `RecentItems.addFile` / `addFolder` / `files` / `folders`: a persistent, capped, most-recent-first list that drops paths no longer on disk
- 👀 **Directory watching** — `DirectoryEventStream` streams debounced FSEvents batches as `[Event]` of typed `FSEvent` kinds; `cancel()` is thread-safe and idempotent
- ✍️ **Replace All** — `ProjectSearch.replaceAll(query:in:caseSensitive:regex:replacement:commit:isCancelled:)` rewrites every match per line (the same matching as search), dry-run or commit, and a rewritten file keeps its own bytes: encoding (UTF-8 or Latin-1), UTF-8 byte-order mark and permission bits (`TextFileContents` + `FileRewrite`)
- 🏃 **Project scripts** — `ProjectScripts.detect(root:)` lists the runnable tasks in a project's manifests — `package.json` scripts (with the runner from the `packageManager` field, else the lockfile: npm/pnpm/yarn/bun), `composer.json` scripts (reserved lifecycle hooks filtered out), and `GNUmakefile`/`makefile`/`Makefile` targets — each as a `ProjectScript { name, command, source }`. Read-only: it reflects the project, it doesn't run anything
- 🖱️ **Terminal path references** — `TerminalPathParser.match(in:at:)` pulls `path:line:col` or `path(line,col)` out of a line of terminal output at a clicked column
- 🚫 **Noise-aware, and configurable** — both scanners honor the one `SkippedDirs.names` set (`.git`, `node_modules`, `.build`, `DerivedData`, …). Matching is by *name*, so the list is settable: a project with real sources in `dist/` can take it off the list, and `SkippedDirs.resetToDefault()` restores `SkippedDirs.defaultNames`
- 🪶 **Small** — Foundation plus swift-foundation-extensions (FoundationExtensions, ProcessRunner)
- **Ignore rules without walking** — `IgnoreMatcher(root:nestedRoots:)` answers "is this URL ignored?" for a file tree or an index that enumerates on its own: git's own answer inside a checkout (`GitIgnoredSet`, one `git ls-files` per root), the parser for a plain folder, and the `.ignore` / `.rgignore` / `.fdignore` stack on top. A checkout nested inside the root is judged by its own rules once the host names it (`setNestedRoots(_:)`), the way `git check-ignore` run in that checkout would; a lookup costs one set probe per path component, never a scan of the ignored directories
- 🧪 **Tested** — tree rendering, search caps/cancellation/symlink handling, replace fidelity (encoding, BOM, permissions), recents persistence, watcher lifecycle + flag mapping, manifest script detection (runner choice, reserved-hook filtering, Makefile heuristics), and the ignore parser against git itself (`IgnoreGitParityTests` writes pattern corpora into real repositories and compares the walk with `git ls-files`)

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

// Ask about single URLs without walking: a file tree dimming rows, an index enumerating
// on its own. Inside a checkout git itself answers; a plain folder's ignore files are parsed.
let matcher = IgnoreMatcher(root: projectURL)
matcher.isIgnored(url: projectURL.appendingPathComponent("build/out.o"), isDirectory: false)

// A checkout nested inside the project is its own git root once you name it: everything
// beneath it is judged by its own .gitignore, as `git check-ignore` run there would.
matcher.setNestedRoots([projectURL.appendingPathComponent("vendor/lib")])   // or IgnoreMatcher(root:nestedRoots:)
IgnoreRulesCache.warm(matcher.nestedRoots)   // optional: load their rules before the first question
```

## Notes

- `ProjectSearch.search` and `FileTree.ascii` are **synchronous** and do blocking file I/O — keep them off the main queue for large projects.
- Search caps: files over 2 MB are skipped, at most 200 matches per file and 5,000 in total.
- Two global switches shape the search walk, both meant to be set once at start-up from the host's preferences: `ProjectSearch.respectIgnoreFiles` (default on — `.gitignore` / `.ignore` / `.rgignore` / `.fdignore`, as ripgrep and fd) and `ProjectSearch.includeHiddenFiles` (default off — dot-files and dot-directories, ripgrep's `--hidden`). The name skip list applies on top of both.
- `IgnoreMatcher` without nested roots sees a nested checkout the way `git ls-files` reports it: one untracked directory, nothing beneath it ignored. Name the checkouts and each answers from its own rules; an outer `.gitignore` never reaches inside one (git's rule), while the `.ignore` stack flows down through it (ripgrep's). The search walk (`ProjectSearch`) still answers from the opened root alone.
- `SkippedDirs.names` is global mutable state read by both scanners. Set it once during start-up rather than mutating it concurrently with a walk; `FileTree.ascii` snapshots it per render.
- `DirectoryEventStream` callbacks may arrive on an unpredictable dispatch queue; hop to the main queue before touching UI. Unrecognized or coalesced FSEvents flags are surfaced as `.changeInDirectory` rather than dropped.
- `RecentItems` persists to `UserDefaults.standard` (caps: 15 files, 5 folders).

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT — see [LICENSE](LICENSE).
