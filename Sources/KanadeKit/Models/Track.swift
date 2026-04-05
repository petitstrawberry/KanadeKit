import Foundation

public struct Track: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let filePath: String
    public let albumId: String?
    public let title: String?
    public let artist: String?
    public let albumArtist: String?
    public let albumTitle: String?
    public let composer: String?
    public let genre: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let durationSecs: Double?
    public let format: String?
    public let sampleRate: Int?

    public init(
        id: String,
        filePath: String,
        albumId: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        albumTitle: String? = nil,
        composer: String? = nil,
        genre: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        durationSecs: Double? = nil,
        format: String? = nil,
        sampleRate: Int? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.albumId = albumId
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.composer = composer
        self.genre = genre
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationSecs = durationSecs
        self.format = format
        self.sampleRate = sampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case filePath = "file_path"
        case albumId = "album_id"
        case title
        case artist
        case albumArtist = "album_artist"
        case albumTitle = "album_title"
        case composer
        case genre
        case trackNumber = "track_number"
        case discNumber = "disc_number"
        case durationSecs = "duration_secs"
        case format
        case sampleRate = "sample_rate"
    }
}
