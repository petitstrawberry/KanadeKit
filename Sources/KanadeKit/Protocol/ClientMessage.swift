import Foundation

enum ClientMessage: Codable, Sendable, Equatable {
    case command(WsCommand)
    case request(reqId: UInt64, request: WsRequest)

    private enum CodingKeys: String, CodingKey {
        case cmd
        case reqId = "req_id"
        case req
        case positionSecs = "position_secs"
        case volume
        case repeatMode = "repeat"
        case shuffle
        case nodeId = "node_id"
        case track
        case tracks
        case index
        case from
        case to
        case albumId = "album_id"
        case artist
        case genre
        case query
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.cmd) {
            let cmd = try container.decode(String.self, forKey: .cmd)

            switch cmd {
            case "play":
                self = .command(.play)
            case "pause":
                self = .command(.pause)
            case "stop":
                self = .command(.stop)
            case "next":
                self = .command(.next)
            case "previous":
                self = .command(.previous)
            case "seek":
                self = .command(.seek(positionSecs: try container.decode(Double.self, forKey: .positionSecs)))
            case "set_volume":
                self = .command(.setVolume(volume: try container.decode(Int.self, forKey: .volume)))
            case "set_repeat":
                self = .command(.setRepeat(repeatMode: try container.decode(RepeatMode.self, forKey: .repeatMode)))
            case "set_shuffle":
                self = .command(.setShuffle(shuffle: try container.decode(Bool.self, forKey: .shuffle)))
            case "select_node":
                self = .command(.selectNode(nodeId: try container.decode(String.self, forKey: .nodeId)))
            case "add_to_queue":
                self = .command(.addToQueue(track: try container.decode(Track.self, forKey: .track)))
            case "add_tracks_to_queue":
                self = .command(.addTracksToQueue(tracks: try container.decode([Track].self, forKey: .tracks)))
            case "play_index":
                self = .command(.playIndex(index: try container.decode(Int.self, forKey: .index)))
            case "remove_from_queue":
                self = .command(.removeFromQueue(index: try container.decode(Int.self, forKey: .index)))
            case "move_in_queue":
                self = .command(
                    .moveInQueue(
                        from: try container.decode(Int.self, forKey: .from),
                        to: try container.decode(Int.self, forKey: .to)
                    )
                )
            case "clear_queue":
                self = .command(.clearQueue)
            case "replace_and_play":
                self = .command(
                    .replaceAndPlay(
                        tracks: try container.decode([Track].self, forKey: .tracks),
                        index: try container.decode(Int.self, forKey: .index)
                    )
                )
            default:
                throw KanadeError.unknownCommand(cmd)
            }

            return
        }

        if container.contains(.reqId) {
            let reqId = try container.decode(UInt64.self, forKey: .reqId)
            let req = try container.decode(String.self, forKey: .req)

            switch req {
            case "get_albums":
                self = .request(reqId: reqId, request: .getAlbums)
            case "get_album_tracks":
                self = .request(
                    reqId: reqId,
                    request: .getAlbumTracks(albumId: try container.decode(String.self, forKey: .albumId))
                )
            case "get_artists":
                self = .request(reqId: reqId, request: .getArtists)
            case "get_artist_albums":
                self = .request(
                    reqId: reqId,
                    request: .getArtistAlbums(artist: try container.decode(String.self, forKey: .artist))
                )
            case "get_artist_tracks":
                self = .request(
                    reqId: reqId,
                    request: .getArtistTracks(artist: try container.decode(String.self, forKey: .artist))
                )
            case "get_genres":
                self = .request(reqId: reqId, request: .getGenres)
            case "get_genre_albums":
                self = .request(
                    reqId: reqId,
                    request: .getGenreAlbums(genre: try container.decode(String.self, forKey: .genre))
                )
            case "get_genre_tracks":
                self = .request(
                    reqId: reqId,
                    request: .getGenreTracks(genre: try container.decode(String.self, forKey: .genre))
                )
            case "search":
                self = .request(
                    reqId: reqId,
                    request: .search(query: try container.decode(String.self, forKey: .query))
                )
            case "get_queue":
                self = .request(reqId: reqId, request: .getQueue)
            default:
                throw KanadeError.unknownRequest(req)
            }

            return
        }

        let keys = container.allKeys.map(\.stringValue).sorted().joined(separator: ", ")
        throw KanadeError.unknownMessageType("missing cmd or req_id, got: [\(keys)]")
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .command(let command):
            try command.encode(to: encoder)
        case .request(let reqId, let request):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reqId, forKey: .reqId)

            switch request {
            case .getAlbums:
                try container.encode("get_albums", forKey: .req)
            case .getAlbumTracks(let albumId):
                try container.encode("get_album_tracks", forKey: .req)
                try container.encode(albumId, forKey: .albumId)
            case .getArtists:
                try container.encode("get_artists", forKey: .req)
            case .getArtistAlbums(let artist):
                try container.encode("get_artist_albums", forKey: .req)
                try container.encode(artist, forKey: .artist)
            case .getArtistTracks(let artist):
                try container.encode("get_artist_tracks", forKey: .req)
                try container.encode(artist, forKey: .artist)
            case .getGenres:
                try container.encode("get_genres", forKey: .req)
            case .getGenreAlbums(let genre):
                try container.encode("get_genre_albums", forKey: .req)
                try container.encode(genre, forKey: .genre)
            case .getGenreTracks(let genre):
                try container.encode("get_genre_tracks", forKey: .req)
                try container.encode(genre, forKey: .genre)
            case .search(let query):
                try container.encode("search", forKey: .req)
                try container.encode(query, forKey: .query)
            case .getQueue:
                try container.encode("get_queue", forKey: .req)
            }
        }
    }
}
