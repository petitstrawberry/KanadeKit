import Foundation

public struct Node: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let connected: Bool
    public let nodeType: NodeType?
    public let queue: [Track]?
    public let currentIndex: Int?
    public let status: PlaybackStatus
    public let positionSecs: Double
    public let volume: Int
    public let repeatMode: RepeatMode?
    public let shuffle: Bool?

    public init(
        id: String,
        name: String,
        connected: Bool,
        nodeType: NodeType? = nil,
        queue: [Track]? = nil,
        currentIndex: Int? = nil,
        status: PlaybackStatus,
        positionSecs: Double,
        volume: Int,
        repeatMode: RepeatMode? = nil,
        shuffle: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.connected = connected
        self.nodeType = nodeType
        self.queue = queue
        self.currentIndex = currentIndex
        self.status = status
        self.positionSecs = positionSecs
        self.volume = volume
        self.repeatMode = repeatMode
        self.shuffle = shuffle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case connected
        case nodeType = "node_type"
        case queue
        case currentIndex = "current_index"
        case status
        case positionSecs = "position_secs"
        case volume
        case repeatMode = "repeat"
        case shuffle
    }
}
