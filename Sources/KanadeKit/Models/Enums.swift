import Foundation

public enum PlaybackStatus: String, Codable, Sendable, Equatable, Hashable {
    case stopped
    case playing
    case paused
    case loading
}

public enum RepeatMode: String, Codable, Sendable, Equatable, Hashable {
    case off
    case one
    case all
}
