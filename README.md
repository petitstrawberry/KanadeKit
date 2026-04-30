# KanadeKit

Swift client for the [Kanade](https://github.com/petitstrawberry/kanade) music player protocol. Pure Foundation for core logic, with Starscream for WebSocket transport and optional FLAC/ogg binary frameworks.

## Requirements

- Swift 6.2+
- iOS 26+ / macOS 26+

## Add to Your Project

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/petitstrawberry/KanadeKit.git", branch: "main"),
],
targets: [
    .target(name: "YourApp", dependencies: ["KanadeKit"]),
]
```

## Quick Start

```swift
import KanadeKit

let client = KanadeClient(url: URL(string: "ws://192.168.1.10:8080")!)
client.connect()

// SwiftUI
// @State var client = KanadeClient(url: ...)
// client.state?.queue          // [Track]
// client.state?.shuffle        // Bool
// client.state?.repeatMode     // RepeatMode
// client.connected             // Bool

// Playback
client.play()
client.pause()
client.next()
client.previous()
client.seek(to: 30.0)
client.setVolume(75)
client.setRepeat(.all)
client.setShuffle(true)

// Queue
client.addToQueue(track)
client.addTracksToQueue([track1, track2])
client.removeFromQueue(2)
client.moveInQueue(from: 0, to: 3)
client.clearQueue()
client.replaceAndPlay(tracks: playlist, index: 0)

// Library queries — return concrete types
let albums = try await client.getAlbums()
let tracks = try await client.getAlbumTracks(albumId: "abc")
let artists = try await client.getArtists()
let results = try await client.search("Neru")
let (queue, currentIndex) = try await client.getQueue()

// Playlists
let playlists = try await client.getPlaylists()
let playlist = try await client.getPlaylist(playlistId: "pl-1")
let playlistTracks = try await client.getPlaylistTracks(playlistId: "pl-1")

client.createPlaylist(name: "Favorites", description: "Best of", kind: .normal)
client.updatePlaylist(playlistId: "pl-1", name: "Renamed", description: .clear)
client.appendPlaylistTracks(playlistId: "pl-1", trackIds: ["t1", "t2"])
client.movePlaylistTrack(playlistId: "pl-1", from: 0, to: 3)
client.removePlaylistTrack(playlistId: "pl-1", position: 2)
client.deletePlaylist("pl-1")

// Media
let media = MediaClient(baseURL: URL(string: "http://192.168.1.10:8081")!)
let artworkData = try await media.artwork(albumId: "abc123")
let trackUrl = media.trackURL(trackId: "def456") // feed to AVPlayer

// HLS streaming URL (signed, for AVPlayer)
let hlsUrl = try await media.signedHLSURL(trackId: "track-id") // AVPlayer-ready HLS manifest
let hlsPath = media.hlsPath(trackId: "track-id", variant: "lossless") // raw path for signing
```

## API

### KanadeClient

```swift
let client = KanadeClient(
    url: URL(string: "ws://host:8080")!,
    reconnectPolicy: ReconnectPolicy(),      // 3s initial, 5s cap
    heartbeatTimeout: 30.0,                   // receive timeout
    requestTimeout: 10.0                      // per-request timeout
)

client.connect()
client.disconnect()
```

**Playback**

| Method | Description |
|---|---|
| `play()` | Start / resume |
| `pause()` | Pause |
| `stop()` | Stop |
| `next()` | Next track |
| `previous()` | Previous track |
| `seek(to: Double)` | Seek to position (seconds) |
| `setVolume(_ Int)` | Volume 0–100 |
| `setRepeat(_ RepeatMode)` | `.off`, `.one`, `.all` |
| `setShuffle(_ Bool)` | Toggle shuffle |

**Queue**

| Method | Description |
|---|---|
| `addToQueue(_ Track)` | Add single track |
| `addTracksToQueue(_ [Track])` | Add multiple tracks |
| `playIndex(_ Int)` | Play track at index |
| `removeFromQueue(_ Int)` | Remove at index |
| `moveInQueue(from: Int, to: Int)` | Reorder |
| `clearQueue()` | Clear all |
| `replaceAndPlay(tracks: [Track], index: Int)` | Replace queue and play |

**Library Queries** — all return concrete types, no enum unwrapping needed.

| Method | Returns |
|---|---|
| `getAlbums()` | `[Album]` |
| `getAlbumTracks(albumId:)` | `[Track]` |
| `getArtists()` | `[String]` |
| `getArtistAlbums(artist:)` | `[Album]` |
| `getArtistTracks(artist:)` | `[Track]` |
| `getGenres()` | `[String]` |
| `getGenreAlbums(genre:)` | `[Album]` |
| `getGenreTracks(genre:)` | `[Track]` |
| `search(_ query:)` | `[Track]` |
| `getQueue()` | `(tracks: [Track], currentIndex: Int?)` |
| `getPlaylists()` | `[Playlist]` |
| `getPlaylist(playlistId:)` | `Playlist?` |
| `getPlaylistTracks(playlistId:)` | `[Track]` |
| `sendRequest(req:data:)` | `[String: Any]` | Send a custom request (e.g. `sign_urls`) |

**Playlist Mutations** — fire-and-forget. Track mutations apply to `kind: .normal` only.

| Method | Description |
|---|---|
| `createPlaylist(name:description:kind:filter:limit:sortBy:)` | Create a normal or smart playlist |
| `updatePlaylist(playlistId:name:description:kind:)` | Update metadata; `description` uses `DescriptionUpdate` |
| `deletePlaylist(_ String)` | Delete a playlist |
| `setPlaylistTracks(playlistId:trackIds:)` | Replace tracks in a normal playlist |
| `appendPlaylistTracks(playlistId:trackIds:)` | Append tracks |
| `removePlaylistTrack(playlistId:position:)` | Remove track at position |
| `movePlaylistTrack(playlistId:from:to:)` | Reorder track |

`DescriptionUpdate` models the protocol's `Option<Option<String>>` semantics: `.unchanged` omits the field, `.clear` sends `null`, `.set(String)` sends the value.

**Node Selection**

| Method | Description |
|---|---|
| `selectNode(_ String)` | Select output node by ID |
| `localSessionStart(deviceName:deviceId:)` | Start a local playback session |
| `localSessionStop()` | Stop the local playback session |
| `localSessionUpdate(queue:currentIndex:positionSecs:status:volume:repeatMode:shuffle:)` | Update local session state |
| `handoff(fromNodeId:toNodeId:)` | Hand off playback between nodes |

**Observable State** (SwiftUI-ready)

```swift
client.state?.nodes          // [Node]
client.state?.queue          // [Track]
client.state?.selectedNodeId // String?
client.state?.currentIndex   // Int?
client.state?.shuffle        // Bool
client.state?.repeatMode     // RepeatMode
client.connected             // Bool
client.reconnectExhausted    // Bool
```

### KanadeClientDelegate

For non-SwiftUI consumers. All methods have empty default implementations.

```swift
class MyDelegate: KanadeClientDelegate {
    func clientDidConnect(_ client: KanadeClient) { }
    func clientDidDisconnect(_ client: KanadeClient, error: Error?) { }
    func clientDidUpdateConnectionStatus(_ client: KanadeClient) { }
    func client(_ client: KanadeClient, didUpdateState state: PlaybackState) { }
    func client(_ client: KanadeClient, didReceiveError error: Error) { }
    func client(_ client: KanadeClient, didReceiveMediaAuthKeyId keyId: String?) { }
}
client.delegate = MyDelegate()
```

### MediaClient

```swift
let media = MediaClient(baseURL: URL(string: "http://host:8081")!)

