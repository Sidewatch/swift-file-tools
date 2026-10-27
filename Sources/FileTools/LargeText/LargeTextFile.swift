//
//  LargeTextFile.swift
//  FileTools
//
//  A text file of any size, read in pieces: its lines found by a background scan, any line's bytes read and
//  decoded only when asked for.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A text file of any size, read in pieces instead of into a string: a background scan finds its lines, and a
/// line's bytes are read and decoded only when asked for. Opening reads 64 KB, so a 10 GB log shows its first
/// screen at once; memory holds the start of every 256th line and of every line of 64 KB or more.
///
/// The bytes are read with `pread`, never mapped: a mapped log that another process truncates (a rotation) kills
/// its reader the moment a page past the new end is touched, while a read just comes back short. A file that
/// grows is read on from where the scan stopped (``grew()``, then ``scanLines(update:)`` again).
///
/// Lines end at `\n`; a `\r` before it is not part of the line, and the text after the last `\n` is the last line,
/// empty when the file ends with a break, as an editor shows it. The bytes decode as UTF-8, an invalid sequence as
/// U+FFFD, unless the file's opening bytes are not UTF-8, when they are read as Windows-1252.
public final class LargeTextFile: @unchecked Sendable {
    /// The file this reads.
    public let url: URL

    /// How the bytes decode: UTF-8, or Windows-1252 for a file whose opening bytes are not UTF-8.
    public let encoding: String.Encoding

    /// Whether the file reads as binary: a NUL in its opening bytes (``TextFileContents/hasBinaryPrefix(_:)``).
    public let isBinary: Bool

    private let descriptor: Int32

    /// One line in this many keeps its start; any other line is found by walking from the last one kept.
    let stride: Int

    /// A line at least this long keeps its start and end, so finding it never reads it.
    let longLine: Int

    /// How much the scan reads at a time.
    let chunk: Int

    private let lock = NSLock()
    /// The start of line `k * stride`, for every k the scan has reached.
    private var checkpoints: [Int] = [0]
    /// The lines of `longLine` bytes or more, ascending.
    private var longLines: [LongLine] = []
    /// The scan's position and findings.
    private var newlines = 0
    private var scanned = 0
    private var lastLineStart = 0
    private var longest = 0
    private var size: Int
    private var finished = false
    private var stopped = false
    private var scanning = false
    /// The last line found by walking, where the next walk can start.
    private var recent: (line: Int, start: Int) = (0, 0)

    /// A line too long to read through: where it starts and where its break (or the file) ends it.
    private struct LongLine {
        let line: Int
        let start: Int
        let end: Int
    }

    /// Opens the file at `url` for reading; nil when it cannot be opened or is not a regular file.
    public convenience init?(url: URL) { self.init(url: url, stride: 256, longLine: 64 << 10, chunk: 16 << 20) }

