import Foundation

/// Tri-state update for optional fields (e.g. `description` on `update_playlist`).
///
/// Maps to Rust's `Option<Option<T>>`:
/// - `.unchanged`: field omitted from JSON (no change)
/// - `.clear`: field encoded as `null` (clear the value)
/// - `.set(value)`: field encoded with the value
public enum DescriptionUpdate: Sendable, Equatable {
    case unchanged
    case clear
    case set(String)
}

enum WsCommand: Codable, Sendable, Equatable {
    case play
    case pause
    case stop
    case next
    case previous
    case seek(positionSecs: Double)
    case setVolume(volume: Int)
    case setRepeat(repeatMode: RepeatMode)
    case setShuffle(shuffle: Bool)
    case selectNode(nodeId: String)
    case addToQueue(track: Track)
    case addTracksToQueue(tracks: [Track])
    case playIndex(index: Int)
    case removeFromQueue(index: Int)
    case moveInQueue(from: Int, to: Int)
    case clearQueue
    case replaceAndPlay(tracks: [Track], index: Int)
    case localSessionStart(deviceName: String, deviceId: String?)
    case localSessionStop
    case localSessionUpdate(queue: [Track]?, currentIndex: Int?, positionSecs: Double, status: PlaybackStatus, volume: Int, repeatMode: RepeatMode, shuffle: Bool)
    case handoff(fromNodeId: String, toNodeId: String)
    case createPlaylist(name: String, description: String?, kind: PlaylistKind, filter: SmartFilter?, limit: Int?, sortBy: SmartSort?)
    case updatePlaylist(playlistId: String, name: String?, description: DescriptionUpdate, kind: PlaylistKind?)
    case deletePlaylist(playlistId: String)
    case setPlaylistTracks(playlistId: String, trackIds: [String])
    case appendPlaylistTracks(playlistId: String, trackIds: [String])
    case removePlaylistTrack(playlistId: String, position: Int)
    case movePlaylistTrack(playlistId: String, from: Int, to: Int)

    private enum CodingKeys: String, CodingKey {
        case cmd
        case deviceName = "device_name"
        case deviceId = "device_id"
        case positionSecs = "position_secs"
        case status
        case volume
        case repeatMode = "repeat"
        case shuffle
        case fromNodeId = "from_node_id"
        case nodeId = "node_id"
        case toNodeId = "to_node_id"
        case track
        case tracks
        case index
        case from
        case to
        case name
        case description
        case kind
        case filter
        case limit
        case sortBy = "sort_by"
        case playlistId = "playlist_id"
        case trackIds = "track_ids"
        case position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cmd = try container.decode(String.self, forKey: .cmd)