// Track URL for AVPlayer (handles Range automatically)
let url = media.trackURL(trackId: "track-id")

// Artwork data
let data = try await media.artwork(albumId: "album-id")

// Raw range request
let (audio, response) = try await media.trackData(trackId: "track-id", range: 0..<1024)
```

**MediaClient Methods**

| Method | Returns | Description |
|---|---|---|
| `trackURL(trackId:)` | `URL` | Unsigned track URL for AVPlayer |
| `signedTrackURL(trackId:refresh:)` | `async throws -> URL` | Signed track URL (refreshes token if needed) |
| `artwork(albumId:)` | `async throws -> Data` | Album artwork image data |
| `trackData(trackId:range:)` | `async throws -> (Data, URLResponse)` | Raw range request for audio data (`Range<Int>?`) |
| `signedHLSURL(trackId:variant:)` | `async throws -> URL` | Signed HLS manifest URL for AVPlayer streaming |
| `hlsPath(trackId:variant:)` | `String` | Raw HLS path (for manual signing) |
| `downloadTrack(trackId:)` | `async throws -> URL` | Download full track to local cache |
| `warmTrackInitialBytes(trackId:byteCount:)` | `async throws -> TrackByteCacheContentInfo` | Preload initial bytes into cache |
| `ensureTrackBytesCached(trackId:range:)` | `async throws -> TrackByteCacheContentInfo` | Ensure a byte range is cached |
| `readCachedTrackBytes(trackId:range:)` | `throws -> Data` | Read bytes from local cache |
| `trackContentInfo(trackId:)` | `throws -> TrackByteCacheContentInfo` | Get cached track metadata |
| `trackByteCacheSnapshot(trackId:)` | `throws -> TrackByteCacheSnapshot` | Get full cache snapshot |
| `cleanupTrackCache()` | `throws` | Evict stale cached tracks |
| `setMediaAuthSigner(_:)` | — | Set a `MediaAuthSigner` for signed URLs |
| `clearMediaAuthSigner()` | — | Clear signer and revoke tokens |

### Models

| Type | Fields |
|---|---|
| `Track` | id, filePath, albumId, title, artist, albumArtist, albumTitle, composer, genre, trackNumber, discNumber, durationSecs, format, sampleRate |
| `Album` | id, dirPath, title, artworkPath |
| `Node` | id, name, connected, nodeType, queue, currentIndex, status, positionSecs, volume, repeatMode, shuffle, deviceId |
| `PlaybackState` | nodes, selectedNodeId, queue, currentIndex, shuffle, repeatMode |
| `PlaybackStatus` | stopped, playing, paused, loading |
| `RepeatMode` | off, one, all |
| `Playlist` | id, name, description, kind, createdAt, updatedAt, filter, limit, sortBy |
| `PlaylistKind` | normal, smart |
| `SmartFilter` | matchMode, conditions |
| `SmartCondition` | field, op, value |
| `SmartField` | title, artist, albumArtist, album, composer, genre |
| `SmartOperator` | equals, notEquals, contains, notContains, startsWith, endsWith |
| `MatchMode` | all, any |
| `SmartSort` | title, artist, album, genre |
| `DescriptionUpdate` | unchanged, clear, set(String) |

All models are `Codable`, `Sendable`, `Equatable`, `Hashable`.

### MediaAuthSigner

Used with `MediaClient` to sign track and artwork URLs. Typically provided by `KanadeClient` or a custom implementation.

```swift
public protocol MediaAuthSigner: Sendable {
    func getSignedUrl(path: String) async throws -> String
    func invalidate(path: String) async
    func clear() async
}
```

The `KanadeClient` exposes `sendRequest(req: "sign_urls", data: ["paths": [...]])` for URL signing.

## License

MIT. See [LICENSE](LICENSE) for details.
