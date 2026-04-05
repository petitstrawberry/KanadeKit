import Foundation
import Observation

public protocol KanadeClientDelegate: AnyObject, Sendable {
    func clientDidConnect(_ client: KanadeClient)
    func clientDidDisconnect(_ client: KanadeClient, error: (any Error)?)
    func client(_ client: KanadeClient, didUpdateState state: PlaybackState)
    func client(_ client: KanadeClient, didReceiveError error: any Error)
}

public extension KanadeClientDelegate {
    func clientDidConnect(_ client: KanadeClient) {}
    func clientDidDisconnect(_ client: KanadeClient, error: (any Error)?) {}
    func client(_ client: KanadeClient, didUpdateState state: PlaybackState) {}
    func client(_ client: KanadeClient, didReceiveError error: any Error) {}
}

@Observable
public final class KanadeClient: @unchecked Sendable {
    public private(set) var state: PlaybackState?
    public private(set) var connected: Bool = false

    public weak var delegate: (any KanadeClientDelegate)?

    private let wsClient: WsClient

    public init(
        url: URL,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeout: TimeInterval = 45.0,
        requestTimeout: TimeInterval = 10.0
    ) {
        self.wsClient = WsClient(
            url: url,
            reconnectPolicy: reconnectPolicy,
            heartbeatTimeout: heartbeatTimeout,
            requestTimeout: requestTimeout
        )
        self.state = wsClient.state
        self.connected = wsClient.connected
        self.wsClient.delegate = self
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
}

extension KanadeClient: WsClientDelegate {
    nonisolated func clientDidConnect(_ client: WsClient) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = true
            self.delegate?.clientDidConnect(self)
        }
    }

    nonisolated func clientDidDisconnect(_ client: WsClient, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connected = false
            self.delegate?.clientDidDisconnect(self, error: error)
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
