import Synchronization

/// Thread-safe running totals updated by the scanner as it walks, and polled by
/// the UI so a long scan shows live activity instead of a frozen spinner.
public final class ScanProgress: Sendable {
    private let state = Mutex((files: 0, bytes: Int64(0)))

    public init() {}

    public func add(files: Int, bytes: Int64) {
        state.withLock { $0.files += files; $0.bytes += bytes }
    }

    public func snapshot() -> (files: Int, bytes: Int64) {
        state.withLock { ($0.files, $0.bytes) }
    }
}
