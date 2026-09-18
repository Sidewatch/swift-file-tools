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
- **A nested repository's own `.gitignore` is not applied by the outer walk** when the outer
  folder is a checkout (git's `ls-files` stops at nested repos, and `.gitignore` parsing is off
  while git answers). Its `node_modules` / `build` / `vendor` still fall to the skip list.
- `IgnoreStack.isIgnored` answers for the exact path only; walkers prune, `IgnoreMatcher` checks
  ancestors. A `!` in `.ignore` cannot re-include what git ignored (git's verdict is OR-ed in).
- `FileTree` follows symlinked directories; a cycle is bounded by `maxDepth` and `maxEntries`.
- `GitIgnoredSet.isIgnored` is O(ignored directories) per query; walkers never ask inside a
  pruned subtree, so it does not compound.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review of every file, with the git-parity test; four fixes (above).
- 18 Sep 2026 — `FastDirectoryListing.Entry.isSymbolicLink`: a recursive walker in the app (Quick Open) followed
  symlinked directories, so a link to an ancestor looped it forever and a link to `~` indexed the home folder.
- 18 Sep 2026 — `ProjectSearch.includeHiddenFiles` (default off): the host's Show Hidden Files toggle now reaches
  search, so `.env` and `.github/workflows` are searched when the tree lists them. Test first failed against
  the old walk (the flag did not exist; with it ignored the "on" set came back without the dot-files).
