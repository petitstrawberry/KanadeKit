import Foundation

public struct Album: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let dirPath: String
    public let title: String?
    public let artworkPath: String?

    public init(
        id: String,
        dirPath: String,
        title: String? = nil,
        artworkPath: String? = nil
    ) {
        self.id = id
        self.dirPath = dirPath
        self.title = title
        self.artworkPath = artworkPath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case dirPath = "dir_path"
        case title
        case artworkPath = "artwork_path"
    }
}
