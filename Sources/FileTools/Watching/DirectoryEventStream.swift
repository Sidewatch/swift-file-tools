//
//  DirectoryEventStream.swift
//  SwiftFileTools
//
//  A self-contained FSEvents wrapper that streams file-system change events for
//  a directory. Lifted from CodeEdit (MIT). Original author: Khan Winter.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Creates a stream of events using the File System Events API.
///
/// The stream of events is started immediately upon initialization, and will only be stopped when either `cancel`
/// is called, or the object is deallocated. The stream is also configured to debounce notifications to happen
/// according to the `debounceDuration` parameter. This directly corresponds with the `latency` parameter in
/// `FSEventStreamCreate`, which will delay notifications until `latency` has passed at which point it will send all
/// the notifications built up during that period of time.
///
/// Use the `callback` parameter to listen for notifications.
/// Notifications are automatically filtered to include certain events, but the FS event API doesn't always correctly
/// flag events so use caution when handling events as they can come frequently.
///
/// The `callback` function will be called with all events that happened since the last event notification,
/// effectively batching all notifications every `debounceDuration`. This callback may not be called on a
/// predictable dispatch queue.
public final class DirectoryEventStream {

    /// A callback invoked with every batch of events since the last notification.
    public typealias EventCallback = ([Event]) -> Void

    /// Bridges the C callback to the stream without extending its lifetime.
    ///
    /// The FSEvents context holds an unretained pointer, so the callback must
    /// never dereference `DirectoryEventStream` directly — a callback already
    /// in flight when the last strong reference drops would touch freed
    /// memory. The box is kept alive by the stream instance, and the `weak`
    /// load safely yields `nil` once deinit has begun.
    private final class CallbackBox {
        weak var owner: DirectoryEventStream?
        init(owner: DirectoryEventStream) { self.owner = owner }
    }

    /// Marks `eventQueue` so `cancel()` can detect re-entrant calls made from
    /// inside the client callback and avoid a `sync` deadlock.
    private static let queueKey = DispatchSpecificKey<Void>()

    private var streamRef: FSEventStreamRef?
    private var callback: EventCallback
    private let debounceDuration: TimeInterval
    /// Serial queue events are delivered on; `cancel()` synchronizes on it so
    /// teardown waits for any in-flight callback and is safe to call from
    /// multiple threads.
    private let eventQueue: DispatchQueue
    /// Kept alive for the lifetime of the object so the context's unretained
    /// pointer stays valid for as long as a callback could possibly run.
    private var callbackBox: CallbackBox?

    /// A single file-system change: the affected `path` and its ``FSEvent`` kind.
    public struct Event {

        /// The absolute path of the item that changed.
        public let path: String

        /// The kind of change that occurred.
        public let eventType: FSEvent

        /// Creates a file-system event.
        /// - Parameters:
        ///   - path: The absolute path of the item that changed.
        ///   - eventType: The kind of change that occurred.
        public init(path: String, eventType: FSEvent) {
            self.path = path
            self.eventType = eventType
        }
    }

    /// Initialize the event stream and begin listening for events.
    /// - Parameters:
    ///   - directory: The directory to monitor.
    ///   - debounceDuration: The duration to delay notifications for to let the FS events API accumulate events.
    ///   - callback: A callback the stream will send events to.
    public init(directory: String, debounceDuration: TimeInterval = 0.1, callback: @escaping EventCallback) {
        self.debounceDuration = debounceDuration
        self.callback = callback
        self.eventQueue = DispatchQueue(label: "FileTools.DirectoryEventStream")
        eventQueue.setSpecific(key: Self.queueKey, value: ())

        let box = CallbackBox(owner: self)
        self.callbackBox = box
        let boxPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())

