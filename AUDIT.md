# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift). **Line-by-line logic review of the whole library: 18 Sep 2026** (section below). Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line; git as the oracle)

Fixed, each pinned by a test that fails against the old code:

- **`replaceAll` dropped the byte-order mark, every extended attribute, and a hard-linked file's
  executable bit.** `String(data:encoding:)` strips a UTF-8 BOM, so the rewrite never put it back.
  `Data.write(.atomic)` renames a fresh file over the original and, measured on macOS 26, loses the
  xattrs (Finder tags and comments) every time and the permission bits when the file has a second hard
  link (`755` → `644`; a plain file keeps its mode — the first measurement had a hard link, which is
  why the claim was briefly "every script"). `FileRewrite.write` replaces through
  `FileManager.replaceItemAt` (mode and xattrs kept in every case) and `TextFileContents` /
  `TextFileEncoding` carry the BOM and encoding back out. `readTextFile` now returns
  `TextFileContents`; the app's targeted replace and `Document.save` go through the same two.
- **`IgnorePattern` had no POSIX bracket classes** — `[[:alpha:]]*.log` parsed as an ordinary class
  of `[`, `:`, `a`… followed by a literal `]`. Found by `IgnoreGitParityTests`: ten pattern corpora
  written into real repositories, the parser-driven walk compared with `git ls-files --others
  --exclude-standard`. All ten agree now.
- **`ProjectScripts`**: Bun's text `bun.lock` (1.2+) was not a Bun signal; the `packageManager`
  field was ignored; only `Makefile` was read (not `GNUmakefile` / `makefile`); an `a b: dep` line
  declared no targets.
- **`TerminalPathParser`**: `path(line,col)` — tsc, MSBuild, csc — was not a reference, and the
  parentheses are token boundaries, so a click on either side gave a bare path or bare digits.

Reviewed and sound: the search/replace line model (`enumerateLines` and `.byLines` agree on
terminators; the reassembly tiles the file), the regex pre-filter's over-admit-only contract, the
dry-run == commit invariant, the walk's symlink and size handling, `FastDirectoryListing`'s d_type
fallbacks, `DirectoryEventStream`'s weak-box lifetime and re-entrant `cancel()`,
`DiskStormDetector`'s buckets and folder election, `GitIgnoredSet`'s pipes and timeout,
`IgnoreMatcher`'s ancestor walk and generation check, `FileLibrary`, `RecentItems`.

## Known non-issues (do not "fix" these again)

- **Ignore matching is case-sensitive, and git on this Mac is not.** `git init` on a case-insensitive
  volume sets `core.ignorecase`, which folds case in ignore matching too (`README` ignores `readme`).
  The parser follows ripgrep, fd and git on Linux. Inside a checkout git itself answers, so the
  difference reaches only a plain folder's `.gitignore`; the parity test asks git with the option off.
- **Hidden files are search candidates only with `ProjectSearch.includeHiddenFiles` on** (default off:
  ripgrep and fd without `--hidden`). A host whose tree shows dot-files sets it from that toggle. The
  name skip list and the ignore files apply on top either way, and the ignore files themselves become
  candidates once the flag is on — pinned by `testHiddenFilesFollowTheFlagWhileTheSkipListAndIgnoreRulesStillApply`.
- **A nested repository's own `.gitignore` is not applied by the search walk** when the outer
  folder is a checkout (git's `ls-files` stops at nested repos, and `.gitignore` parsing is off
  while git answers). Its `node_modules` / `build` / `vendor` still fall to the skip list.
  `IgnoreMatcher` does apply it once the host names the nested roots (9 Oct 2026, below); the
  walk would need the same root switch mid-descent, not done.
- **An outer `.gitignore` parsed by the matcher for a plain (non-checkout) root still applies
  inside a nested checkout** through the inherited stack. Git would not read it there; the case
  is a repository inside a folder that is not one, and the nested root's own rules still answer
  first.
