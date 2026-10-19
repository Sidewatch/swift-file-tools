# Swift File Tools

A small bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher. Pure Foundation, zero dependencies.

- Module `FileTools` in `Sources/FileTools`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Extensions/` — Data.utf8String, URL.isDirectory
- `Enums/` — enums with no behaviour beyond their cases and labels: FSEvent
- `Errors/` — every Error type, one per file: FileRewriteError, ProjectFolderError
- `Ignore/` — the engine: ignore: GitIgnoredSet, IgnoreFile, IgnoreFileNames, IgnoreMatcher, IgnoreMatcherCache, IgnorePattern, IgnoreRules, IgnoreRulesCache, IgnoreStack
- `Library/` — the engine: library: FileLibrary (global + per-project folder of one file kind)
- `Listing/` — the engine: listing: FastDirectoryListing, FileTree, SkippedDirs
- `Models/` — value types — the shape of a thing, nothing else: ReplaceSummary, SearchFileResult, SearchMatch, TextFileContents (+ TextFileEncoding: UTF-8, Latin-1, UTF-16 LE/BE)
- `Search/` — the engine: search: ProjectSearch, SearchStreamBuffer (batches a walk's results for the main thread)
- `Support/` — pure helpers: parsing, escaping, validation: DirectoryChildren, FileNaming (`base`, `base 2`, … free in a folder), FileRewrite (through links; mode, group, xattrs kept), JSONObject, ProjectFolder (a new project's folder: created, or an existing empty one accepted; never a folder with files), ProjectScripts (a script's name is quoted as one shell argument unless it is plain), RecentItems, TerminalPathParser, FileLocationLink (an app's `scheme://open?path=&line=` link; absolute paths to files only, a trailing `:line:col` split by TerminalPathParser)
- `Watching/` — the engine: watching: DirectoryEventStream, DiskStormDetector, EventPaths (an event batch renamed back under folders opened through a symlink, and the skip filter)

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
