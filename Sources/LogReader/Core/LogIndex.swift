//
//  LogIndex.swift
//  LogReader
//
//  A log file of any size read once, in the background, as entries a filter can run over.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import FileTools
import Foundation

/// A log file read as entries: a background scan reads it a megabyte at a time, gives each line with a header an
/// entry (`LogLineParser`) and every line without one to the entry above (a stack trace stays with its error), and
/// keeps about 30 bytes an entry, never the text (`LogColumns`). Lines before the first header, and every line of a
/// file that has none, are entries of their own, their level read from a capitalised level word in them.
///
/// A file that grows is read on from where the scan stopped: after ``FileTools/LargeTextFile/grew()``, ``scan(update:)``
/// again. A last line with no break yet is read provisionally and read again once it has one. Filtering
/// (``matching(_:isCancelled:)``) runs over the columns, and over the file's bytes for text, on the caller's queue.
public final class LogIndex: @unchecked Sendable {
    /// The file read.
    public let file: LargeTextFile
    /// The day formats without a year or a date are read against.
    public let reference: LogReference

    /// How much the scan reads at a time, and how much of a line longer than that it reads for the header.
    static let block = 1 << 20
    static let headLimit = 64 << 10
    /// A run of header-less lines this long starts a new entry: a log that stopped writing headers is not one entry.
    static let maxContinuation: Int32 = 5000

    private let lock = NSLock()
    private var columns = LogColumns()
    /// Where the next line starts, and its number.
    private var scanned = 0
    private var lineNumber = 0
    private var sawHeader = false
    /// Blank lines read since the last entry's last line: they join it only if more of it follows.
    private var pendingBlanks: Int32 = 0
    /// The last line read with no break after it, to read again when the file grows.
    private var tail: (change: LogColumns.Change, start: Int, line: Int, sawHeader: Bool, blanks: Int32)?
    private var scanning = false
    private var stopped = false
    private var complete = false
    private let queue = DispatchQueue(label: "LogIndex.scan", qos: .userInitiated)

    /// An index of `file`, read against `reference`.
    public init(file: LargeTextFile, reference: LogReference) {
        self.file = file
        self.reference = reference
    }

    /// An index of the file at `url`, read against its modification day; nil when it cannot be opened.
    public convenience init?(url: URL) {
        guard let file = LargeTextFile(url: url) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let day = Calendar(identifier: .gregorian).dateComponents(in: .current, from: modified)
        self.init(file: file, reference: LogReference(year: day.year ?? 2026, month: day.month ?? 1, day: day.day ?? 1))
    }

    /// The entries read so far.
    public var entryCount: Int { lock.withLock { columns.count } }

    /// The entry at `index`, while it exists.
    public func entry(at index: Int) -> LogEntry? {
        lock.withLock { index >= 0 && index < columns.count ? columns.entry(index, end: entryEnd) : nil }
    }

    /// Where the last entry ends: the last line read, its break left out.
    private var entryEnd: Int { tail.map { _ in file.byteCount } ?? max(0, scanned - 1) }

    /// What the log holds so far.
    public var summary: LogSummary {
        lock.withLock {
            let names = columns.componentNames
            let components = zip(names, columns.componentCounts).filter { $0.1 > 0 }.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
            var levels: [LogLevel: Int] = [:]
            for level in LogLevel.allCases where columns.levelCounts[level.rawValue] > 0 {
                levels[level] = columns.levelCounts[level.rawValue]
            }
            let formats = zip(LogFormat.allCases, columns.formatCounts).filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
            return LogSummary(
                entryCount: columns.count, levelCounts: levels, unleveledCount: columns.unleveledCount,
                components: components.map { (name: $0.0, count: $0.1) }, firstTime: columns.firstTime, lastTime: columns.lastTime,
                formats: formats, isComplete: complete)
        }
    }

    /// Reads on from where the last scan stopped, on a background queue; `update` runs on the main queue about ten
    /// times a second meanwhile and once at the end. A scan already running is left to finish.
    public func scan(update: @escaping @MainActor @Sendable (LogSummary) -> Void) {
        let start: Bool = lock.withLock {
            guard !scanning else { return false }
            scanning = true
            stopped = false
            complete = false
            return true
        }
        guard start else { return }
        queue.async { [self] in
            readOn { summary in DispatchQueue.main.async { MainActor.assumeIsolated { update(summary) } } }
            lock.withLock {
                scanning = false
                complete = !stopped
            }
            let final = summary
            DispatchQueue.main.async { MainActor.assumeIsolated { update(final) } }
        }
    }

