import Foundation
import Testing
@testable import KanadeKit

private func makeProtocolTrack(
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

private func makeProtocolAlbum(id: String = "album-1") -> Album {
    Album(
        id: id,
        dirPath: "/music/Album",
        title: "Album Title",
        artworkPath: "/music/Album/cover.jpg"
    )
}

private func makeProtocolNode(id: String = "node-1") -> Node {
    Node(
        id: id,
        name: "Living Room",
        connected: true,
        status: .playing,
        positionSecs: 93.5,
        volume: 72
    )
}

private func makeProtocolState() -> PlaybackState {
    PlaybackState(
        nodes: [makeProtocolNode()],
        selectedNodeId: "node-1",
        queue: [Track(id: "queue-track", filePath: "/music/Album/queue.flac")],
        currentIndex: 0,
        shuffle: true,
        repeatMode: .one
    )
}

private func dictionary(from data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func assertUnknownCommand(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
    do {
        _ = try JSONDecoder().decode(WsCommand.self, from: data)
        Issue.record("Expected unknown command error", sourceLocation: sourceLocation)
    } catch let error as KanadeError {
        switch error {
        case .unknownCommand(let command):
            #expect(command == "wat", sourceLocation: sourceLocation)
        default:
            Issue.record("Expected unknownCommand, got \(error)", sourceLocation: sourceLocation)
        }
    }
}

private func assertUnknownRequest(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
    do {
        _ = try JSONDecoder().decode(WsRequest.self, from: data)
        Issue.record("Expected unknown request error", sourceLocation: sourceLocation)
    } catch let error as KanadeError {
        switch error {
        case .unknownRequest(let request):
            #expect(request == "wat", sourceLocation: sourceLocation)
        default:
            Issue.record("Expected unknownRequest, got \(error)", sourceLocation: sourceLocation)
        }
    }
}

private func assertUnknownMessageType<T: Decodable>(
    _ type: T.Type,
    data: Data,
    expectedValue: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    do {
        _ = try JSONDecoder().decode(type, from: data)
        Issue.record("Expected unknown message type error", sourceLocation: sourceLocation)
    } catch let error as KanadeError {
        switch error {
        case .unknownMessageType(let messageType):
            if let expectedValue {
                #expect(messageType == expectedValue, sourceLocation: sourceLocation)
            } else {
                #expect(!messageType.isEmpty, sourceLocation: sourceLocation)
            }
        default:
            Issue.record("Expected unknownMessageType, got \(error)", sourceLocation: sourceLocation)
        }
    }
}

private func assertWsCommandRoundTrip(
    _ command: WsCommand,
    expectedCmd: String,
    expectedFields: [String: Any] = [:],
    absentKeys: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let data = try JSONEncoder().encode(command)
    let json = try dictionary(from: data)

    #expect(json["cmd"] as? String == expectedCmd, sourceLocation: sourceLocation)
    for (key, value) in expectedFields {
        switch value {
        case let value as String:
            #expect(json[key] as? String == value, sourceLocation: sourceLocation)
        case let value as Int:
            #expect(json[key] as? Int == value, sourceLocation: sourceLocation)
        case let value as Double:
            #expect(json[key] as? Double == value, sourceLocation: sourceLocation)
        case let value as Bool:
            #expect(json[key] as? Bool == value, sourceLocation: sourceLocation)
        default:
            Issue.record("Unsupported expected field type for key \(key)", sourceLocation: sourceLocation)
        }
    }
    for key in absentKeys {
        #expect(json[key] == nil, sourceLocation: sourceLocation)
    }

    let decoded = try JSONDecoder().decode(WsCommand.self, from: data)
    #expect(decoded == command, sourceLocation: sourceLocation)
}

private func assertWsRequestRoundTrip(
    _ request: WsRequest,
    expectedReq: String,
    expectedFields: [String: Any] = [:],
    absentKeys: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let data = try JSONEncoder().encode(request)
    let json = try dictionary(from: data)

    #expect(json["req"] as? String == expectedReq, sourceLocation: sourceLocation)
    for (key, value) in expectedFields {
        switch value {
        case let value as String:
            #expect(json[key] as? String == value, sourceLocation: sourceLocation)
        case let value as Int:
            #expect(json[key] as? Int == value, sourceLocation: sourceLocation)
        default:
            Issue.record("Unsupported expected field type for key \(key)", sourceLocation: sourceLocation)
        }
    }
    for key in absentKeys {
        #expect(json[key] == nil, sourceLocation: sourceLocation)
    }

    let decoded = try JSONDecoder().decode(WsRequest.self, from: data)
    #expect(decoded == request, sourceLocation: sourceLocation)
}

private func assertWsResponseRoundTrip(
    _ response: WsResponse,
    rootKey: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    extraChecks: ([String: Any]) throws -> Void = { _ in }
) throws {
    let data = try JSONEncoder().encode(response)
    let json = try dictionary(from: data)

    #expect(json[rootKey] != nil, sourceLocation: sourceLocation)
    #expect(json.count == 1, sourceLocation: sourceLocation)
    try extraChecks(json)

    let decoded = try JSONDecoder().decode(WsResponse.self, from: data)
    #expect(decoded == response, sourceLocation: sourceLocation)
}

@Test func wsCommandPlayEncodesCorrectly() throws {
    let data = try JSONEncoder().encode(WsCommand.play)
    let json = try dictionary(from: data)

    #expect(json["cmd"] as? String == "play")
    #expect(json.count == 1)
}

@Test func wsCommandPauseRoundTrip() throws {
    try assertWsCommandRoundTrip(.pause, expectedCmd: "pause")
}

@Test func wsCommandStopRoundTrip() throws {
    try assertWsCommandRoundTrip(.stop, expectedCmd: "stop")
}

@Test func wsCommandNextRoundTrip() throws {
    try assertWsCommandRoundTrip(.next, expectedCmd: "next")
}

@Test func wsCommandPreviousRoundTrip() throws {
    try assertWsCommandRoundTrip(.previous, expectedCmd: "previous")
}

@Test func wsCommandSeekRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .seek(positionSecs: 30.0),
        expectedCmd: "seek",
        expectedFields: ["position_secs": 30.0],
        absentKeys: ["positionSecs"]
    )
}

