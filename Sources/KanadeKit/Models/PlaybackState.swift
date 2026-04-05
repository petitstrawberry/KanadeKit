import Foundation

public struct PlaybackState: Codable, Sendable, Equatable, Hashable {
    public let nodes: [Node]
    public let selectedNodeId: String?
    public let queue: [Track]
    public let currentIndex: Int?
    public let shuffle: Bool
    public let repeatMode: RepeatMode

    public init(
        nodes: [Node],
        selectedNodeId: String? = nil,
        queue: [Track],
        currentIndex: Int? = nil,
        shuffle: Bool,
        repeatMode: RepeatMode
    ) {
        self.nodes = nodes
        self.selectedNodeId = selectedNodeId
        self.queue = queue
        self.currentIndex = currentIndex
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    private enum CodingKeys: String, CodingKey {
        case nodes
        case selectedNodeId = "selected_node_id"
        case queue
        case currentIndex = "current_index"
        case shuffle
        case repeatMode = "repeat"
    }
}
