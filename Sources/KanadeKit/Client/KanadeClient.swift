import Foundation
import Observation

public protocol KanadeClientDelegate: AnyObject, Sendable {
    func clientDidConnect(_ client: KanadeClient)
    func clientDidDisconnect(_ client: KanadeClient, error: (any Error)?)
    func clientDidUpdateConnectionStatus(_ client: KanadeClient)
    func client(_ client: KanadeClient, didUpdateState state: PlaybackState)
    func client(_ client: KanadeClient, didReceiveError error: any Error)
    func client(_ client: KanadeClient, didReceiveMediaAuthKeyId keyId: String?)
}

public extension KanadeClientDelegate {
    func clientDidConnect(_ client: KanadeClient) {}
    func clientDidDisconnect(_ client: KanadeClient, error: (any Error)?) {}
    func clientDidUpdateConnectionStatus(_ client: KanadeClient) {}
    func client(_ client: KanadeClient, didUpdateState state: PlaybackState) {}
    func client(_ client: KanadeClient, didReceiveError error: any Error) {}
    func client(_ client: KanadeClient, didReceiveMediaAuthKeyId keyId: String?) {}
}

    @Observable
public final class KanadeClient: @unchecked Sendable {
    public private(set) var state: PlaybackState?
    public private(set) var connected: Bool = false
    public private(set) var reconnectExhausted: Bool = false

    public weak var delegate: (any KanadeClientDelegate)?

    private let wsClient: WsClient

    public init(
        url: URL,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeout: TimeInterval = 30.0,
        requestTimeout: TimeInterval = 10.0,
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        self.wsClient = WsClient(
            url: url,
            reconnectPolicy: reconnectPolicy,
            heartbeatTimeout: heartbeatTimeout,
            requestTimeout: requestTimeout,
            tlsConfiguration: tlsConfiguration
        )
        self.state = wsClient.state
        self.connected = wsClient.connected
        self.wsClient.delegate = self
    }

    public convenience init(
        host: String,
        port: Int,
        useTLS: Bool = false,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeout: TimeInterval = 30.0,
        requestTimeout: TimeInterval = 10.0,
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        let scheme = useTLS ? "wss" : "ws"
        let url = URL(string: "\(scheme)://\(host):\(port)/ws")!
        self.init(
            url: url,
            reconnectPolicy: reconnectPolicy,
            heartbeatTimeout: heartbeatTimeout,
            requestTimeout: requestTimeout,
            tlsConfiguration: tlsConfiguration
        )
    }

    deinit {
        wsClient.disconnect()
    }

    public func connect() {
        wsClient.connect()
    }

    public func disconnect() {
        wsClient.disconnect()
    }

    public func play() { wsClient.send(.play) }
    public func pause() { wsClient.send(.pause) }
    public func stop() { wsClient.send(.stop) }
    public func next() { wsClient.send(.next) }
    public func previous() { wsClient.send(.previous) }
    public func seek(to positionSecs: Double) { wsClient.send(.seek(positionSecs: positionSecs)) }
    public func setVolume(_ volume: Int) { wsClient.send(.setVolume(volume: volume)) }
    public func setRepeat(_ mode: RepeatMode) { wsClient.send(.setRepeat(repeatMode: mode)) }
    public func setShuffle(_ enabled: Bool) { wsClient.send(.setShuffle(shuffle: enabled)) }

    public func selectNode(_ nodeId: String) { wsClient.send(.selectNode(nodeId: nodeId)) }

