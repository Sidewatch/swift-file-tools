//
//  LocalHistory+Disk.swift
//  FileTools
//
//  LocalHistory: versions of files another writer changed, read from disk in a bounded batch.
//
//  Created by David Sherlock on 10/10/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension LocalHistory {
    /// The most files one ``recordFromDisk(_:source:limit:at:previous:)`` call examines by default.
    public static let defaultDiskBatchLimit = 200

    /// Keeps each of `files` as it is on disk now, for changes the host did not make (an agent,
    /// a formatter, a checkout). Synchronous file I/O: call it off the main thread.
    ///
    /// The files are examined in path order and at most `limit` of them; the rest are counted in
    /// ``LocalHistoryDiskRecord/unexamined`` and never touched, so a storm costs a bounded pass.
    /// A file is left out when it is missing, not a regular file (a link is followed), over
    /// ``maxFileSize``, binary (``TextFileContents``), or the same bytes as its last version.
    ///
    /// A file with no versions yet is a first sighting: `previous` is asked ONCE, with every such
    /// file, for what they held before (a clean buffer, the committed blob), and an answer that
    /// differs from the new bytes is kept first, a millisecond earlier, under
    /// ``LocalHistorySource/previous`` — so the first outside change has a "before".
    @discardableResult
    public func recordFromDisk(
        _ files: [URL], source: LocalHistorySource, limit: Int = LocalHistory.defaultDiskBatchLimit, at time: Date = Date(),
        previous: ([URL]) -> [URL: Data] = { _ in [:] }
    ) -> LocalHistoryDiskRecord {
        let ordered = files.sorted { $0.path < $1.path }
        let examined = ordered.prefix(max(0, limit))
        var outcome = LocalHistoryDiskRecord(unexamined: ordered.count - examined.count)
        let candidates = examined.filter(isRecordableOnDisk)
        outcome.skipped = examined.count - candidates.count
        let firstSeen = candidates.filter { entries(for: $0).isEmpty }
        let earlier = firstSeen.isEmpty ? [:] : previous(firstSeen)
        let firstSeenSet = Set(firstSeen)
        for file in candidates {
            guard let data = readRecordable(file) else {
                outcome.skipped += 1
                continue
            }
            if firstSeenSet.contains(file), let before = earlier[file], before != data, isRecordable(before),
                (try? record(before, for: file, source: .previous, at: time.addingTimeInterval(-0.001))) != nil
            {
                outcome.previousKept.append(file)
            }
            if (try? record(data, for: file, source: source, at: time)) != nil {
                outcome.recorded.append(file)
            } else {
                outcome.skipped += 1
            }
        }
        return outcome
    }

    /// Whether `file` is a regular file (after links) no larger than ``maxFileSize`` — one `stat`,
    /// so a large log or a pipe is never opened.
    private func isRecordableOnDisk(_ file: URL) -> Bool {
        var info = stat()
        guard stat(file.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG && Int(info.st_size) <= maxFileSize
    }

    /// The file's bytes when they are text (``record(_:for:source:at:)`` holds the ceiling).
    private func readRecordable(_ file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file), isRecordable(data) else { return nil }
        return data
    }

    /// Bytes that decode as text.
    private func isRecordable(_ data: Data) -> Bool { TextFileContents(data: data) != nil }
}
