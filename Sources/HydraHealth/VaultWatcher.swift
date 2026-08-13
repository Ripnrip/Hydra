import Foundation
import HydraCore

// MARK: - Vault Watcher

/// Watches a directory for file changes and emits hydration events.
/// Uses DispatchSource (FS events) — pure Swift, no bash.
/// Enables "watch mode": real-time context hydration when new plans/sessions land.
public actor VaultWatcher {
    private let watchPath: String
    private var fileDescriptor: CInt = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var streamContinuation: AsyncStream<String>.Continuation?

    public init(watchPath: String) throws {
        self.watchPath = watchPath
        let fd = open(watchPath, O_EVTONLY)
        guard fd >= 0 else {
            throw VaultWatcherError.failedToOpen(path: watchPath)
        }
        self.fileDescriptor = fd
    }

    deinit {
        dispatchSource?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    /// Start watching. Emits the path of each changed file.
    public func changes() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.streamContinuation = continuation

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .global(qos: .utility)
            )

            source.setEventHandler {
                Task { [weak self] in await self?.scanAndEmit() }
            }

            source.setCancelHandler {
                Task { [weak self] in await self?.finishStream() }
            }

            source.resume()
            self.dispatchSource = source
        }
    }

    /// Stop watching.
    public func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Private

    private func scanAndEmit() async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: watchPath) else { return }

        let now = Date()
        let recentCutoff = now.addingTimeInterval(-5)

        while let entry = enumerator.nextObject() as? String {
            guard entry.hasSuffix(".md") else { continue }
            let fullPath = (watchPath as NSString).appendingPathComponent(entry)

            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            if let modDate = attrs?[.modificationDate] as? Date, modDate > recentCutoff {
                streamContinuation?.yield(fullPath)
            }
        }
    }

    private func finishStream() {
        streamContinuation?.finish()
    }
}

public enum VaultWatcherError: Error, Sendable {
    case failedToOpen(path: String)
}