    public func addToQueue(_ track: Track) { wsClient.send(.addToQueue(track: track)) }
    public func addTracksToQueue(_ tracks: [Track]) { wsClient.send(.addTracksToQueue(tracks: tracks)) }
    public func playIndex(_ index: Int) { wsClient.send(.playIndex(index: index)) }
    public func removeFromQueue(_ index: Int) { wsClient.send(.removeFromQueue(index: index)) }
    public func moveInQueue(from: Int, to: Int) { wsClient.send(.moveInQueue(from: from, to: to)) }
    public func clearQueue() { wsClient.send(.clearQueue) }
    public func replaceAndPlay(tracks: [Track], index: Int) { wsClient.send(.replaceAndPlay(tracks: tracks, index: index)) }
     public func localSessionStart(deviceName: String, deviceId: String?) { wsClient.send(.localSessionStart(deviceName: deviceName, deviceId: deviceId)) }
    public func localSessionStop() { wsClient.send(.localSessionStop) }
    public func localSessionUpdate(queue: [Track]?, currentIndex: Int?, positionSecs: Double, status: PlaybackStatus, volume: Int, repeatMode: RepeatMode, shuffle: Bool) {
        wsClient.send(.localSessionUpdate(queue: queue, currentIndex: currentIndex, positionSecs: positionSecs, status: status, volume: volume, repeatMode: repeatMode, shuffle: shuffle))
    }
    public func handoff(fromNodeId: String, toNodeId: String) { wsClient.send(.handoff(fromNodeId: fromNodeId, toNodeId: toNodeId)) }

    public func getAlbums() async throws -> [Album] {
        let response = try await wsClient.request(.getAlbums)
        guard case .albums(let albums) = response else {
            throw KanadeError.unknownResponse("albums")
        }
        return albums
    }

    public func getAlbumTracks(albumId: String) async throws -> [Track] {
        let response = try await wsClient.request(.getAlbumTracks(albumId: albumId))
        guard case .albumTracks(let tracks) = response else {
            throw KanadeError.unknownResponse("album_tracks")
        }
        return tracks
    }

    public func getTracks(offset: Int? = nil, limit: Int? = nil) async throws -> [Track] {
        let response = try await wsClient.request(.getTracks(offset: offset, limit: limit))
        guard case .tracks(let tracks) = response else {
            throw KanadeError.unknownResponse("tracks")
        }
        return tracks
    }

    public func getArtists() async throws -> [String] {
        let response = try await wsClient.request(.getArtists)
        guard case .artists(let artists) = response else {
            throw KanadeError.unknownResponse("artists")
        }
        return artists
    }

    public func getArtistAlbums(artist: String) async throws -> [Album] {
        let response = try await wsClient.request(.getArtistAlbums(artist: artist))
        guard case .artistAlbums(let albums) = response else {
            throw KanadeError.unknownResponse("artist_albums")
        }
        return albums
    }

    public func getArtistTracks(artist: String) async throws -> [Track] {
        let response = try await wsClient.request(.getArtistTracks(artist: artist))
        guard case .artistTracks(let tracks) = response else {
            throw KanadeError.unknownResponse("artist_tracks")
        }
        return tracks
    }

    public func getGenres() async throws -> [String] {
        let response = try await wsClient.request(.getGenres)
        guard case .genres(let genres) = response else {
            throw KanadeError.unknownResponse("genres")
        }
        return genres
    }

    public func getGenreAlbums(genre: String) async throws -> [Album] {
        let response = try await wsClient.request(.getGenreAlbums(genre: genre))
        guard case .genreAlbums(let albums) = response else {
            throw KanadeError.unknownResponse("genre_albums")
        }
        return albums
    }

    public func getGenreTracks(genre: String) async throws -> [Track] {
        let response = try await wsClient.request(.getGenreTracks(genre: genre))
        guard case .genreTracks(let tracks) = response else {
            throw KanadeError.unknownResponse("genre_tracks")
        }
        return tracks
    }

    public func search(_ query: String) async throws -> [Track] {
        let response = try await wsClient.request(.search(query: query))
        guard case .searchResults(let tracks) = response else {
            throw KanadeError.unknownResponse("search_results")
        }
        return tracks
    }

