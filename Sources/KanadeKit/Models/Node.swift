import Foundation

public struct Node: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let connected: Bool
    public let status: PlaybackStatus
    public let positionSecs: Double
    public let volume: Int

    public init(
        id: String,
        name: String,
        connected: Bool,
        status: PlaybackStatus,
        positionSecs: Double,
        volume: Int
    ) {
        self.id = id
        self.name = name
        self.connected = connected
        self.status = status
        self.positionSecs = positionSecs
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case connected
        case status
        case positionSecs = "position_secs"
        case volume
    }
}
