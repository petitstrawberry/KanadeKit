import Foundation
import Testing
@testable import KanadeKit

private func makeTrack(
    id: String = "track-1",
    filePath: String = "/music/Album/01-track.flac"
) -> Track {
    Track(
        id: id,
        filePath: filePath,
        albumId: "album-1",
        title: "Track Name",
        artist: "Artist Name",
        albumArtist: "Album Artist",
        albumTitle: "Album Title",
        composer: "Composer",
        genre: "Genre",
        trackNumber: 1,
        discNumber: 1,
        durationSecs: 245.93,
        format: "FLAC",
        sampleRate: 48_000
    )
}

private func makeAlbum(id: String = "album-1") -> Album {
    Album(
        id: id,
        dirPath: "/music/Album",
        title: "Album Title",
        artworkPath: "/music/Album/cover.jpg"
    )
}

private func makeNode(id: String = "node-1") -> Node {
    Node(
        id: id,
        name: "Living Room",
        connected: true,
        status: .playing,
        positionSecs: 93.5,
        volume: 72
    )
}

private func makePlaybackState() -> PlaybackState {
    PlaybackState(
        nodes: [makeNode()],
        selectedNodeId: "node-1",
        queue: [makeTrack()],
        currentIndex: 0,
        shuffle: true,
        repeatMode: .all
    )
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func trackRoundTrip() throws {
    let track = makeTrack(id: "abc123")
    let data = try JSONEncoder().encode(track)
    let decoded = try JSONDecoder().decode(Track.self, from: data)

    #expect(decoded == track)
}

@Test func trackOptionalFieldsNil() throws {
    let track = Track(id: "abc", filePath: "/music/test.flac")
    let data = try JSONEncoder().encode(track)
    let decoded = try JSONDecoder().decode(Track.self, from: data)
    let json = try jsonObject(from: data)

    #expect(decoded.id == "abc")
    #expect(decoded.filePath == "/music/test.flac")
    #expect(decoded.albumId == nil)
    #expect(decoded.title == nil)
    #expect(decoded.artist == nil)
    #expect(decoded.albumArtist == nil)
    #expect(decoded.albumTitle == nil)
    #expect(decoded.composer == nil)
    #expect(decoded.genre == nil)
    #expect(decoded.trackNumber == nil)
    #expect(decoded.discNumber == nil)
    #expect(decoded.durationSecs == nil)
    #expect(decoded.format == nil)
    #expect(decoded.sampleRate == nil)
    #expect(json["album_id"] == nil)
    #expect(json["title"] == nil)
    #expect(json["artist"] == nil)
    #expect(json["album_artist"] == nil)
    #expect(json["album_title"] == nil)
    #expect(json["composer"] == nil)
    #expect(json["genre"] == nil)
    #expect(json["track_number"] == nil)
    #expect(json["disc_number"] == nil)
    #expect(json["duration_secs"] == nil)
    #expect(json["format"] == nil)
    #expect(json["sample_rate"] == nil)
}

@Test func trackJSONKeysAreSnakeCase() throws {
    let track = Track(id: "x", filePath: "/a.flac", albumId: "y")
    let data = try JSONEncoder().encode(track)
    let json = try jsonObject(from: data)

    #expect(json["id"] as? String == "x")
    #expect(json["file_path"] as? String == "/a.flac")
    #expect(json["album_id"] as? String == "y")
    #expect(json["filePath"] == nil)
    #expect(json["albumId"] == nil)
}

@Test func trackDecodesFromServerJSON() throws {
    let json = """
    {
        "id": "sha256hex",
        "file_path": "/music/Album/01-track.flac",
        "album_id": "albumsha256",
        "title": "Track Name",
        "artist": "Artist Name",
        "album_artist": "Album Artist",
        "album_title": "Album Title",
        "composer": "Composer",
        "genre": "Genre",
        "track_number": 1,
        "disc_number": 1,
        "duration_secs": 245.93,
        "format": "FLAC",
        "sample_rate": 48000
    }
    """.data(using: .utf8)!

    let track = try JSONDecoder().decode(Track.self, from: json)

    #expect(track == Track(
        id: "sha256hex",
        filePath: "/music/Album/01-track.flac",
        albumId: "albumsha256",
        title: "Track Name",
        artist: "Artist Name",
        albumArtist: "Album Artist",
        albumTitle: "Album Title",
        composer: "Composer",
        genre: "Genre",
        trackNumber: 1,
        discNumber: 1,
        durationSecs: 245.93,
        format: "FLAC",
        sampleRate: 48_000
    ))
}

@Test func albumRoundTrip() throws {
    let album = makeAlbum(id: "album456")
    let data = try JSONEncoder().encode(album)
    let decoded = try JSONDecoder().decode(Album.self, from: data)

    #expect(decoded == album)
}

