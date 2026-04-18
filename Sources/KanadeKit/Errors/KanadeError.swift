public enum KanadeError: Error, Sendable {
    case notConnected
    case connectionFailed(underlying: any Error)
    case connectionLost
    case heartbeatTimeout
    case decodeFailed(underlying: any Error)
    case requestTimeout(reqId: UInt64)
    case httpError(statusCode: Int)
    case unknownCommand(String)
    case unknownRequest(String)
    case unknownResponse(String)
    case unknownMessageType(String)
    case tlsError(String)
}