@Test func wsCommandSetVolumeRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .setVolume(volume: 80),
        expectedCmd: "set_volume",
        expectedFields: ["volume": 80]
    )
}

@Test func wsCommandSetRepeatRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .setRepeat(repeatMode: .all),
        expectedCmd: "set_repeat",
        expectedFields: ["repeat": "all"],
        absentKeys: ["repeatMode"]
    )
}

@Test func wsCommandSetShuffleRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .setShuffle(shuffle: true),
        expectedCmd: "set_shuffle",
        expectedFields: ["shuffle": true]
    )
}

@Test func wsCommandSelectNodeRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .selectNode(nodeId: "node-9"),
        expectedCmd: "select_node",
        expectedFields: ["node_id": "node-9"],
        absentKeys: ["nodeId"]
    )
}

@Test func wsCommandAddToQueueRoundTrip() throws {
    let track = makeProtocolTrack(id: "track-add")
    let data = try JSONEncoder().encode(WsCommand.addToQueue(track: track))
    let json = try dictionary(from: data)
    let trackJSON = try #require(json["track"] as? [String: Any])

    #expect(json["cmd"] as? String == "add_to_queue")
    #expect(trackJSON["id"] as? String == "track-add")
    #expect(trackJSON["file_path"] as? String == "/music/Album/01-track.flac")
    #expect(trackJSON["filePath"] == nil)

    let decoded = try JSONDecoder().decode(WsCommand.self, from: data)
    #expect(decoded == .addToQueue(track: track))
}

@Test func wsCommandAddTracksToQueueRoundTrip() throws {
    let tracks = [
        makeProtocolTrack(id: "track-1"),
        makeProtocolTrack(id: "track-2", filePath: "/music/Album/02-track.flac")
    ]
    let data = try JSONEncoder().encode(WsCommand.addTracksToQueue(tracks: tracks))
    let json = try dictionary(from: data)
    let tracksJSON = try #require(json["tracks"] as? [[String: Any]])

    #expect(json["cmd"] as? String == "add_tracks_to_queue")
    #expect(tracksJSON.count == 2)
    #expect(tracksJSON[0]["id"] as? String == "track-1")
    #expect(tracksJSON[1]["file_path"] as? String == "/music/Album/02-track.flac")

    let decoded = try JSONDecoder().decode(WsCommand.self, from: data)
    #expect(decoded == .addTracksToQueue(tracks: tracks))
}

@Test func wsCommandPlayIndexRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .playIndex(index: 3),
        expectedCmd: "play_index",
        expectedFields: ["index": 3]
    )
}

@Test func wsCommandRemoveFromQueueRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .removeFromQueue(index: 2),
        expectedCmd: "remove_from_queue",
        expectedFields: ["index": 2]
    )
}