    /// Opens the file with the index's spacing, the long-line length and the scan's read size given (a test makes
    /// them small, to cross every boundary with a small file).
    init?(url: URL, stride: Int, longLine: Int, chunk: Int) {
        self.stride = stride
        self.longLine = longLine
        self.chunk = chunk
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            return nil
        }
        self.url = url
        self.descriptor = fd
        self.size = Int(info.st_size)
        let opening = Self.read(fd, 0..<min(Int(info.st_size), 64 << 10))
        self.encoding = Self.encoding(ofOpening: opening)
        self.isBinary = TextFileContents.hasBinaryPrefix(Data(opening))
    }

    deinit { close(descriptor) }

    /// Where the scan has got to.
    public var progress: LargeTextProgress {
        lock.withLock {
            LargeTextProgress(
                lineCount: finished ? newlines + 1 : newlines, bytesScanned: scanned, byteCount: size, isComplete: finished,
                longestLineBytes: longest)
        }
    }

    /// The lines that can be asked for: every line the scan has seen end, and the last one once it is done.
    public var lineCount: Int { progress.lineCount }

    /// The bytes the file had when it was opened, or at the last ``grew()``.
    public var byteCount: Int { lock.withLock { size } }

    // MARK: - Scanning

    /// Scans for lines on a background queue, from where the last scan stopped. `update` runs on the main queue
    /// about ten times a second meanwhile and once at the end. A scan already running is left to finish.
    public func scanLines(update: @escaping @MainActor @Sendable (LargeTextProgress) -> Void) {
        guard
            lock.withLock({ () -> Bool in
                guard !scanning else { return false }
                scanning = true
                stopped = false
                return true
            })
        else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var reported = ProcessInfo.processInfo.systemUptime
            scan {
                let now = ProcessInfo.processInfo.systemUptime
                guard now - reported > 0.1 else { return }
                reported = now
                let snapshot = progress
                DispatchQueue.main.async { MainActor.assumeIsolated { update(snapshot) } }
            }
            lock.withLock { scanning = false }
            let snapshot = progress
            DispatchQueue.main.async { MainActor.assumeIsolated { update(snapshot) } }
        }
    }

    /// Ends a scan in progress; the lines found so far stay usable, and a later ``scanLines(update:)`` goes on.
    public func stopScanning() { lock.withLock { stopped = true } }

    /// Whether the file has grown since it was opened or last asked; when it has, the new bytes join the text and
    /// the next ``scanLines(update:)`` reads them. A file that shrank or was replaced answers false: open it again.
    public func grew() -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        return lock.withLock {
            guard Int(info.st_size) > size else { return false }
            size = Int(info.st_size)
            finished = false
            stopped = false
            return true
        }
    }

    /// Whether the file now holds fewer bytes than were read (truncated, rotated): its lines are no longer these.
    public var isTruncated: Bool {
        var info = stat()
        return fstat(descriptor, &info) == 0 && Int(info.st_size) < byteCount
    }

    /// The scan itself, run on the calling thread: the file read a chunk at a time up to its size when the scan
    /// began, each chunk swept for `\n` with `memchr`.
    func scan(afterChunk: () -> Void = {}) {
        var (offset, lineStart, count, longestLine, limit) = lock.withLock { (scanned, lastLineStart, newlines, longest, size) }
        var buffer = [UInt8](repeating: 0, count: chunk)
        while offset < limit, !lock.withLock({ stopped }) {
            let got = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, min(chunk, limit - offset), off_t(offset)) }
            guard got > 0 else {
                limit = offset  // shorter than it was: it ends here now
                break
            }
            var found: [Int] = []
            var long: [LongLine] = []
            buffer.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var position = 0
                while position < got, let hit = memchr(base + position, 0x0A, got - position) {
                    let at = UnsafeRawPointer(hit) - base
                    let length = offset + at - lineStart
                    longestLine = max(longestLine, length)
                    if length >= longLine { long.append(LongLine(line: count, start: lineStart, end: offset + at)) }
                    lineStart = offset + at + 1
                    count += 1
                    if count % stride == 0 { found.append(lineStart) }
                    position = at + 1
                }
            }
            offset += got
            let (reached, start, lines, longestSoFar) = (offset, lineStart, count, longestLine)
            lock.withLock {
                checkpoints += found
                longLines += long
                newlines = lines
                scanned = reached
                lastLineStart = start
                longest = longestSoFar
            }
            afterChunk()
        }
        let (end, start) = (limit, lineStart)
        lock.withLock {
            guard !stopped || offset >= size else { return }
            if end < size { size = end }
            longest = max(longest, end - start)
            finished = offset >= size
        }
    }

    // MARK: - Lines

    /// The bytes of 0-based `line`, without its line break; nil for a line the scan has not reached.
    public func byteRange(ofLine line: Int) -> Range<Int>? {
        guard let start = start(ofLine: line) else { return nil }
        let (isLast, end, long) = lock.withLock { () -> (Bool, Int, LongLine?) in
            (finished && line == newlines, size, Self.long(line, in: longLines))
        }
        if isLast { return trimmed(start..<end) }
        if let long { return trimmed(long.start..<long.end) }
        // Not a long line: its break is within the next `longLine` bytes.
        let block = Self.read(descriptor, start..<min(end, start + longLine))
        let length = block.withUnsafeBytes { raw in
            raw.baseAddress.flatMap { memchr($0, 0x0A, raw.count) }.map { UnsafeRawPointer($0) - raw.baseAddress! } ?? raw.count
        }
        return trimmed(start..<(start + length))
    }

    /// The offset where 0-based `line` starts; nil for a line the scan has not reached.
    func start(ofLine line: Int) -> Int? {
        let (available, from, fromLine, lastStart, last, long) = lock.withLock {
            () -> (Int, Int, Int, Int, Int, [LongLine]) in
            let k = max(0, min(line / stride, checkpoints.count - 1))
            var from = checkpoints[k]
            var fromLine = k * stride
            if recent.line <= line, recent.line >= fromLine { (fromLine, from) = recent }
            return (finished ? newlines + 1 : newlines, from, fromLine, lastLineStart, newlines, longLines)
        }
        guard line >= 0, line < available else { return nil }
        if line == last { return lastStart }
        var start = from
        var current = fromLine
        var block: [UInt8] = []
        var blockStart = 0
        while current < line {
            if let long = Self.long(current, in: long) {
                start = long.end + 1
                current += 1
                continue
            }
            if start < blockStart || start >= blockStart + block.count {
                blockStart = start
                block = Self.read(descriptor, start..<(start + 256 << 10))
                if block.isEmpty { return nil }  // the file shrank under us
            }
            let next = block.withUnsafeBytes { raw -> Int? in
                let from = start - blockStart
                return memchr(raw.baseAddress! + from, 0x0A, raw.count - from).map { UnsafeRawPointer($0) - raw.baseAddress! }
            }
            if let next {
                start = blockStart + next + 1
                current += 1
            } else {
                blockStart += block.count  // read on
                block = []
                start = max(start, blockStart)
            }
        }
        lock.withLock { recent = (line, start) }
        return start
    }

    /// The 0-based line holding byte `offset`.
    public func line(containingByte offset: Int) -> Int {
        let (k, from, long) = lock.withLock { () -> (Int, Int, [LongLine]) in
            var lo = 0
            var hi = checkpoints.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if checkpoints[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            return (lo, checkpoints[lo], longLines)
        }
        var line = k * stride
        var position = from
        while position < offset {
            if let long = Self.long(line, in: long), long.start == position {
                guard long.end < offset else { return line }
                position = long.end + 1
                line += 1
                continue
            }
            let block = Self.read(descriptor, position..<min(offset, position + 256 << 10))
            guard !block.isEmpty else { return line }
            let breaks = block.withUnsafeBytes { raw -> [Int] in
                var found: [Int] = []
                var at = 0
                while at < raw.count, let hit = memchr(raw.baseAddress! + at, 0x0A, raw.count - at) {
                    at = UnsafeRawPointer(hit) - raw.baseAddress! + 1
                    found.append(at)
                }
                return found
            }
            line += breaks.count
            position += breaks.last ?? block.count  // no break: a line longer than the block, read on
        }
        return line
    }

    /// The text of 0-based `line`, or nil for a line the scan has not reached.
    public func text(ofLine line: Int) -> String? { byteRange(ofLine: line).map(text(in:)) }

    /// The text of the bytes in `range`, as far as the file holds them.
    public func text(in range: Range<Int>) -> String {
        let bytes = Self.read(descriptor, max(0, range.lowerBound)..<max(range.lowerBound, range.upperBound))
        guard !bytes.isEmpty else { return "" }
        if encoding == .utf8 { return String(decoding: bytes, as: UTF8.self) }
        return String(bytes: bytes, encoding: .windowsCP1252) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    /// `offset`, or the start of the UTF-8 character it falls inside (a window into a long line must not begin
    /// halfway through one). Windows-1252 has one byte to a character.
    public func characterStart(atOrBefore offset: Int) -> Int {
        guard encoding == .utf8, offset > 0 else { return max(0, offset) }
        let lower = max(0, offset - 3)
        let around = Self.read(descriptor, lower..<(offset + 1))
        var index = offset - lower  // the byte at `offset`
        guard index < around.count else { return offset }  // at or past the end
        while index > 0, around[index] & 0xC0 == 0x80 { index -= 1 }
        return lower + index
    }

    /// Reads the bytes in `range` (fewer at the file's end, none past it).
    func bytes(in range: Range<Int>) -> [UInt8] { Self.read(descriptor, range) }

    /// The start of the line holding byte `offset`: just past the last line break before it, looked for at most
    /// `limit` bytes back without the scan's help (it may not have got there); 0 at the file's start, and `offset`
    /// itself inside a line longer than `limit`.
    func lineStart(atOrBefore offset: Int, within limit: Int) -> Int {
        let floor = max(0, offset - limit)
        var end = offset
        while end > floor {
            let from = max(floor, end - (64 << 10))
            let bytes = Self.read(descriptor, from..<end)
            guard !bytes.isEmpty else { return offset }  // past the file's end
            if let lastBreak = bytes.lastIndex(of: 0x0A) { return from + lastBreak + 1 }
            end = from
        }
        return floor == 0 ? 0 : offset
    }

    // MARK: - Helpers

    /// The long line numbered `line`, if it is one.
    private static func long(_ line: Int, in lines: [LongLine]) -> LongLine? {
        var lo = 0
        var hi = lines.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].line == line { return lines[mid] }
            if lines[mid].line < line { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// `range` without a `\r` at its end.
    private func trimmed(_ range: Range<Int>) -> Range<Int> {
        guard !range.isEmpty, Self.read(descriptor, (range.upperBound - 1)..<range.upperBound) == [0x0D] else { return range }
        return range.lowerBound..<(range.upperBound - 1)
    }

    /// The bytes of `range` read from `fd` (fewer at its end).
    private static func read(_ fd: Int32, _ range: Range<Int>) -> [UInt8] {
        guard !range.isEmpty, range.lowerBound >= 0 else { return [] }
        var out = [UInt8](repeating: 0, count: range.count)
        let got = out.withUnsafeMutableBytes { pread(fd, $0.baseAddress, range.count, off_t(range.lowerBound)) }
        guard got > 0 else { return [] }
        if got < out.count { out.removeLast(out.count - got) }
        return out
    }

    /// UTF-8 when `opening` is (a character cut off at its end allowed), else Windows-1252.
    private static func encoding(ofOpening opening: [UInt8]) -> String.Encoding {
        for cut in 0...min(3, opening.count) where String(bytes: opening.dropLast(cut), encoding: .utf8) != nil {
            return .utf8
        }
        return .windowsCP1252
    }
}