- `IgnoreStack.isIgnored` answers for the exact path only; walkers prune, `IgnoreMatcher` checks
  ancestors. A `!` in `.ignore` cannot re-include what git ignored (git's verdict is OR-ed in).
- `FileTree` follows symlinked directories; a cycle is bounded by `maxDepth` and `maxEntries`.
- `GitIgnoredSet.isIgnored` is O(path depth) per query since 9 Oct 2026: the path's own
  ancestors are probed in the directory set, the set is never scanned.

## Ignore lookups — 9 Oct 2026

Fixed, each pinned by a test that fails against the old code:

- **Nothing under a nested checkout was ever ignored.** `GitIgnoredSet` runs one `git ls-files`
  at the opened root, and git never descends into a nested repository: `nested/` came back as
  one untracked directory, so `nested/build/` and `nested/.env` were never ignored, and the
  `.gitignore` parser was off because the outer root is a work tree. `IgnoreMatcher` now takes
  the nested roots the host discovers (`init(root:nestedRoots:)` / `setNestedRoots(_:)`) and
  judges every entry by the deepest root containing it, each root with its own `GitIgnoredSet`
  through `IgnoreRulesCache`; an ancestor is judged by its own deepest root, so a checkout
  under an outer-ignored `vendor/` stays ignored whole, and the `.ignore` stack flows down
  through nested roots as ripgrep's does. Pinned by `IgnoreNestedRepoTests`:
  `testEachEntryIsJudgedByTheDeepestCheckoutContainingIt`,
  `testNestedRootsCanBeSuppliedAfterConstruction`, and
  `testParityWithGitCheckIgnoreRunInEachRepository` (real repositories; `git check-ignore` run in
  each one is the oracle, composed over ancestors). Mutant: the matcher never switching to a
  nested root's rules — 7 failures across the three tests.
- **A lookup scanned every ignored directory.** `GitIgnoredSet.isIgnored` walked the whole
  directory set with a string concatenation per entry on every miss, and `IgnoreMatcher` asked
  it once per ancestor: O(depth × ignored directories) allocations per row. It now probes the
  path's own ancestors in the set, O(depth). `IgnoreRulesCache.rules(for:)` also skips
  re-standardising a root that already hits. Measured in `IgnoreLookupCostTests` (5,000 ignored
  directories, 1,000 lookups, debug build): `GitIgnoredSet` 99 ms → 2.1 ms; `IgnoreMatcher` over
  a real checkout 508 ms → 22 ms. Both tests guard at 50 ms and print their numbers. Mutant: the
  old linear scan restored — both guards fail (99 ms, 508 ms).

Checked and unchanged: `IgnoreRules.isIgnored` for the walkers, `IgnoreStack`, the parity
corpora (`IgnoreGitParityTests` still agrees with git on all ten).

## Write paths — 9 Oct 2026

Fixed, each pinned by a test that fails against the old code (`FileRewriteTests`,
`TextFileContentsTests`, `LocalHistoryTests`):

- **A write through a symbolic link failed, or replaced the link.** `replaceItemAt` on the LINK fails
  with ENOENT (Foundation reports "doesn't exist"), and a dangling link took the `.atomic` branch
  and became a regular file. `FileRewrite` now resolves the path with `URL.realPath`
  (FoundationExtensions, `realpath(3)`) and writes the target; a link to nothing throws
  `FileRewriteError.danglingSymbolicLink`. Mutant (the old body): three tests fail.
- **`com.apple.TextEncoding` was lost on every rewrite.** Measured: `replaceItemAt` carries
  `user.*` attributes over but not `com.apple.TextEncoding`. Every attribute of the old file is
  read first and set on the new one, `com.apple.quarantine` excepted (it described the old bytes).
  `testExtendedAttributesSurviveExceptTheQuarantineFlag`.
- **Group.** Measured: `replaceItemAt` puts back a group the user belongs to (a file chowned to
  `admin` comes back `admin`); a file in a folder of a group the user is NOT in (`wheel` under
  `/tmp`) comes back in the user's primary group and `chown` back fails with EPERM, so no
  user-space write can keep it. The `chown` in `FileRewrite` is a safety net for the first case;
  `testTheGroupSurvivesTheRewrite` pins the outcome (it passes against the old body too, so it is
  a pin of Foundation's behaviour, not a mutant-verified check).
- **A read-only file failed with Foundation's folder-permission text.** `FileRewrite` checks
  `isWritableFile` first and throws `FileRewriteError.fileNotWritable` ("“x” is read-only.").
- **UTF-16 files opened as binary.** The NUL sniff ran before any mark; `FF FE` / `FE FF` are read
  first and round-trip through `TextFileEncoding.utf16LittleEndian` / `.utf16BigEndian` (the
  mark re-written). An unmarked UTF-16 file still reads as binary. Mutant (sniff first): the
  round-trip test fails.
- **Latin-1 was presented as a fact.** `TextFileContents.decodedByFallback` says when the bytes
  were not UTF-8 and Latin-1 was assumed; `TextFileEncoding.displayName` names the encoding for
  a badge. `data(for:)` still answers nil for a text the encoding cannot hold; its doc now says
  the host must ask rather than switch encodings on its own.
- **`LocalHistory` had no total cap and lost a renamed file's versions.** `maxTotalSize`
  (256 MB) with `trimToTotalSize()` (oldest first across every file; a host calls it at launch,
  not per save) and `move(from:to:)` (the old folder's versions join the new path's, in time
  order). Mutant (both no-ops): both tests fail.

## Local history from disk — 10 Oct 2026

The host now keeps the files another writer changes (an agent's writes), not only its own saves.

- **`LocalHistorySource`** replaces the free-form source string at the API: `.saved` ("File Saved"),
  `.overwritten` ("Overwritten on disk"), `.agent` ("Agent"), `.changedOnDisk` ("Changed on disk"),
  `.previous` ("Before change"). `LocalHistoryEntry.source` stays the stored string so an index with
  a value this build does not know still reads (`kind` is nil for it);
  `testTheStoredRawValuesNeverChange`, `testAnUnknownSourceInTheIndexStillReads`.
- **The identical-bytes rule ignores the source**, so a host's save that comes back through FSEvents
  is kept once. `testTheHostsOwnSaveComingBackFromDiskIsKeptOnce`. Mutant (skip only for the same
  source): that test fails.
- **`recordFromDisk(_:source:limit:at:previous:)`**: path order, at most `limit` files, one `stat`
  before any read (a pipe or a large log is never opened), the binary sniff, and one `previous`
  call for every first sighting, kept a millisecond before the change. Mutants, each failing its own
  test: no binary check (2), no size in the stat (1), no limit (1), no previous kept (1), every file
  a first sighting (1), the previous at the same instant (1), a pipe opened (2), a previous equal to
  the new bytes kept (1). `LocalHistoryDiskTests`, 13 tests.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review of every file, with the git-parity test; four fixes (above).
- 18 Sep 2026 — `FastDirectoryListing.Entry.isSymbolicLink`: a recursive walker in the app (Quick Open) followed
  symlinked directories, so a link to an ancestor looped it forever and a link to `~` indexed the home folder.
- 18 Sep 2026 — `ProjectSearch.includeHiddenFiles` (default off): the host's Show Hidden Files toggle now reaches
  search, so `.env` and `.github/workflows` are searched when the tree lists them. Test first failed against
  the old walk (the flag did not exist; with it ignored the "on" set came back without the dot-files).
- 9 Oct 2026 — ignore lookups: nested checkouts answer from their own rules through `IgnoreMatcher`'s nested
  roots; `GitIgnoredSet.isIgnored` probes ancestors instead of scanning the listing (measured above). Two
  `nonisolated(unsafe)` annotations on `NSRegularExpression` constants (`ProjectSearch+Parallel`, `IncludeGlobs`)
  dropped: the type is `Sendable` and the compiler warned; the one on the `(String) -> Bool` capture stays, it is needed.
- 9 Oct 2026 — write paths: `FileRewrite` through links with attributes and group kept, its own errors; UTF-16 and the Latin-1 fallback in `TextFileContents`; `LocalHistory` bounded and moved with its file (section above).
- 9 Oct 2026 — security review: `ProjectScripts` interpolated a manifest's script key into `npm run \(name)` / `composer run \(name)` unquoted, so a key `build; touch /tmp/x` ran two commands when the task was chosen. `ProjectScripts.argument(_:)` quotes any name that is not plain (`String.shellQuoted` from FoundationExtensions); plain names stay readable in a menu. `testAScriptNameIsOneShellArgument` (a `;`, a space, an `&&`, an apostrophe). Mutant: the name returned as written — 3 failures.
- 10 Oct 2026 — local history from disk: `LocalHistorySource`, `recordFromDisk`, the cross-source identical-bytes rule (section above).
- 22 Oct 2026 — non-UTF-8 text reads as Windows-1252 first (old Windows files: its 0x80–0x9F are curly quotes, `€`
  and dashes, control characters in Latin-1), Latin-1 when one of its five undefined bytes appears. Measured on
  Foundation: those five fail the Windows-1252 decode, every defined byte round-trips. Tests: quotes and `€` shown and
  saved back exactly, all 123 defined high bytes round-trip, each undefined byte falls back. Mutants killed: no
  Windows-1252 step, its text read as Latin-1, not marked assumed, wrong name.