@Test func wsCommandMoveInQueueRoundTrip() throws {
    try assertWsCommandRoundTrip(
        .moveInQueue(from: 1, to: 4),
        expectedCmd: "move_in_queue",
        expectedFields: ["from": 1, "to": 4]
    )
}

@Test func wsCommandClearQueueRoundTrip() throws {
    try assertWsCommandRoundTrip(.clearQueue, expectedCmd: "clear_queue")
}

@Test func wsCommandReplaceAndPlayRoundTrip() throws {
    let tracks = [
        Track(id: "t1", filePath: "/a.flac"),
        Track(id: "t2", filePath: "/b.flac")
    ]
    let data = try JSONEncoder().encode(WsCommand.replaceAndPlay(tracks: tracks, index: 1))
    let json = try dictionary(from: data)
    let tracksJSON = try #require(json["tracks"] as? [[String: Any]])

    #expect(json["cmd"] as? String == "replace_and_play")
    #expect(json["index"] as? Int == 1)
    #expect(tracksJSON.count == 2)
    #expect(tracksJSON[0]["file_path"] as? String == "/a.flac")

    let decoded = try JSONDecoder().decode(WsCommand.self, from: data)
    #expect(decoded == .replaceAndPlay(tracks: tracks, index: 1))
}

@Test func wsCommandUnknownCommandThrows() throws {
    try assertUnknownCommand(#"{"cmd":"wat"}"#.data(using: .utf8)!)
}

@Test func wsRequestGetAlbumsRoundTrip() throws {
    try assertWsRequestRoundTrip(.getAlbums, expectedReq: "get_albums")
}

@Test func wsRequestGetAlbumTracksRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .getAlbumTracks(albumId: "album-7"),
        expectedReq: "get_album_tracks",
        expectedFields: ["album_id": "album-7"],
        absentKeys: ["albumId"]
    )
}

@Test func wsRequestGetArtistsRoundTrip() throws {
    try assertWsRequestRoundTrip(.getArtists, expectedReq: "get_artists")
}

@Test func wsRequestGetArtistAlbumsRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .getArtistAlbums(artist: "Neru"),
        expectedReq: "get_artist_albums",
        expectedFields: ["artist": "Neru"]
    )
}

@Test func wsRequestGetArtistTracksRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .getArtistTracks(artist: "Neru"),
        expectedReq: "get_artist_tracks",
        expectedFields: ["artist": "Neru"]
    )
}

@Test func wsRequestGetGenresRoundTrip() throws {
    try assertWsRequestRoundTrip(.getGenres, expectedReq: "get_genres")
}

@Test func wsRequestGetGenreAlbumsRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .getGenreAlbums(genre: "Rock"),
        expectedReq: "get_genre_albums",
        expectedFields: ["genre": "Rock"]
    )
}

@Test func wsRequestGetGenreTracksRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .getGenreTracks(genre: "Rock"),
        expectedReq: "get_genre_tracks",
        expectedFields: ["genre": "Rock"]
    )
}

@Test func wsRequestSearchRoundTrip() throws {
    try assertWsRequestRoundTrip(
        .search(query: "Neru"),
        expectedReq: "search",
        expectedFields: ["query": "Neru"]
    )
}

@Test func wsRequestGetQueueRoundTrip() throws {
    try assertWsRequestRoundTrip(.getQueue, expectedReq: "get_queue")
}

