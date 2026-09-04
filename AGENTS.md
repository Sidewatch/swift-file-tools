# Swift File Tools

A small bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher. Pure Foundation, zero dependencies.

- Module `FileTools` in `Sources/FileTools`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Extensions/` — URL.isDirectory
- `Enums/` — enums with no behaviour beyond their cases and labels: FSEvent
- `Ignore/` — the engine: ignore: GitIgnoredSet, IgnoreFile, IgnoreFileNames, IgnoreMatcher, IgnorePattern, IgnoreRules, IgnoreRulesCache, IgnoreStack
- `Listing/` — the engine: listing: FastDirectoryListing, FileTree, SkippedDirs
- `Models/` — value types — the shape of a thing, nothing else: ReplaceSummary, SearchFileResult, SearchMatch
- `Search/` — the engine: search: ProjectSearch
- `Support/` — pure helpers: parsing, escaping, validation: DirectoryChildren, ProjectScripts, RecentItems, TerminalPathParser
- `Watching/` — the engine: watching: DirectoryEventStream, DiskStormDetector

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.
