import Foundation
import Observation
import os

public protocol WsClientDelegate: AnyObject, Sendable {
    func clientDidConnect(_ client: WsClient)
    func clientDidDisconnect(_ client: WsClient, error: (any Error)?)
    func client(_ client: WsClient, didUpdateState state: PlaybackState)
    func client(_ client: WsClient, didReceiveError error: any Error)
}

extension WsClient: @unchecked Sendable {}

@Observable
public final class WsClient {
    public private(set) var state: PlaybackState?
    public private(set) var connected: Bool = false

    private struct QueuedMessage: Sendable {
        let data: Data
        let requestId: UInt64?
    }

    private struct InternalState {
        var wsTask: URLSessionWebSocketTask?
        var receiveTask: Task<Void, Never>?
        var heartbeatTask: Task<Void, Never>?
        var reconnectTask: Task<Void, Never>?
        var retryCount: Int = 0
        var nextReqId: UInt64 = 0
        var active: Bool = false
        var readyToSend: Bool = false
    }

    private struct ConnectionResources {
        let wsTask: URLSessionWebSocketTask?
        let receiveTask: Task<Void, Never>?
        let heartbeatTask: Task<Void, Never>?
    }

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let reconnectPolicy: ReconnectPolicy
    @ObservationIgnored private let requestTimeout: TimeInterval
    @ObservationIgnored private let heartbeat: HeartbeatMonitor

    @ObservationIgnored public weak var delegate: (any WsClientDelegate)?

    @ObservationIgnored private let internalState = OSAllocatedUnfairLock(initialState: InternalState())
    @ObservationIgnored private let pendingRequestsLock = OSAllocatedUnfairLock(
        initialState: [UInt64: CheckedContinuation<WsResponse, any Error>]()
    )
    @ObservationIgnored private let sendQueueLock = OSAllocatedUnfairLock(initialState: [QueuedMessage]())

    public init(
        url: URL,
        session: URLSession = .shared,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeout: TimeInterval = 45.0,
        requestTimeout: TimeInterval = 10.0
    ) {
        self.url = url
        self.session = session
        self.reconnectPolicy = reconnectPolicy
        self.requestTimeout = requestTimeout
        self.heartbeat = HeartbeatMonitor(timeout: heartbeatTimeout)
    }

    deinit {
        let teardown = internalState.withLock { state -> (ConnectionResources, Task<Void, Never>?) in
            let resources = ConnectionResources(
                wsTask: state.wsTask,
                receiveTask: state.receiveTask,
                heartbeatTask: state.heartbeatTask
            )
            let reconnectTask = state.reconnectTask
            state.wsTask = nil
            state.receiveTask = nil
            state.heartbeatTask = nil
            state.reconnectTask = nil
            state.readyToSend = false
            state.active = false
            return (resources, reconnectTask)
        }

        teardown.0.receiveTask?.cancel()
        teardown.0.heartbeatTask?.cancel()
        teardown.1?.cancel()
        teardown.0.wsTask?.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)

        let continuations = pendingRequestsLock.withLock { pending -> [CheckedContinuation<WsResponse, any Error>] in
            let continuations = Array(pending.values)
            pending.removeAll()
            return continuations
        }