        var context = FSEventStreamContext(
            version: 0,
            info: boxPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let cfDirectory = directory as CFString
        let pathsToWatch = [cfDirectory] as CFArray

        // The context pointer is only valid inside this closure, so the
        // stream must be created here (FSEventStreamCreate copies the struct).
        let ref = withUnsafeMutablePointer(to: &context) { contextPtr in
            FSEventStreamCreate(
                kCFAllocatorDefault,
                { streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
                    guard let clientCallBackInfo else { return }
                    Unmanaged<CallbackBox>
                        .fromOpaque(clientCallBackInfo)
                        .takeUnretainedValue()
                        .owner?
                        .eventStreamHandler(streamRef, numEvents, eventPaths, eventFlags, eventIds)
                },
                contextPtr,
                pathsToWatch,
                UInt64(kFSEventStreamEventIdSinceNow),
                debounceDuration,
                // WatchRoot is required for kFSEventStreamEventFlagRootChanged to be
                // delivered at all — without it a rename/move of the watched root
                // leaves the stream silently watching the old, nonexistent path.
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseExtendedData
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagWatchRoot
                )
            )
        }

        if let ref {
            self.streamRef = ref
            FSEventStreamSetDispatchQueue(ref, eventQueue)
            FSEventStreamStart(ref)
        }
    }

    deinit {
        cancel()
    }

    /// Cancels the events watcher. Re-initialize to begin streaming again.
    ///
    /// Thread-safe and idempotent: teardown is serialized on the event queue,
    /// so it waits for any in-flight callback to finish and concurrent calls
    /// cannot double-release the stream.
    public func cancel() {
        // Run inline when already on the event queue (e.g. cancel() called
        // from inside the client callback) — `sync` there would deadlock.
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopStream()
        } else {
            eventQueue.sync { self.stopStream() }
        }
    }

    /// Must be called on `eventQueue`.
    private func stopStream() {
        guard let streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        self.streamRef = nil
    }

    /// Unpacks a raw FSEvents batch (extended-data dictionaries + flags) into
    /// ``Event`` values and forwards them to the client callback. Runs on
    /// `eventQueue`.
    private func eventStreamHandler(
        _ streamRef: ConstFSEventStreamRef,
        _ numEvents: Int,
        _ eventPaths: UnsafeMutableRawPointer,
        _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        _ eventIds: UnsafePointer<FSEventStreamEventId>
    ) {
        guard let eventDictionaries = unsafeBitCast(eventPaths, to: NSArray.self) as? [NSDictionary] else {
            return
        }

        var events: [Event] = []

        for (index, dictionary) in eventDictionaries.enumerated() {
            guard let path = dictionary[kFSEventStreamEventExtendedDataPathKey] as? String else {
                continue
            }
            let fsEvents = getEventsFromFlags(eventFlags[index])
            for event in fsEvents {
                events.append(.init(path: path, eventType: event))
            }
        }

        callback(events)
    }

    /// Parses ``FSEvent`` from the raw flag value. There can be multiple events in one raw flag.
    /// Internal (not private) so tests can exercise the flag mapping directly.
    func getEventsFromFlags(_ raw: FSEventStreamEventFlags) -> Set<FSEvent> {
        var events: Set<FSEvent> = []

        if raw & UInt32(kFSEventStreamEventFlagRootChanged) > 0 {
            events.insert(.rootChanged)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemChangeOwner) > 0 {
            events.insert(.itemChangedOwner)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCreated) > 0 {
            events.insert(.itemCreated)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCloned) > 0 {
            events.insert(.itemCloned)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemModified) > 0 {
            events.insert(.itemModified)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRemoved) > 0 {
            events.insert(.itemRemoved)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRenamed) > 0 {
            events.insert(.itemRenamed)
        }

        // raw == 0 (a plain "something in this directory changed") and flag
        // values with no recognized item bits — most importantly
        // kFSEventStreamEventFlagMustScanSubDirs, which FSEvents sends when
        // events were coalesced/dropped and the client MUST rescan — must not
        // be silently swallowed. Surface them as a generic directory change.
        if events.isEmpty {
            events.insert(.changeInDirectory)
        }

        return events
    }
}