@Test func wsRequestUnknownRequestThrows() throws {
    try assertUnknownRequest(#"{"req":"wat"}"#.data(using: .utf8)!)
}

@Test func wsResponseAlbumsRoundTrip() throws {
    try assertWsResponseRoundTrip(.albums([makeProtocolAlbum()]), rootKey: "albums")
}

@Test func wsResponseAlbumTracksRoundTrip() throws {
    try assertWsResponseRoundTrip(.albumTracks([Track(id: "t1", filePath: "/a.flac")]), rootKey: "album_tracks")
}

@Test func wsResponseArtistsRoundTrip() throws {
    try assertWsResponseRoundTrip(.artists(["Neru", "Miku"]), rootKey: "artists")
}

@Test func wsResponseArtistAlbumsRoundTrip() throws {
    try assertWsResponseRoundTrip(.artistAlbums([makeProtocolAlbum(id: "artist-album")]), rootKey: "artist_albums")
}

@Test func wsResponseArtistTracksRoundTrip() throws {
    try assertWsResponseRoundTrip(.artistTracks([Track(id: "t2", filePath: "/b.flac")]), rootKey: "artist_tracks")
}

@Test func wsResponseGenresRoundTrip() throws {
    try assertWsResponseRoundTrip(.genres(["Rock", "Jazz"]), rootKey: "genres")
}

@Test func wsResponseGenreAlbumsRoundTrip() throws {
    try assertWsResponseRoundTrip(.genreAlbums([makeProtocolAlbum(id: "genre-album")]), rootKey: "genre_albums")
}

@Test func wsResponseGenreTracksRoundTrip() throws {
    try assertWsResponseRoundTrip(.genreTracks([Track(id: "t3", filePath: "/c.flac")]), rootKey: "genre_tracks")
}

@Test func wsResponseSearchResultsRoundTrip() throws {
    try assertWsResponseRoundTrip(.searchResults([Track(id: "t4", filePath: "/d.flac")]), rootKey: "search_results")
}

@Test func wsResponseQueueRoundTrip() throws {
    let response = WsResponse.queue(
        tracks: [Track(id: "t5", filePath: "/e.flac")],
        currentIndex: 0
    )

    try assertWsResponseRoundTrip(response, rootKey: "queue") { json in
        let queue = try #require(json["queue"] as? [String: Any])
        let tracks = try #require(queue["tracks"] as? [[String: Any]])
        #expect(queue["current_index"] as? Int == 0)
        #expect(tracks.count == 1)
        #expect(tracks[0]["file_path"] as? String == "/e.flac")
    }
}

@Test func wsResponseDynamicKeyDecodingWorks() throws {
    let data = #"{"albums":[{"id":"album-1","dir_path":"/music/Album"}]}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(WsResponse.self, from: data)

    #expect(decoded == .albums([Album(id: "album-1", dirPath: "/music/Album")]))
}

@Test func clientMessageCommandEncodesWithoutReqId() throws {
    let data = try JSONEncoder().encode(ClientMessage.command(.play))
    let json = try dictionary(from: data)

    #expect(json["cmd"] as? String == "play")
    #expect(json["req_id"] == nil)
}

@Test func clientMessageRequestIncludesReqId() throws {
    let message = ClientMessage.request(reqId: 42, request: .search(query: "Neru"))
    let data = try JSONEncoder().encode(message)
    let json = try dictionary(from: data)

    #expect(json["req_id"] as? UInt64 == 42)
    #expect(json["req"] as? String == "search")
    #expect(json["query"] as? String == "Neru")

    let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
    #expect(decoded == message)
}

@Test func clientMessageDecodesCommandWhenCmdPresent() throws {
    let data = #"{"cmd":"pause"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

    #expect(decoded == .command(.pause))
}

@Test func clientMessageDecodesRequestWhenReqIdPresent() throws {
    let data = #"{"req_id":7,"req":"get_queue"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

    #expect(decoded == .request(reqId: 7, request: .getQueue))
}

@Test func clientMessageMissingTypeThrows() throws {
    try assertUnknownMessageType(
        ClientMessage.self,
        data: #"{"query":"Neru"}"#.data(using: .utf8)!
    )
}

@Test func serverMessageStateRoundTrip() throws {
    let message = ServerMessage.state(makeProtocolState())
    let data = try JSONEncoder().encode(message)
    let json = try dictionary(from: data)

    #expect(json["type"] as? String == "state")
    #expect(json["state"] != nil)

    let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
    #expect(decoded == message)
}

@Test func serverMessageResponseRoundTrip() throws {
    let response = WsResponse.queue(tracks: [Track(id: "srv", filePath: "/srv.flac")], currentIndex: 0)
    let message = ServerMessage.response(reqId: 1, response: response)
    let data = try JSONEncoder().encode(message)
    let json = try dictionary(from: data)
    let dataJSON = try #require(json["data"] as? [String: Any])

    #expect(json["type"] as? String == "response")
    #expect(json["req_id"] as? UInt64 == 1)
    #expect(dataJSON["queue"] != nil)

    let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
    #expect(decoded == message)
}

@Test func serverMessageUnknownTypeThrows() throws {
    try assertUnknownMessageType(
        ServerMessage.self,
        data: #"{"type":"wat"}"#.data(using: .utf8)!,
        expectedValue: "wat"
    )
}

@Test func clientMessageReplaceAndPlayRoundTrip() throws {
    let msg = ClientMessage.request(
        reqId: 42,
        request: .search(query: "Neru")
    )
    let data = try JSONEncoder().encode(msg)
    let json = try dictionary(from: data)

    #expect(json["req_id"] as? UInt64 == 42)
    #expect(json["req"] as? String == "search")
    #expect(json["query"] as? String == "Neru")

    let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)
    #expect(decoded == msg)
}
