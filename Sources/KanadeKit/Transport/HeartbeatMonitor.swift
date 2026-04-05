import Foundation
import os

public final class HeartbeatMonitor: Sendable {
    public let timeout: TimeInterval
    private let lock = OSAllocatedUnfairLock(initialState: ContinuousClock.now)

    public init(timeout: TimeInterval = 45.0) {
        self.timeout = timeout
    }

    public func reset() {
        lock.withLock { $0 = ContinuousClock.now }
    }

    public func isTimedOut() -> Bool {
        let now = ContinuousClock.now
        return lock.withLock { now - $0 > .seconds(timeout) }
    }
}