@Test func albumOptionalFieldsNil() throws {
    let album = Album(id: "album-2", dirPath: "/music/Test")
    let data = try JSONEncoder().encode(album)
    let decoded = try JSONDecoder().decode(Album.self, from: data)
    let json = try jsonObject(from: data)

    #expect(decoded.id == "album-2")
    #expect(decoded.dirPath == "/music/Test")
    #expect(decoded.title == nil)
    #expect(decoded.artworkPath == nil)
    #expect(json["title"] == nil)
    #expect(json["artwork_path"] == nil)
}

@Test func albumJSONKeysAreSnakeCase() throws {
    let album = makeAlbum(id: "album-json")
    let data = try JSONEncoder().encode(album)
    let json = try jsonObject(from: data)

    #expect(json["id"] as? String == "album-json")
    #expect(json["dir_path"] as? String == "/music/Album")
    #expect(json["artwork_path"] as? String == "/music/Album/cover.jpg")
    #expect(json["dirPath"] == nil)
    #expect(json["artworkPath"] == nil)
}

@Test func albumDecodesFromServerJSON() throws {
    let json = """
    {
        "id": "album-server",
        "dir_path": "/music/Album",
        "title": "Album Title",
        "artwork_path": "/music/Album/cover.jpg"
    }
    """.data(using: .utf8)!

    let album = try JSONDecoder().decode(Album.self, from: json)

    #expect(album == makeAlbum(id: "album-server"))
}

@Test func nodeRoundTrip() throws {
    let node = makeNode(id: "node-rt")
    let data = try JSONEncoder().encode(node)
    let decoded = try JSONDecoder().decode(Node.self, from: data)

    #expect(decoded == node)
}

@Test func nodeJSONKeysAreSnakeCase() throws {
    let node = makeNode(id: "node-json")
    let data = try JSONEncoder().encode(node)
    let json = try jsonObject(from: data)

    #expect(json["id"] as? String == "node-json")
    #expect(json["name"] as? String == "Living Room")
    #expect(json["connected"] as? Bool == true)
    #expect(json["status"] as? String == "playing")
    #expect(json["position_secs"] as? Double == 93.5)
    #expect(json["volume"] as? Int == 72)
    #expect(json["positionSecs"] == nil)
}

@Test func nodeDecodesFromServerJSON() throws {
    let json = """
    {
        "id": "node-server",
        "name": "Desk",
        "connected": false,
        "status": "paused",
        "position_secs": 12.25,
        "volume": 33
    }
    """.data(using: .utf8)!

    let node = try JSONDecoder().decode(Node.self, from: json)

    #expect(node == Node(
        id: "node-server",
        name: "Desk",
        connected: false,
        status: .paused,
        positionSecs: 12.25,
        volume: 33
    ))
}

@Test func playbackStateRoundTrip() throws {
    let state = makePlaybackState()
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PlaybackState.self, from: data)

    #expect(decoded == state)
}

@Test func playbackStateRepeatKeyMapsToRepeatMode() throws {
    let state = makePlaybackState()
    let data = try JSONEncoder().encode(state)
    let json = try jsonObject(from: data)

    #expect(json["repeat"] as? String == "all")
    #expect(json["repeatMode"] == nil)

    let decoded = try JSONDecoder().decode(PlaybackState.self, from: data)
    #expect(decoded.repeatMode == .all)
}

@Test func playbackStateDecodesFromServerJSON() throws {
    let json = """
    {
        "nodes": [
            {
                "id": "node-1",
                "name": "Living Room",
                "connected": true,
                "status": "playing",
                "position_secs": 93.5,
                "volume": 72
            }
        ],
        "selected_node_id": "node-1",
        "queue": [
            {
                "id": "track-1",
                "file_path": "/music/Album/01-track.flac"
            }
        ],
        "current_index": 0,
        "shuffle": true,
        "repeat": "all"
    }
    """.data(using: .utf8)!

    let state = try JSONDecoder().decode(PlaybackState.self, from: json)

    #expect(state == PlaybackState(
        nodes: [makeNode()],
        selectedNodeId: "node-1",
        queue: [Track(id: "track-1", filePath: "/music/Album/01-track.flac")],
        currentIndex: 0,
        shuffle: true,
        repeatMode: .all
    ))
}

@Test(arguments: [PlaybackStatus.stopped, .playing, .paused, .loading])
func playbackStatusRawValueEncoding(status: PlaybackStatus) throws {
    let data = try JSONEncoder().encode(status)
    let decoded = try JSONDecoder().decode(PlaybackStatus.self, from: data)
    let raw = try JSONDecoder().decode(String.self, from: data)

    #expect(raw == status.rawValue)
    #expect(decoded == status)
}

@Test(arguments: [RepeatMode.off, .one, .all])
func repeatModeRawValueEncoding(mode: RepeatMode) throws {
    let data = try JSONEncoder().encode(mode)
    let decoded = try JSONDecoder().decode(RepeatMode.self, from: data)
    let raw = try JSONDecoder().decode(String.self, from: data)

    #expect(raw == mode.rawValue)
    #expect(decoded == mode)
}
