//
//  LogColumns.swift
//  LogReader
//
//  A log's entries as columns: what a filter needs for each, and the running counts.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// Every entry's start, first line, line count, level, time, component and format, one array each (about 30 bytes
/// an entry), with the counts a summary reports. The text is never held: it is read from the file when shown.
struct LogColumns {
    private(set) var starts: [Int] = []
    private(set) var firstLines: [Int32] = []
    private(set) var lineCounts: [Int32] = []
    /// The level's raw value, -1 for none.
    private(set) var levels: [Int8] = []
    /// Seconds since the epoch, NaN for none.
    private(set) var times: [Double] = []
    private(set) var zoned: [Bool] = []
    /// An index into `componentNames`, -1 for none.
    private(set) var components: [Int32] = []
    private(set) var formats: [UInt8] = []
    /// Whether the entry's level is still to come on its next line (java.util.logging).
    private(set) var levelPending = false

    private(set) var componentNames: [String] = []
    private var componentIDs: [String: Int32] = [:]
    private(set) var componentCounts: [Int] = []
    private(set) var levelCounts = [Int](repeating: 0, count: LogLevel.allCases.count)
    private(set) var unleveledCount = 0
    private(set) var formatCounts = [Int](repeating: 0, count: LogFormat.allCases.count)
    private(set) var firstTime: Double?
    private(set) var lastTime: Double?

    var count: Int { starts.count }

    /// What `append` or `extendLast` changed, so a provisional last line can be taken back.
    enum Change {
        case appended(firstTime: Double?, lastTime: Double?)
        case extended(lines: Int32, levelSet: Bool)
        /// A blank line held back until it is known whose it is: nothing in the columns changed.
        case blank
    }

    /// A new entry from a header line at byte `start`, line `line`.
    mutating func append(_ head: LogLineHead, start: Int, line: Int) -> Change {
        let before = Change.appended(firstTime: firstTime, lastTime: lastTime)
        starts.append(start)
        firstLines.append(Int32(clamping: line))
        lineCounts.append(1)
        levels.append(head.level.map { Int8($0.rawValue) } ?? -1)
        countLevel(head.level, by: 1)
        if let t = head.time?.seconds {
            times.append(t)
            firstTime = Swift.min(firstTime ?? t, t)
            lastTime = Swift.max(lastTime ?? t, t)
        } else {
            times.append(.nan)
        }
        zoned.append(head.time?.zoned ?? false)
        if let name = head.component {
            components.append(componentID(name))
        } else {
            components.append(-1)
        }
        let format = LogFormat.allCases.firstIndex(of: head.format)!
        formats.append(UInt8(format))
        formatCounts[format] += 1
        levelPending = head.levelOnNextLine && head.level == nil
        return before
    }

    /// `lines` more lines for the last entry; `level`, when the entry was waiting for one (java.util.logging).
    mutating func extendLast(by lines: Int32 = 1, level: LogLevel?) -> Change {
        let last = count - 1
        lineCounts[last] += lines
        guard levelPending, let level else { return .extended(lines: lines, levelSet: false) }
        countLevel(nil, by: -1)
        levels[last] = Int8(level.rawValue)
        countLevel(level, by: 1)
        levelPending = false
        return .extended(lines: lines, levelSet: true)
    }

    /// Takes back a change, newest first.
    mutating func undo(_ change: Change) {
        let last = count - 1
        switch change {
        case .blank:
            return
        case .extended(let lines, let levelSet):
            lineCounts[last] -= lines
            if levelSet {
                countLevel(LogLevel(rawValue: Int(levels[last])), by: -1)
                levels[last] = -1
                countLevel(nil, by: 1)
                levelPending = true
            }
        case .appended(let first, let lastT):
            countLevel(LogLevel(rawValue: Int(levels[last])), by: -1)
            formatCounts[Int(formats[last])] -= 1
            if components[last] >= 0 { componentCounts[Int(components[last])] -= 1 }
            starts.removeLast()
            firstLines.removeLast()
            lineCounts.removeLast()
            levels.removeLast()
            times.removeLast()
            zoned.removeLast()
            components.removeLast()
            formats.removeLast()
            firstTime = first
            lastTime = lastT
            levelPending = false
        }
    }

    private mutating func countLevel(_ level: LogLevel?, by delta: Int) {
        if let level { levelCounts[level.rawValue] += delta } else { unleveledCount += delta }
    }

    private mutating func componentID(_ name: String) -> Int32 {
        if let id = componentIDs[name] {
            componentCounts[Int(id)] += 1
            return id
        }
        let id = Int32(componentNames.count)
        componentNames.append(name)
        componentIDs[name] = id
        componentCounts.append(1)
        return id
    }

    /// The entry at `i`, its bytes ending where the next starts (less the break) or at `end`.
    func entry(_ i: Int, end: Int) -> LogEntry {
        let next = i + 1 < count ? starts[i + 1] : end
        let level = levels[i] >= 0 ? LogLevel(rawValue: Int(levels[i])) : nil
        let time = times[i].isNaN ? nil : LogInstant(seconds: times[i], zoned: zoned[i])
        return LogEntry(
            index: i, bytes: starts[i]..<Swift.max(starts[i], next), firstLine: Int(firstLines[i]), lineCount: Int(lineCounts[i]),
            level: level, time: time, component: components[i] >= 0 ? componentNames[Int(components[i])] : nil,
            format: LogFormat.allCases[Int(formats[i])])
    }
}
