import Foundation
import Testing
@testable import KanadeKit

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {
    @Test func firstRetryUsesInitialDelay() {
        let policy = ReconnectPolicy()
        #expect(policy.nextDelay(retryCount: 0) == 3.0)
    }

    @Test func exponentialBackoff() {
        let policy = ReconnectPolicy()
        #expect(policy.nextDelay(retryCount: 1) == 5.0)
        #expect(policy.nextDelay(retryCount: 2) == 5.0)
    }

    @Test func customPolicy() {
        let policy = ReconnectPolicy(initialDelay: 1.0, maxDelay: 30.0, base: 2.0)
        #expect(policy.nextDelay(retryCount: 0) == 1.0)
        #expect(policy.nextDelay(retryCount: 1) == 2.0)
        #expect(policy.nextDelay(retryCount: 2) == 4.0)
        #expect(policy.nextDelay(retryCount: 3) == 8.0)
        #expect(policy.nextDelay(retryCount: 4) == 16.0)
        #expect(policy.nextDelay(retryCount: 5) == 30.0)
    }

    @Test func maxDelayCapping() {
        let policy = ReconnectPolicy(initialDelay: 3.0, maxDelay: 5.0)
        #expect(policy.nextDelay(retryCount: 10) == 5.0)
    }
}

@Suite("HeartbeatMonitor")
struct HeartbeatMonitorTests {
    @Test func notTimedOutImmediately() {
        let monitor = HeartbeatMonitor(timeout: 45.0)
        #expect(!monitor.isTimedOut())
    }

    @Test func resetPreventsTimeout() {
        let monitor = HeartbeatMonitor(timeout: 0.1)
        monitor.reset()
        #expect(!monitor.isTimedOut())
        monitor.reset()
        #expect(!monitor.isTimedOut())
    }
}

@Suite("WsClient")
struct WsClientTests {
    @Test func initialState() {
        let client = WsClient(url: URL(string: "ws://localhost:8080")!)
        #expect(client.state == nil)
        #expect(!client.connected)
    }

    @Test func connectDisconnectWithoutServer() async {
        let client = WsClient(url: URL(string: "ws://localhost:1")!)
        client.connect()
        try? await Task.sleep(for: .milliseconds(500))
        client.disconnect()
        #expect(!client.connected)
    }
}