        for continuation in continuations {
            continuation.resume(throwing: KanadeError.connectionLost)
        }
    }

    public func connect() {
        let shouldStart = internalState.withLock { state -> Bool in
            guard !state.active else { return false }
            state.active = true
            return true
        }

        guard shouldStart else { return }
        startConnection()
    }

    public func disconnect() {
        let teardown = internalState.withLock { state -> (ConnectionResources, Task<Void, Never>?, Bool) in
            let hadConnection = state.active || state.wsTask != nil || state.receiveTask != nil || state.heartbeatTask != nil || state.readyToSend
            state.active = false
            state.retryCount = 0
            state.readyToSend = false

            let resources = ConnectionResources(
                wsTask: state.wsTask,
                receiveTask: state.receiveTask,
                heartbeatTask: state.heartbeatTask
            )
            let reconnectTask = state.reconnectTask

            state.wsTask = nil
            state.receiveTask = nil
            state.heartbeatTask = nil
            state.reconnectTask = nil

            return (resources, reconnectTask, hadConnection)
        }

        teardown.0.receiveTask?.cancel()
        teardown.0.heartbeatTask?.cancel()
        teardown.1?.cancel()
        teardown.0.wsTask?.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)

        rejectAllPendingRequests(with: KanadeError.connectionLost)
        sendQueueLock.withLock { $0.removeAll() }

        guard teardown.2 else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = false
            self.delegate?.clientDidDisconnect(self, error: nil)
        }
    }

    public func send(_ command: WsCommand) {
        enqueueSend(.command(command), requestId: nil)
    }

    @discardableResult
    public func request(_ request: WsRequest) async throws -> WsResponse {
        let reqId = internalState.withLock { state -> UInt64 in
            let reqId = state.nextReqId
            state.nextReqId &+= 1
            return reqId
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequestsLock.withLock { pending in
                pending[reqId] = continuation
            }

            enqueueSend(.request(reqId: reqId, request: request), requestId: reqId)

            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.requestTimeout))

                let continuation = self.pendingRequestsLock.withLock { pending in
                    pending.removeValue(forKey: reqId)
                }

                guard let continuation else { return }

                self.removeQueuedRequest(with: reqId)
                continuation.resume(throwing: KanadeError.requestTimeout(reqId: reqId))
            }
        }
    }

    private func startConnection() {
        let isActive = internalState.withLock { $0.active }
        guard isActive else { return }

        heartbeat.reset()

        let previousResources = internalState.withLock { state -> ConnectionResources in
            let resources = ConnectionResources(
                wsTask: state.wsTask,
                receiveTask: state.receiveTask,
                heartbeatTask: state.heartbeatTask
            )
            state.wsTask = nil
            state.receiveTask = nil
            state.heartbeatTask = nil
            state.reconnectTask = nil
            state.readyToSend = false
            return resources
        }

        previousResources.receiveTask?.cancel()
        previousResources.heartbeatTask?.cancel()
        previousResources.wsTask?.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)

        let wsTask = session.webSocketTask(with: url)
        wsTask.resume()

        let receiveTask = Task { [weak self, wsTask] in
            guard let self else { return }

            do {
                while !Task.isCancelled {
                    let message = try await wsTask.receive()
                    self.heartbeat.reset()

                    let data: Data
                    switch message {
                    case .string(let text):
                        data = Data(text.utf8)
                    case .data(let rawData):
                        data = rawData
                    @unknown default:
                        continue
                    }

                    do {
                        let serverMessage = try JSONDecoder().decode(ServerMessage.self, from: data)
                        await MainActor.run {
                            self.handleServerMessage(serverMessage)
                        }
                    } catch {
                        self.reportError(KanadeError.decodeFailed(underlying: error))
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.handleDisconnect(error: error)
                }
            }
        }

        let heartbeatTask = Task { [weak self] in
            guard let self else { return }

            let interval = max(1.0, min(self.heartbeat.timeout / 2.0, 5.0))

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }

                if self.heartbeat.isTimedOut() {
                    await MainActor.run {
                        self.handleDisconnect(error: KanadeError.heartbeatTimeout)
                    }
                    return
                }
            }
        }

        internalState.withLock { state in
            state.wsTask = wsTask
            state.receiveTask = receiveTask
            state.heartbeatTask = heartbeatTask
        }
    }

    @MainActor
    private func handleServerMessage(_ message: ServerMessage) {
        switch message {
        case .state(let state):
            let didConnect = internalState.withLock { state -> Bool in
                let didConnect = !state.readyToSend
                state.readyToSend = true
                state.retryCount = 0
                state.reconnectTask = nil
                return didConnect
            }

            self.state = state
            self.connected = true

            if didConnect {
                delegate?.clientDidConnect(self)
                flushSendQueue()
            }

            delegate?.client(self, didUpdateState: state)

        case .response(let reqId, let response):
            let continuation = pendingRequestsLock.withLock { pending in
                pending.removeValue(forKey: reqId)
            }

            removeQueuedRequest(with: reqId)
            continuation?.resume(returning: response)
        }
    }

    @MainActor
    private func handleDisconnect(error: (any Error)?) {
        let teardown = internalState.withLock { state -> (ConnectionResources, Bool, Bool) in
            let hadConnection = state.wsTask != nil || state.receiveTask != nil || state.heartbeatTask != nil || state.readyToSend
            let resources = ConnectionResources(
                wsTask: state.wsTask,
                receiveTask: state.receiveTask,
                heartbeatTask: state.heartbeatTask
            )

            state.wsTask = nil
            state.receiveTask = nil
            state.heartbeatTask = nil
            state.readyToSend = false

            return (resources, hadConnection, state.active)
        }

        teardown.0.receiveTask?.cancel()
        teardown.0.heartbeatTask?.cancel()
        teardown.0.wsTask?.cancel(with: URLSessionWebSocketTask.CloseCode.goingAway, reason: nil)

        connected = false

        guard teardown.1 else { return }

        rejectAllPendingRequests(with: error ?? KanadeError.connectionLost)
        removeQueuedRequests()
        delegate?.clientDidDisconnect(self, error: error)

        if teardown.2 {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        let reconnectPolicy = self.reconnectPolicy

        let previousTask = internalState.withLock { state in
            let previousTask = state.reconnectTask
            state.reconnectTask = nil
            return previousTask
        }
        previousTask?.cancel()

        let delay = internalState.withLock { state -> TimeInterval? in
            guard state.active else { return nil }
            let delay = reconnectPolicy.nextDelay(retryCount: state.retryCount)
            state.retryCount += 1
            return delay
        }

        guard let delay else { return }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.startConnection()
        }

        internalState.withLock { state in
            guard state.active else {
                task.cancel()
                return
            }
            state.reconnectTask = task
        }
    }

    private func enqueueSend(_ message: ClientMessage, requestId: UInt64?) {
        guard let data = try? JSONEncoder().encode(message) else { return }

        let queuedMessage = QueuedMessage(data: data, requestId: requestId)
        let wsTask = internalState.withLock { state -> URLSessionWebSocketTask? in
            guard state.readyToSend else { return nil }
            return state.wsTask
        }

        guard let wsTask else {
            sendQueueLock.withLock { $0.append(queuedMessage) }
            return
        }

        sendImmediate(queuedMessage, over: wsTask)
    }

    private func sendImmediate(_ queuedMessage: QueuedMessage, over wsTask: URLSessionWebSocketTask) {
        wsTask.send(.data(queuedMessage.data)) { [weak self] error in
            guard let self, let error else { return }

            if queuedMessage.requestId == nil {
                self.sendQueueLock.withLock { queue in
                    queue.insert(queuedMessage, at: 0)
                }
            }

            self.reportError(error)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleDisconnect(error: error)
            }
        }
    }

    private func flushSendQueue() {
        let wsTask = internalState.withLock { state -> URLSessionWebSocketTask? in
            guard state.readyToSend else { return nil }
            return state.wsTask
        }

        guard let wsTask else { return }

        let queuedMessages = sendQueueLock.withLock { queue -> [QueuedMessage] in
            let queuedMessages = queue
            queue.removeAll()
            return queuedMessages
        }

        for queuedMessage in queuedMessages {
            sendImmediate(queuedMessage, over: wsTask)
        }
    }

    private func rejectAllPendingRequests(with error: any Error) {
        let continuations = pendingRequestsLock.withLock { pending -> [CheckedContinuation<WsResponse, any Error>] in
            let continuations = Array(pending.values)
            pending.removeAll()
            return continuations
        }

        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func removeQueuedRequest(with reqId: UInt64) {
        sendQueueLock.withLock { queue in
            queue.removeAll { $0.requestId == reqId }
        }
    }

    private func removeQueuedRequests() {
        sendQueueLock.withLock { queue in
            queue.removeAll { $0.requestId != nil }
        }
    }

    private func reportError(_ error: any Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.client(self, didReceiveError: error)
        }
    }
}