        switch cmd {
        case "play":
            self = .play
        case "pause":
            self = .pause
        case "stop":
            self = .stop
        case "next":
            self = .next
        case "previous":
            self = .previous
        case "seek":
            self = .seek(positionSecs: try container.decode(Double.self, forKey: .positionSecs))
        case "set_volume":
            self = .setVolume(volume: try container.decode(Int.self, forKey: .volume))
        case "set_repeat":
            self = .setRepeat(repeatMode: try container.decode(RepeatMode.self, forKey: .repeatMode))
        case "set_shuffle":
            self = .setShuffle(shuffle: try container.decode(Bool.self, forKey: .shuffle))
        case "select_node":
            self = .selectNode(nodeId: try container.decode(String.self, forKey: .nodeId))
        case "add_to_queue":
            self = .addToQueue(track: try container.decode(Track.self, forKey: .track))
        case "add_tracks_to_queue":
            self = .addTracksToQueue(tracks: try container.decode([Track].self, forKey: .tracks))
        case "play_index":
            self = .playIndex(index: try container.decode(Int.self, forKey: .index))
        case "remove_from_queue":
            self = .removeFromQueue(index: try container.decode(Int.self, forKey: .index))
        case "move_in_queue":
            self = .moveInQueue(
                from: try container.decode(Int.self, forKey: .from),
                to: try container.decode(Int.self, forKey: .to)
            )
        case "clear_queue":
            self = .clearQueue
        case "replace_and_play":
            self = .replaceAndPlay(
                tracks: try container.decode([Track].self, forKey: .tracks),
                index: try container.decode(Int.self, forKey: .index)
            )
         case "local_session_start":
            let deviceName = try container.decode(String.self, forKey: .deviceName)
            let deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
            self = .localSessionStart(deviceName: deviceName, deviceId: deviceId)
        case "local_session_stop":
            self = .localSessionStop
        case "local_session_update":
            let queue = try container.decodeIfPresent([Track].self, forKey: .tracks)
            let currentIndex = try container.decodeIfPresent(Int.self, forKey: .index)
            let positionSecs = try container.decode(Double.self, forKey: .positionSecs)
            let status = try container.decode(PlaybackStatus.self, forKey: .status)
            let volume = try container.decode(Int.self, forKey: .volume)
            let repeatMode = try container.decode(RepeatMode.self, forKey: .repeatMode)
            let shuffle = try container.decode(Bool.self, forKey: .shuffle)
            self = .localSessionUpdate(
                queue: queue,
                currentIndex: currentIndex,
                positionSecs: positionSecs,
                status: status,
                volume: volume,
                repeatMode: repeatMode,
                shuffle: shuffle
            )
        case "handoff":
            self = .handoff(
                fromNodeId: try container.decode(String.self, forKey: .fromNodeId),
                toNodeId: try container.decode(String.self, forKey: .toNodeId)
            )
        case "create_playlist":
            self = .createPlaylist(
                name: try container.decode(String.self, forKey: .name),
                description: try container.decodeIfPresent(String.self, forKey: .description),
                kind: try container.decode(PlaylistKind.self, forKey: .kind),
                filter: try container.decodeIfPresent(SmartFilter.self, forKey: .filter),
                limit: try container.decodeIfPresent(Int.self, forKey: .limit),
                sortBy: try container.decodeIfPresent(SmartSort.self, forKey: .sortBy)
            )
        case "update_playlist":
            let descriptionUpdate: DescriptionUpdate
            if container.contains(.description) {
                if try container.decodeNil(forKey: .description) {
                    descriptionUpdate = .clear
                } else {
                    descriptionUpdate = .set(try container.decode(String.self, forKey: .description))
                }
            } else {
                descriptionUpdate = .unchanged
            }
            self = .updatePlaylist(
                playlistId: try container.decode(String.self, forKey: .playlistId),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                description: descriptionUpdate,
                kind: try container.decodeIfPresent(PlaylistKind.self, forKey: .kind)
            )
        case "delete_playlist":
            self = .deletePlaylist(playlistId: try container.decode(String.self, forKey: .playlistId))
        case "set_playlist_tracks":
            self = .setPlaylistTracks(
                playlistId: try container.decode(String.self, forKey: .playlistId),
                trackIds: try container.decode([String].self, forKey: .trackIds)
            )
        case "append_playlist_tracks":
            self = .appendPlaylistTracks(
                playlistId: try container.decode(String.self, forKey: .playlistId),
                trackIds: try container.decode([String].self, forKey: .trackIds)
            )
        case "remove_playlist_track":
            self = .removePlaylistTrack(
                playlistId: try container.decode(String.self, forKey: .playlistId),
                position: try container.decode(Int.self, forKey: .position)
            )
        case "move_playlist_track":
            self = .movePlaylistTrack(
                playlistId: try container.decode(String.self, forKey: .playlistId),
                from: try container.decode(Int.self, forKey: .from),
                to: try container.decode(Int.self, forKey: .to)
            )
        default:
            throw KanadeError.unknownCommand(cmd)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .play:
            try container.encode("play", forKey: .cmd)
        case .pause:
            try container.encode("pause", forKey: .cmd)
        case .stop:
            try container.encode("stop", forKey: .cmd)
        case .next:
            try container.encode("next", forKey: .cmd)
        case .previous:
            try container.encode("previous", forKey: .cmd)
        case .seek(let positionSecs):
            try container.encode("seek", forKey: .cmd)
            try container.encode(positionSecs, forKey: .positionSecs)
        case .setVolume(let volume):
            try container.encode("set_volume", forKey: .cmd)
            try container.encode(volume, forKey: .volume)
        case .setRepeat(let repeatMode):
            try container.encode("set_repeat", forKey: .cmd)
            try container.encode(repeatMode, forKey: .repeatMode)
        case .setShuffle(let shuffle):
            try container.encode("set_shuffle", forKey: .cmd)
            try container.encode(shuffle, forKey: .shuffle)
        case .selectNode(let nodeId):
            try container.encode("select_node", forKey: .cmd)
            try container.encode(nodeId, forKey: .nodeId)
        case .addToQueue(let track):
            try container.encode("add_to_queue", forKey: .cmd)
            try container.encode(track, forKey: .track)
        case .addTracksToQueue(let tracks):
            try container.encode("add_tracks_to_queue", forKey: .cmd)
            try container.encode(tracks, forKey: .tracks)
        case .playIndex(let index):
            try container.encode("play_index", forKey: .cmd)
            try container.encode(index, forKey: .index)
        case .removeFromQueue(let index):
            try container.encode("remove_from_queue", forKey: .cmd)
            try container.encode(index, forKey: .index)
        case .moveInQueue(let from, let to):
            try container.encode("move_in_queue", forKey: .cmd)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .clearQueue:
            try container.encode("clear_queue", forKey: .cmd)
        case .replaceAndPlay(let tracks, let index):
            try container.encode("replace_and_play", forKey: .cmd)
            try container.encode(tracks, forKey: .tracks)
            try container.encode(index, forKey: .index)
         case .localSessionStart(let deviceName, let deviceId):
            try container.encode("local_session_start", forKey: .cmd)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encodeIfPresent(deviceId, forKey: .deviceId)
        case .localSessionStop:
            try container.encode("local_session_stop", forKey: .cmd)
        case .localSessionUpdate(let queue, let currentIndex, let positionSecs, let status, let volume, let repeatMode, let shuffle):
            try container.encode("local_session_update", forKey: .cmd)
            try container.encodeIfPresent(queue, forKey: .tracks)
            try container.encodeIfPresent(currentIndex, forKey: .index)
            try container.encode(positionSecs, forKey: .positionSecs)
            try container.encode(status, forKey: .status)
            try container.encode(volume, forKey: .volume)
            try container.encode(repeatMode, forKey: .repeatMode)
            try container.encode(shuffle, forKey: .shuffle)
        case .handoff(let fromNodeId, let toNodeId):
            try container.encode("handoff", forKey: .cmd)
            try container.encode(fromNodeId, forKey: .fromNodeId)
            try container.encode(toNodeId, forKey: .toNodeId)
        case .createPlaylist(let name, let description, let kind, let filter, let limit, let sortBy):
            try container.encode("create_playlist", forKey: .cmd)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(filter, forKey: .filter)
            try container.encodeIfPresent(limit, forKey: .limit)
            try container.encodeIfPresent(sortBy, forKey: .sortBy)
        case .updatePlaylist(let playlistId, let name, let description, let kind):
            try container.encode("update_playlist", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
            try container.encodeIfPresent(name, forKey: .name)
            switch description {
            case .unchanged:
                break
            case .clear:
                try container.encodeNil(forKey: .description)
            case .set(let value):
                try container.encode(value, forKey: .description)
            }
            try container.encodeIfPresent(kind, forKey: .kind)
        case .deletePlaylist(let playlistId):
            try container.encode("delete_playlist", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
        case .setPlaylistTracks(let playlistId, let trackIds):
            try container.encode("set_playlist_tracks", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
            try container.encode(trackIds, forKey: .trackIds)
        case .appendPlaylistTracks(let playlistId, let trackIds):
            try container.encode("append_playlist_tracks", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
            try container.encode(trackIds, forKey: .trackIds)
        case .removePlaylistTrack(let playlistId, let position):
            try container.encode("remove_playlist_track", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
            try container.encode(position, forKey: .position)
        case .movePlaylistTrack(let playlistId, let from, let to):
            try container.encode("move_playlist_track", forKey: .cmd)
            try container.encode(playlistId, forKey: .playlistId)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        }
    }
}
