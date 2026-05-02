import Foundation

enum WsRequest: Codable, Sendable, Equatable {
    case getAlbums
    case getAlbumTracks(albumId: String)
    case getArtists
    case getArtistAlbums(artist: String)
    case getArtistTracks(artist: String)
    case getGenres
    case getGenreAlbums(genre: String)
    case getGenreTracks(genre: String)
    case search(query: String)
    case getQueue
    case signURLs(paths: [String])
    case getPlaylists
    case getPlaylist(playlistId: String)
    case getPlaylistTracks(playlistId: String)

    private enum CodingKeys: String, CodingKey {
        case req
        case albumId = "album_id"
        case artist
        case genre
        case query
        case paths
        case playlistId = "playlist_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let req = try container.decode(String.self, forKey: .req)

        switch req {
        case "get_albums":
            self = .getAlbums
        case "get_album_tracks":
            self = .getAlbumTracks(albumId: try container.decode(String.self, forKey: .albumId))
        case "get_artists":
            self = .getArtists
        case "get_artist_albums":
            self = .getArtistAlbums(artist: try container.decode(String.self, forKey: .artist))
        case "get_artist_tracks":
            self = .getArtistTracks(artist: try container.decode(String.self, forKey: .artist))
        case "get_genres":
            self = .getGenres
        case "get_genre_albums":
            self = .getGenreAlbums(genre: try container.decode(String.self, forKey: .genre))
        case "get_genre_tracks":
            self = .getGenreTracks(genre: try container.decode(String.self, forKey: .genre))
        case "search":
            self = .search(query: try container.decode(String.self, forKey: .query))
        case "get_queue":
            self = .getQueue
        case "sign_urls":
            self = .signURLs(paths: try container.decode([String].self, forKey: .paths))
        case "get_playlists":
            self = .getPlaylists
        case "get_playlist":
            self = .getPlaylist(playlistId: try container.decode(String.self, forKey: .playlistId))
        case "get_playlist_tracks":
            self = .getPlaylistTracks(playlistId: try container.decode(String.self, forKey: .playlistId))
        default:
            throw KanadeError.unknownRequest(req)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
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
        case .signURLs(let paths):
            try container.encode("sign_urls", forKey: .req)
            try container.encode(paths, forKey: .paths)
        case .getPlaylists:
            try container.encode("get_playlists", forKey: .req)
        case .getPlaylist(let playlistId):
            try container.encode("get_playlist", forKey: .req)
            try container.encode(playlistId, forKey: .playlistId)
        case .getPlaylistTracks(let playlistId):
            try container.encode("get_playlist_tracks", forKey: .req)
            try container.encode(playlistId, forKey: .playlistId)
        }
    }
}