    public func getQueue() async throws -> (tracks: [Track], currentIndex: Int?) {
        let response = try await wsClient.request(.getQueue)
        guard case .queue(let tracks, let currentIndex) = response else {
            throw KanadeError.unknownResponse("queue")
        }
        return (tracks, currentIndex)
    }

    public func getPlaylists() async throws -> [Playlist] {
        let response = try await wsClient.request(.getPlaylists)
        guard case .playlists(let playlists) = response else {
            throw KanadeError.unknownResponse("playlists")
        }
        return playlists
    }

    public func getPlaylist(playlistId: String) async throws -> Playlist? {
        let response = try await wsClient.request(.getPlaylist(playlistId: playlistId))
        guard case .playlistDetails(let playlist) = response else {
            throw KanadeError.unknownResponse("playlist_details")
        }
        return playlist
    }

    public func getPlaylistTracks(playlistId: String) async throws -> [Track] {
        let response = try await wsClient.request(.getPlaylistTracks(playlistId: playlistId))
        guard case .playlistTracks(_, let tracks) = response else {
            throw KanadeError.unknownResponse("playlist_tracks")
        }
        return tracks
    }

    public func createPlaylist(
        name: String,
        description: String? = nil,
        kind: PlaylistKind = .normal,
        filter: SmartFilter? = nil,
        limit: Int? = nil,
        sortBy: SmartSort? = nil
    ) {
        wsClient.send(.createPlaylist(name: name, description: description, kind: kind, filter: filter, limit: limit, sortBy: sortBy))
    }

    public func updatePlaylist(
        playlistId: String,
        name: String? = nil,
        description: DescriptionUpdate = .unchanged,
        kind: PlaylistKind? = nil
    ) {
        wsClient.send(.updatePlaylist(playlistId: playlistId, name: name, description: description, kind: kind))
    }

    public func deletePlaylist(_ playlistId: String) {
        wsClient.send(.deletePlaylist(playlistId: playlistId))
    }

    public func setPlaylistTracks(playlistId: String, trackIds: [String]) {
        wsClient.send(.setPlaylistTracks(playlistId: playlistId, trackIds: trackIds))
    }

    public func appendPlaylistTracks(playlistId: String, trackIds: [String]) {
        wsClient.send(.appendPlaylistTracks(playlistId: playlistId, trackIds: trackIds))
    }

    public func removePlaylistTrack(playlistId: String, position: Int) {
        wsClient.send(.removePlaylistTrack(playlistId: playlistId, position: position))
    }

    public func movePlaylistTrack(playlistId: String, from: Int, to: Int) {
        wsClient.send(.movePlaylistTrack(playlistId: playlistId, from: from, to: to))
    }

    public func sendRequest(req: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        try await wsClient.sendRequest(req: req, data: data)
    }
}

extension KanadeClient: WsClientDelegate {
    nonisolated func clientDidConnect(_ client: WsClient) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = true
            self.reconnectExhausted = false
            self.delegate?.clientDidConnect(self)
        }
    }

    nonisolated func clientDidDisconnect(_ client: WsClient, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = false
            self.reconnectExhausted = client.reconnectExhausted
            self.delegate?.clientDidDisconnect(self, error: error)
        }
    }

    nonisolated func clientDidUpdateConnectionStatus(_ client: WsClient) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = client.connected
            self.reconnectExhausted = client.reconnectExhausted
            self.delegate?.clientDidUpdateConnectionStatus(self)
        }
    }

    nonisolated func client(_ client: WsClient, didReceiveMediaAuthKeyId keyId: String?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.client(self, didReceiveMediaAuthKeyId: keyId)
        }
    }

    nonisolated func client(_ client: WsClient, didUpdateState state: PlaybackState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = state
            self.connected = true
            self.delegate?.client(self, didUpdateState: state)
        }
    }

    nonisolated func client(_ client: WsClient, didReceiveError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.client(self, didReceiveError: error)
        }
    }
}
