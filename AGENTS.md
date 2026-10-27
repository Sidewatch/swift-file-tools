# Swift File Tools

A small bundle of macOS file utilities for tooling and code-review UIs — an ASCII project-tree renderer, a fast recursive project-wide text search, a `UserDefaults`-backed recent-files list, and a self-contained FSEvents directory watcher. Pure Foundation, zero dependencies.

- Module `FileTools` in `Sources/FileTools`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Extensions/` — Data.utf8String, URL.isDirectory, LocalHistoryDiskBatch+Merge (a later batch folded into a waiting one: the EARLIER before wins, 1,000 paths at most)
- `Enums/` — enums with no behaviour beyond their cases and labels: FSEvent
- `Errors/` — every Error type, one per file: FileRewriteError, ProjectFolderError
- `History/` — the engine: local history: LocalHistory (versions per file, merge window, size trim), LocalHistory+Disk (`recordFromDisk`: a bounded pass, a first sighting's "before"), LocalHistory+DiskBatch (`recordDiskBatch`: what an outside change keeps — `.git` and ignored paths out, git asked NOW for brand-new files, the before from a captured buffer else `HEAD`, roots matched through links), LocalHistoryEntry
- `Ignore/` — the engine: ignore (`IgnoreMatcher.reason`: git's `check-ignore -v`, literal pathspecs off for that one call since check-ignore refuses them; a folder git calls ignored only because everything inside is has no reason): GitIgnoredSet, IgnoreFile, IgnoreFileNames, IgnoreMatcher, IgnoreMatcherCache, IgnorePattern, IgnoreRules, IgnoreRulesCache, IgnoreStack
- `Library/` — the engine: library: FileLibrary (global + per-project folder of one file kind)
- `Internal/` — UTF8OffsetWalker (UTF-16 offsets in repaired UTF-8 text back to byte offsets: one U+FFFD per maximal invalid piece, as the decoder makes it), RootSpellings (a root under its given and real path; the deepest root holding a path, by name then by the path's real path)
- `LargeText/` — the engine: text files of any size. LargeTextFile (`pread`, never a mapping; a background line scan into a sparse checkpoint index, long lines recorded; a line still being read is not counted; `grew()` / `isTruncated` for a growing or rotated log; `lineStart(atOrBefore:within:)` without the scan), LargeTextMatcher (a literal over raw bytes, Horspool, ASCII folding — a case-insensitive literal beyond ASCII goes the regex way; a regex over a block of whole lines, offsets mapped back through `UTF8OffsetWalker`; never an empty match or one across a break), LargeTextSearch (next / previous wrapping, `matches(_:in:within:)` for a screenful, `count` by block and `index(of:)` from it — it NEVER holds every match: the reads are 8 MB blocks cut at a line break)
- `Listing/` — the engine: listing: FastDirectoryListing, FileTree, SkippedDirs, EngineCaches (Unity's `Library`/`Temp`/`obj` beside `Assets` and `ProjectSettings`, Unreal's `Intermediate`/`DerivedDataCache` beside a `.uproject`/`.uplugin`, Godot's `.godot`/`.import` beside `project.godot`: skipped by every listing and the event filter that skip `SkippedDirs`, and `isCache(_:)` for a walker in another package)
- `Models/` — value types — the shape of a thing, nothing else: IgnoreReason (the rule that ignores a path: file, line, pattern), LargeTextProgress, LargeTextMatchCount, LocalHistoryDiskBatch, LocalHistoryDiskRecord, ReplaceSummary, SearchFileResult, SearchMatch, TextFileContents (+ TextFileEncoding: UTF-8, Windows-1252 then Latin-1 for non-UTF-8 bytes, UTF-16 LE/BE; `hasBinaryPrefix` and `hasLine(atLeast:in:)` answer from the bytes before any decoding)
- `Search/` — the engine: search: ProjectSearch (+Stream: `stream` — the first file at once, then at most every interval, then exactly one final batch), SearchStreamBuffer (batches a walk's results for the main thread), ExcerptWindows (`runs(around:context:lineCount:)`: context windows around matched lines, touching ones merged, lines a shrunken file no longer has ignored)
- `Support/` — pure helpers: parsing, escaping, validation: GitCheckIgnoreOutput, DirectoryChildren, FileNaming (`base`, `base 2`, … free in a folder; +Copies: Finder's `name copy`, `name copy 2` … with a dangling link counted as taken, `isValidName`, `isCaseOnlyRename`), FileRewrite (through links; mode, group, xattrs kept), JSONObject, ProjectFolder (a new project's folder: created, or an existing empty one accepted; never a folder with files), ProjectScripts (a script's name is quoted as one shell argument unless it is plain), RecentItems (its store is `defaults`, `.standard` unless a test run sets a scratch suite), TerminalPathParser, FileLocationLink (an app's `scheme://open?path=&line=` link; absolute paths to files only, a trailing `:line:col` split by TerminalPathParser), FileComparisonLink (`scheme://diff?old=&new=`, absolute paths only), WaitMarker + WaitingFiles (the `--wait` handshake: a marker file in the user's temp folder the app deletes when the file closes; accepted only straight inside that folder, under a prefix, as a regular file of this user's)
- `Watching/` — the engine: watching: DirectoryEventStream (its callback is `@Sendable`: it runs on the stream's own queue, and a non-Sendable one written in a host's main-actor code would carry the main actor there and trap), DiskStormDetector, EventPaths (an event batch renamed back under folders opened through a symlink, and the skip filter)

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
