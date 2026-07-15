//
//  GitRepoWatcher.swift
//  GitOrigin
//
//  Debounced FSEvents watcher for the open repo. Ignores .git internals to avoid refresh loops.
//

import CoreServices
import Foundation

@MainActor
final class GitRepoWatcher {
    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private var onChange: (() -> Void)?
    private var isPaused = false
    private var lastFiredAt: Date?

    private let minimumInterval: TimeInterval = 2.0
    private let debounceDelay: Duration = .milliseconds(800)

    func start(watching url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()

        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            [url.path as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        onChange = nil
        lastFiredAt = nil
        isPaused = false

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    func pause() {
        isPaused = true
        debounceTask?.cancel()
        debounceTask = nil
    }

    func resume() {
        isPaused = false
    }

    fileprivate func scheduleRefresh() {
        guard !isPaused else { return }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled, !isPaused else { return }

            if let lastFiredAt {
                let elapsed = Date().timeIntervalSince(lastFiredAt)
                if elapsed < minimumInterval {
                    try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
                    guard !Task.isCancelled, !isPaused else { return }
                }
            }

            lastFiredAt = Date()
            onChange?()
        }
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info, numEvents > 0 else { return }
        guard containsWorkingTreeChange(eventPaths: eventPaths, count: numEvents) else { return }

        let watcher = Unmanaged<GitRepoWatcher>.fromOpaque(info).takeUnretainedValue()
        Task { @MainActor in
            watcher.scheduleRefresh()
        }
    }

    private static func containsWorkingTreeChange(eventPaths: UnsafeRawPointer, count: Int) -> Bool {
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

        for path in paths {
            if path.hasSuffix("/.git") { continue }
            if path.contains("/.git/") { continue }
            return true
        }
        return false
    }
}
