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
    case signedURLs([String: String])
    case playlists([Playlist])
    case playlistDetails(Playlist?)
    case playlistTracks(playlistId: String, tracks: [Track])

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

    private struct NestedAlbums: Codable, Sendable, Equatable { let albums: [Album] }
    private struct NestedTracks: Codable, Sendable, Equatable { let tracks: [Track] }
    private struct NestedArtists: Codable, Sendable, Equatable { let artists: [String] }
    private struct NestedGenres: Codable, Sendable, Equatable { let genres: [String] }
    private struct QueueData: Codable, Sendable, Equatable {
        let tracks: [Track]
        let currentIndex: Int?

        private enum CodingKeys: String, CodingKey {
            case tracks
            case currentIndex = "current_index"
        }
    }

    private struct SignedURLsData: Codable, Sendable, Equatable {
        let urls: [String: String]

        private enum CodingKeys: String, CodingKey {
            case urls
        }
    }

    private struct NestedPlaylists: Codable, Sendable, Equatable { let playlists: [Playlist] }
    private struct PlaylistDetailsData: Codable, Sendable, Equatable { let playlist: Playlist? }
    private struct PlaylistTracksData: Codable, Sendable, Equatable {
        let playlistId: String
        let tracks: [Track]

        private enum CodingKeys: String, CodingKey {
            case playlistId = "playlist_id"
            case tracks
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        guard let key = container.allKeys.first else {
            throw KanadeError.unknownResponse("empty response data")
        }

        switch key.stringValue {
        case "albums":
            let nested = try container.decode(NestedAlbums.self, forKey: key)
            self = .albums(nested.albums)
        case "album_tracks":
            let nested = try container.decode(NestedTracks.self, forKey: key)
            self = .albumTracks(nested.tracks)
        case "artists":
            let nested = try container.decode(NestedArtists.self, forKey: key)
            self = .artists(nested.artists)
        case "artist_albums":
            let nested = try container.decode(NestedAlbums.self, forKey: key)
            self = .artistAlbums(nested.albums)
        case "artist_tracks":
            let nested = try container.decode(NestedTracks.self, forKey: key)
            self = .artistTracks(nested.tracks)
        case "genres":
            let nested = try container.decode(NestedGenres.self, forKey: key)
            self = .genres(nested.genres)
        case "genre_albums":
            let nested = try container.decode(NestedAlbums.self, forKey: key)
            self = .genreAlbums(nested.albums)
        case "genre_tracks":
            let nested = try container.decode(NestedTracks.self, forKey: key)
            self = .genreTracks(nested.tracks)
        case "search_results":
            let nested = try container.decode(NestedTracks.self, forKey: key)
            self = .searchResults(nested.tracks)
        case "queue":
            let queueData = try container.decode(QueueData.self, forKey: key)
            self = .queue(tracks: queueData.tracks, currentIndex: queueData.currentIndex)
        case "signed_urls":
            let nested = try container.decode(SignedURLsData.self, forKey: key)
            self = .signedURLs(nested.urls)
        case "playlists":
            let nested = try container.decode(NestedPlaylists.self, forKey: key)
            self = .playlists(nested.playlists)
        case "playlist_details":
            let nested = try container.decode(PlaylistDetailsData.self, forKey: key)
            self = .playlistDetails(nested.playlist)
        case "playlist_tracks":
            let nested = try container.decode(PlaylistTracksData.self, forKey: key)
            self = .playlistTracks(playlistId: nested.playlistId, tracks: nested.tracks)
        default:
            throw KanadeError.unknownResponse(key.stringValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)

        switch self {
        case .albums(let albums):
            try container.encode(NestedAlbums(albums: albums), forKey: DynamicCodingKeys(stringValue: "albums")!)
        case .albumTracks(let tracks):
            try container.encode(NestedTracks(tracks: tracks), forKey: DynamicCodingKeys(stringValue: "album_tracks")!)
        case .artists(let artists):
            try container.encode(NestedArtists(artists: artists), forKey: DynamicCodingKeys(stringValue: "artists")!)
        case .artistAlbums(let albums):
            try container.encode(NestedAlbums(albums: albums), forKey: DynamicCodingKeys(stringValue: "artist_albums")!)
        case .artistTracks(let tracks):
            try container.encode(NestedTracks(tracks: tracks), forKey: DynamicCodingKeys(stringValue: "artist_tracks")!)
        case .genres(let genres):
            try container.encode(NestedGenres(genres: genres), forKey: DynamicCodingKeys(stringValue: "genres")!)
        case .genreAlbums(let albums):
            try container.encode(NestedAlbums(albums: albums), forKey: DynamicCodingKeys(stringValue: "genre_albums")!)
        case .genreTracks(let tracks):
            try container.encode(NestedTracks(tracks: tracks), forKey: DynamicCodingKeys(stringValue: "genre_tracks")!)
        case .searchResults(let tracks):
            try container.encode(NestedTracks(tracks: tracks), forKey: DynamicCodingKeys(stringValue: "search_results")!)
        case .queue(let tracks, let currentIndex):
            try container.encode(
                QueueData(tracks: tracks, currentIndex: currentIndex),
                forKey: DynamicCodingKeys(stringValue: "queue")!
            )
        case .signedURLs(let signedURLs):
            try container.encode(
                SignedURLsData(urls: signedURLs),
                forKey: DynamicCodingKeys(stringValue: "signed_urls")!
            )
        case .playlists(let playlists):
            try container.encode(
                NestedPlaylists(playlists: playlists),
                forKey: DynamicCodingKeys(stringValue: "playlists")!
            )
        case .playlistDetails(let playlist):
            try container.encode(
                PlaylistDetailsData(playlist: playlist),
                forKey: DynamicCodingKeys(stringValue: "playlist_details")!
            )
        case .playlistTracks(let playlistId, let tracks):
            try container.encode(
                PlaylistTracksData(playlistId: playlistId, tracks: tracks),
                forKey: DynamicCodingKeys(stringValue: "playlist_tracks")!
            )
        }
    }
}
