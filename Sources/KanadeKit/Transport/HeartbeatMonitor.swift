import Foundation
import os

final class HeartbeatMonitor: Sendable {
    let timeout: TimeInterval
    private let lock = OSAllocatedUnfairLock(initialState: ContinuousClock.now)

    init(timeout: TimeInterval = 45.0) {
        self.timeout = timeout
    }

    func reset() {
        lock.withLock { $0 = ContinuousClock.now }
    }

    func isTimedOut() -> Bool {
        let now = ContinuousClock.now
        return lock.withLock { now - $0 > .seconds(timeout) }
    }
}