    /// Ends a scan in progress; what it read stays, and a later ``scan(update:)`` goes on.
    public func stop() { lock.withLock { stopped = true } }

    private var isStopped: Bool { lock.withLock { stopped } }

    /// Whether a scan is running.
    public var isScanning: Bool { lock.withLock { scanning } }

    // MARK: - Reading

    /// The scan proper: blocks of whole lines, a line longer than a block read for its header and skipped to its break.
    private func readOn(report: (LogSummary) -> Void) {
        lock.withLock { undoTail() }
        let size = file.byteCount
        var pos = lock.withLock { scanned }
        var lastReport = Date()
        while pos < size, !isStopped {
            let bytes = file.bytes(in: pos..<min(size, pos + Self.block))
            guard !bytes.isEmpty else { break }
            let consumed = lock.withLock { readLines(bytes[...], at: pos) }
            if consumed > 0 {
                pos += consumed
            } else if pos + bytes.count >= size {
                break  // the last line, with no break yet
            } else if let end = nextBreak(after: pos + bytes.count, size: size) {
                lock.withLock {
                    read(line: bytes[0..<min(bytes.count, Self.headLimit)], start: pos)
                    scanned = end + 1
                }
                pos = end + 1
            } else {
                break  // a long last line
            }
            if Date().timeIntervalSince(lastReport) > 0.1 {
                lastReport = Date()
                report(summary)
            }
        }
        if pos < size, !isStopped {
            let rest = file.bytes(in: pos..<min(size, pos + Self.headLimit))
            lock.withLock {
                let line = lineNumber, saw = sawHeader, blanks = pendingBlanks
                let change = read(line: rest[...], start: pos)
                tail = (change, pos, line, saw, blanks)
            }
        }
    }

    /// Reads every whole line in `bytes` (which start at file offset `start`); how many bytes they took.
    private func readLines(_ bytes: ArraySlice<UInt8>, at start: Int) -> Int {
        var lineStart = bytes.startIndex
        while let nl = bytes[lineStart...].firstIndex(of: 0x0A) {
            read(line: bytes[lineStart..<nl], start: start + (lineStart - bytes.startIndex))
            lineStart = nl + 1
        }
        let consumed = lineStart - bytes.startIndex
        scanned = start + consumed
        return consumed
    }

