import Foundation
import Observation
@preconcurrency import Starscream
import os

protocol WsClientDelegate: AnyObject, Sendable {
    func clientDidConnect(_ client: WsClient)
    func clientDidDisconnect(_ client: WsClient, error: (any Error)?)
    func client(_ client: WsClient, didUpdateState state: PlaybackState)
    func client(_ client: WsClient, didReceiveError error: any Error)
}

    @Observable
final class WsClient: @unchecked Sendable {
    private(set) var state: PlaybackState?
    private(set) var connected: Bool = false
    private(set) var reconnectExhausted: Bool = false

    private struct PendingRequest: Sendable {
        let continuation: CheckedContinuation<WsResponse, any Error>
        let timeoutTask: Task<Void, Never>?
    }

    @ObservationIgnored private var _socket: WebSocket?
    @ObservationIgnored private var _reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var _heartbeatTask: Task<Void, Never>?
    private var _socketGeneration: UInt64 = 0
    private var _retryCount: Int = 0
    private let reqIdLock = OSAllocatedUnfairLock(initialState: UInt64(0))
    private var _active: Bool = false

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let reconnectPolicy: ReconnectPolicy
    @ObservationIgnored private let requestTimeout: TimeInterval
    @ObservationIgnored private let heartbeat: HeartbeatMonitor
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let tlsConfiguration: TLSConfiguration?

    @ObservationIgnored weak var delegate: (any WsClientDelegate)?

    @ObservationIgnored private let pendingRequestsLock = OSAllocatedUnfairLock(
        initialState: [UInt64: PendingRequest]()
    )

    init(
        url: URL,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeout: TimeInterval = 20.0,
        requestTimeout: TimeInterval = 10.0,
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        self.url = url
        self.reconnectPolicy = reconnectPolicy
        self.requestTimeout = requestTimeout
        self.heartbeat = HeartbeatMonitor(timeout: heartbeatTimeout)
        self.tlsConfiguration = tlsConfiguration
        self._heartbeatTask = startHeartbeatMonitor()
    }

    deinit {
        let socket = _socket
        _socket = nil
        _socketGeneration &+= 1
        _active = false
        _reconnectTask?.cancel()
        _reconnectTask = nil
        _heartbeatTask?.cancel()
        _heartbeatTask = nil
        socket?.disconnect()

        let continuations = pendingRequestsLock.withLock { pending -> [CheckedContinuation<WsResponse, any Error>] in
            let items = pending.values.map { $0.continuation }
            pending.removeAll()
            return items
        }
        for c in continuations { c.resume(throwing: KanadeError.connectionLost) }
    }

    func connect() {
        guard !_active else { return }
        _active = true
        reconnectExhausted = false
        startConnection()
    }

