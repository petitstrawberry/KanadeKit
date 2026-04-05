import Foundation

enum WsResponse: Codable, Sendable, Equatable {
    case albums([Album])
    case albumTracks([Track])
    case artists([String])
    case artistAlbums([Album])
    case artistTracks([Track])
    case genres([String])
    case genreAlbums([Album])
    case genreTracks([Track])
    case searchResults([Track])
    case queue(tracks: [Track], currentIndex: Int?)

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private struct QueueData: Codable, Sendable, Equatable {
        let tracks: [Track]
        let currentIndex: Int?

        private enum CodingKeys: String, CodingKey {
            case tracks
            case currentIndex = "current_index"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        guard let key = container.allKeys.first else {
            throw KanadeError.unknownResponse("empty response data")
        }

        switch key.stringValue {
        case "albums":
            self = .albums(try container.decode([Album].self, forKey: key))
        case "album_tracks":
            self = .albumTracks(try container.decode([Track].self, forKey: key))
        case "artists":
            self = .artists(try container.decode([String].self, forKey: key))
        case "artist_albums":
            self = .artistAlbums(try container.decode([Album].self, forKey: key))
        case "artist_tracks":
            self = .artistTracks(try container.decode([Track].self, forKey: key))
        case "genres":
            self = .genres(try container.decode([String].self, forKey: key))
        case "genre_albums":
            self = .genreAlbums(try container.decode([Album].self, forKey: key))
        case "genre_tracks":
            self = .genreTracks(try container.decode([Track].self, forKey: key))
        case "search_results":
            self = .searchResults(try container.decode([Track].self, forKey: key))
        case "queue":
            let queueData = try container.decode(QueueData.self, forKey: key)
            self = .queue(tracks: queueData.tracks, currentIndex: queueData.currentIndex)
        default:
            throw KanadeError.unknownResponse(key.stringValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)

        switch self {
        case .albums(let albums):
            try container.encode(albums, forKey: DynamicCodingKeys(stringValue: "albums")!)
        case .albumTracks(let tracks):
            try container.encode(tracks, forKey: DynamicCodingKeys(stringValue: "album_tracks")!)
        case .artists(let artists):
            try container.encode(artists, forKey: DynamicCodingKeys(stringValue: "artists")!)
        case .artistAlbums(let albums):
            try container.encode(albums, forKey: DynamicCodingKeys(stringValue: "artist_albums")!)
        case .artistTracks(let tracks):
            try container.encode(tracks, forKey: DynamicCodingKeys(stringValue: "artist_tracks")!)
        case .genres(let genres):
            try container.encode(genres, forKey: DynamicCodingKeys(stringValue: "genres")!)
        case .genreAlbums(let albums):
            try container.encode(albums, forKey: DynamicCodingKeys(stringValue: "genre_albums")!)
        case .genreTracks(let tracks):
            try container.encode(tracks, forKey: DynamicCodingKeys(stringValue: "genre_tracks")!)
        case .searchResults(let tracks):
            try container.encode(tracks, forKey: DynamicCodingKeys(stringValue: "search_results")!)
        case .queue(let tracks, let currentIndex):
            try container.encode(
                QueueData(tracks: tracks, currentIndex: currentIndex),
                forKey: DynamicCodingKeys(stringValue: "queue")!
            )
        }
    }
}