    /// One line: a new entry when it has a header (or no header has been seen, or it is a separator), else one more
    /// line of the last. Blank lines join the entry above only when more of it follows them: a format that writes
    /// one before every entry (Elixir's) leaves them to no entry.
    @discardableResult private func read(line raw: ArraySlice<UInt8>, start: Int) -> LogColumns.Change {
        let line = raw.last == 0x0D ? raw.dropLast() : raw
        defer { lineNumber += 1 }
        if let head = LogLineParser.head(of: line, reference: reference) {
            sawHeader = true
            pendingBlanks = 0
            return columns.append(head, start: start, line: lineNumber)
        }
        if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }), sawHeader, columns.count > 0 {
            pendingBlanks += 1
            return .blank
        }
        if !sawHeader || columns.count == 0 || columns.lineCounts[columns.count - 1] >= Self.maxContinuation
            || LogLineParser.isSeparator(line)
        {
            pendingBlanks = 0
            let head = LogLineHead(format: .text, level: LogLineParser.keywordLevel(line))
            return columns.append(head, start: start, line: lineNumber)
        }
        let level = columns.levelPending ? LogLineParser.javaUtilLoggingLevel(line) : nil
        let blanks = pendingBlanks
        pendingBlanks = 0
        return columns.extendLast(by: blanks + 1, level: level)
    }

    /// Takes back the provisional last line, so it is read again with what followed it.
    private func undoTail() {
        guard let tail else { return }
        columns.undo(tail.change)
        scanned = tail.start
        lineNumber = tail.line
        sawHeader = tail.sawHeader
        pendingBlanks = tail.blanks
        self.tail = nil
    }

    /// The offset of the next line break at or after `offset`, read a block at a time.
    private func nextBreak(after offset: Int, size: Int) -> Int? {
        var at = offset
        while at < size {
            let bytes = file.bytes(in: at..<min(size, at + Self.block))
            guard !bytes.isEmpty else { return nil }
            if let nl = bytes.firstIndex(of: 0x0A) { return at + nl }
            at += bytes.count
        }
        return nil
    }

    // MARK: - Text

    /// The entry's text, every line of it, up to `limit` bytes (its last break left out).
    public func text(of entry: LogEntry, limit: Int = 1 << 20) -> String {
        let range = entry.bytes.lowerBound..<min(entry.bytes.upperBound, entry.bytes.lowerBound + limit)
        var text = file.text(in: range)
        // By scalar: "\r\n" is one Character, which `hasSuffix("\n")` does not see.
        while let last = text.unicodeScalars.last, last == "\n" || last == "\r" { text.unicodeScalars.removeLast() }
        return text
    }

    /// The entry's first line, up to 64 KB, and what its header says.
    public func firstLine(of entry: LogEntry) -> (text: String, head: LogLineHead?) {
        var bytes = file.bytes(in: entry.bytes.lowerBound..<min(entry.bytes.upperBound, entry.bytes.lowerBound + Self.headLimit))[...]
        if let nl = bytes.firstIndex(of: 0x0A) { bytes = bytes[..<nl] }
        if bytes.last == 0x0D { bytes = bytes.dropLast() }
        return (
            file.text(in: entry.bytes.lowerBound..<(entry.bytes.lowerBound + bytes.count)),
            LogLineParser.head(of: bytes, reference: reference)
        )
    }

    // MARK: - Filtering

    /// The indexes of the entries `filter` lets through, in file order; nil when `isCancelled` said stop. Level,
    /// time and component are answered from the columns; text from the file's bytes, read in 8 MB runs of whole
    /// entries, the matcher run once over each (`LargeTextMatcher`), every match given to the entry it falls in. A
    /// regular expression that does not compile matches nothing.
    public func matching(_ filter: LogFilter, isCancelled: () -> Bool = { false }) -> [Int]? {
        let (snapshot, end) = lock.withLock { (columns, entryEnd) }
        var candidates: [Int] = []
        candidates.reserveCapacity(snapshot.count)
        let componentIDs = filter.components.map { wanted in
            Set(snapshot.componentNames.enumerated().filter { wanted.contains($0.element) }.map { Int32($0.offset) })
        }
        let levelMask = filter.levels.reduce(0) { $0 | (1 << $1.rawValue) }
        for i in 0..<snapshot.count {
            if i & 0xFFFF == 0, isCancelled() { return nil }
            let level = snapshot.levels[i]
            guard level >= 0 ? levelMask & (1 << Int(level)) != 0 : filter.showsUnleveled else { continue }
            let t = snapshot.times[i]
            if !t.isNaN {
                if let from = filter.from, t < from { continue }
                if let to = filter.to, t > to { continue }
            }
            if let ids = componentIDs, !ids.contains(snapshot.components[i]) { continue }
            candidates.append(i)
        }
        guard !filter.text.isEmpty else { return candidates }
        guard
            let matcher = LargeTextMatcher(
                text: filter.text, caseSensitive: filter.caseSensitive, isRegex: filter.isRegex, encoding: file.encoding)
        else { return [] }
        return textMatches(candidates, matcher, snapshot.starts, end: end, isCancelled: isCancelled)
    }

    /// The candidates whose text holds a match.
    private func textMatches(_ candidates: [Int], _ matcher: LargeTextMatcher, _ starts: [Int], end: Int, isCancelled: () -> Bool) -> [Int]?
    {
        var hit = Set<Int>()
        var k = 0
        while k < candidates.count {
            if isCancelled() { return nil }
            let first = candidates[k]
            var last = first
            // Whole entries, up to 8 MB (one entry may be more).
            while last + 1 < starts.count, starts[last + 1] - starts[first] < 8 << 20 { last += 1 }
            let runEnd = last + 1 < starts.count ? starts[last + 1] : end
            let bytes = file.bytes(in: starts[first]..<max(starts[first], runEnd))
            matcher.enumerate(in: bytes[...], at: starts[first]) { range in
                // The entry holding the match: the last start at or before it.
                var lo = first, hi = last
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if starts[mid] <= range.lowerBound { lo = mid } else { hi = mid - 1 }
                }
                hit.insert(lo)
                return true
            }
            while k < candidates.count, candidates[k] <= last { k += 1 }
        }
        return candidates.filter(hit.contains)
    }
}