    func disconnect() {
        let socket = _socket
        let hadConnection = _socket != nil || _active
        _active = false
        _retryCount = 0
        reconnectExhausted = false
        _reconnectTask?.cancel()
        _reconnectTask = nil
        _socket = nil
        _socketGeneration &+= 1

        socket?.disconnect()
        rejectAllPending(with: KanadeError.connectionLost)

        guard hadConnection else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = false
            self.delegate?.clientDidDisconnect(self, error: nil)
        }
    }

    func send(_ command: WsCommand) {
        guard let data = try? encoder.encode(ClientMessage.command(command)),
              let string = String(data: data, encoding: .utf8) else { return }
        _socket?.write(string: string)
    }

    @discardableResult
    func request(_ request: WsRequest) async throws -> WsResponse {
        let reqId = nextReqId()

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.requestTimeout ?? 10.0))
                guard let self else { return }
                let removed = self.pendingRequestsLock.withLock { pending -> PendingRequest? in
                    pending.removeValue(forKey: reqId)
                }
                guard let removed else { return }
                removed.continuation.resume(throwing: KanadeError.requestTimeout(reqId: reqId))
            }

            pendingRequestsLock.withLock { pending in
                pending[reqId] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
            }

            guard let data = try? encoder.encode(ClientMessage.request(reqId: reqId, request: request)),
                  let string = String(data: data, encoding: .utf8) else {
                timeoutTask.cancel()
                _ = pendingRequestsLock.withLock { $0.removeValue(forKey: reqId) }
                continuation.resume(throwing: KanadeError.unknownRequest("encode failed"))
                return
            }

            _socket?.write(string: string)
        }
    }

    func sendRequest(req: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        switch req {
        case "sign_urls":
            guard let paths = data["paths"] as? [String] else {
                throw KanadeError.unknownRequest(req)
            }

            let response = try await request(.signURLs(paths: paths))
            guard case .signedURLs(let signedURLs) = response else {
                throw KanadeError.unknownResponse("signed_urls")
            }
            return ["signed_urls": signedURLs]
        default:
            throw KanadeError.unknownRequest(req)
        }
    }

    private func startConnection() {
        guard _active else { return }

        heartbeat.reset()
        _socketGeneration &+= 1
        let generation = _socketGeneration

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let socket: WebSocket
        if let tlsConfig = tlsConfiguration {
            let transport = MTLSTransport(configuration: tlsConfig)
            let engine = WSEngine(transport: transport, certPinner: nil)
            socket = WebSocket(request: request, engine: engine)
        } else {
            socket = WebSocket(request: request)
        }

        socket.onEvent = { [weak self] event in
            self?.handleEvent(event, generation: generation)
        }

        _socket?.disconnect()
        _socket = socket

        socket.connect()
    }

    private func handleEvent(_ event: WebSocketEvent, generation: UInt64) {
        guard generation == _socketGeneration else {
            switch event {
            case .disconnected(let reason, let code):
                print("[WsClient] ignoring stale .disconnected reason=\(String(describing: reason)) code=\(String(describing: code))")
            case .peerClosed:
                print("[WsClient] ignoring stale .peerClosed")
            case .error(let error):
                print("[WsClient] ignoring stale .error \(String(describing: error))")
            default:
                break
            }
            return
        }

        switch event {
        case .text(let string):
            print("[WsClient] .text \(string.prefix(100))")
        case .binary(let data):
            print("[WsClient] .binary \(data.count) bytes")
        case .error(let error):
            print("[WsClient] .error \(String(describing: error))")
        case .disconnected(let reason, let code):
            print("[WsClient] .disconnected reason=\(String(describing: reason)) code=\(String(describing: code))")
        case .peerClosed:
            print("[WsClient] .peerClosed")
        default:
            break
        }
        switch event {
        case .connected:
            heartbeat.reset()
            _retryCount = 0
            _reconnectTask = nil
            reconnectExhausted = false

            let reqId = nextReqId()

            if let data = try? encoder.encode(ClientMessage.request(reqId: reqId, request: .getQueue)),
               let string = String(data: data, encoding: .utf8) {
                _socket?.write(string: string)
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connected = true
                self.delegate?.clientDidConnect(self)
            }

        case .disconnected:
            let shouldReconnect = _active
            _socket = nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connected = false
                self.delegate?.clientDidDisconnect(self, error: KanadeError.connectionLost)
            }

            rejectAllPending(with: KanadeError.connectionLost)

            if shouldReconnect {
                scheduleReconnect()
            }

        case .text(let string):
            heartbeat.reset()
            if let data = string.data(using: .utf8) {
                handleDataMessage(data)
            }

        case .binary(let data):
            heartbeat.reset()
            handleDataMessage(data)

        case .error(let error):
            if let error {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.delegate?.client(self, didReceiveError: error)
                }
            }

        case .peerClosed:
            let shouldReconnect = _active
            _socket = nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connected = false
                self.delegate?.clientDidDisconnect(self, error: KanadeError.connectionLost)
            }

            rejectAllPending(with: KanadeError.connectionLost)

            if shouldReconnect {
                scheduleReconnect()
            }

        case .viabilityChanged(let isViable):
            if !isViable && _active {
                print("[WsClient] network became non-viable, forcing disconnect")
                let socket = _socket
                _socket = nil
                socket?.disconnect()

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.connected = false
                    self.delegate?.clientDidDisconnect(self, error: KanadeError.connectionLost)
                }

                rejectAllPending(with: KanadeError.connectionLost)
                scheduleReconnect()
            }

        case .pong:
            heartbeat.reset()

        case .ping:
            break

        case .reconnectSuggested:
            break

        case .cancelled:
            break
        }
    }

    private func handleDataMessage(_ data: Data) {
        do {
            let message = try decoder.decode(ServerMessage.self, from: data)
            switch message {
            case .state(let state):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state = state
                    self.connected = true
                    self.delegate?.client(self, didUpdateState: state)
                }
            case .response(let reqId, let response):
                let removed = pendingRequestsLock.withLock { pending -> PendingRequest? in
                    pending.removeValue(forKey: reqId)
                }
                removed?.timeoutTask?.cancel()
                removed?.continuation.resume(returning: response)
            case .mediaAuth:
                break
            }
        } catch {
            let msg = String(decoding: data, as: UTF8.self)
            print("[WsClient] decode error for \(msg.prefix(200)): \(error)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.client(self, didReceiveError: KanadeError.decodeFailed(underlying: error))
            }
        }
    }

    private func nextReqId() -> UInt64 {
        reqIdLock.withLock { id in
            id &+= 1
            return id
        }
    }

    private func startHeartbeatMonitor() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self._active else { return }
                guard self.connected else { continue }

                if self.heartbeat.isTimedOut() {
                    print("[WsClient] heartbeat timeout, forcing disconnect")
                    let socket = self._socket
                    self._socket = nil
                    socket?.disconnect()

                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.connected = false
                        self.delegate?.clientDidDisconnect(self, error: KanadeError.heartbeatTimeout)
                    }

                    self.rejectAllPending(with: KanadeError.heartbeatTimeout)
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard _active else { return }
        guard _reconnectTask == nil else { return }

        if _retryCount >= reconnectPolicy.maxAttempts {
            reconnectExhausted = true
            return
        }

        let delay = reconnectPolicy.nextDelay(retryCount: _retryCount)
        _retryCount += 1

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.startConnection()
        }

        _reconnectTask = task
    }

    private func rejectAllPending(with error: any Error) {
        let items = pendingRequestsLock.withLock { pending -> [PendingRequest] in
            let items = Array(pending.values)
            pending.removeAll()
            return items
        }
        for item in items {
            item.timeoutTask?.cancel()
            item.continuation.resume(throwing: error)
        }
    }
}

extension WsClientDelegate {
    func clientDidConnect(_ client: WsClient) {}
    func clientDidDisconnect(_ client: WsClient, error: (any Error)?) {}
    func client(_ client: WsClient, didUpdateState state: PlaybackState) {}
    func client(_ client: WsClient, didReceiveError error: any Error) {}
}
