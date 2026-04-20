import Foundation

public struct ReconnectPolicy: Sendable {
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let base: Double
    public let maxAttempts: Int

    public init(
        initialDelay: TimeInterval = 3.0,
        maxDelay: TimeInterval = 5.0,
        base: Double = 2.0,
        maxAttempts: Int = 5
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.base = base
        self.maxAttempts = maxAttempts
    }

    public func nextDelay(retryCount: Int) -> TimeInterval {
        if retryCount == 0 { return initialDelay }
        return min(initialDelay * pow(base, Double(retryCount)), maxDelay)
    }
}
