import Foundation

public enum SmartField: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case title
    case artist
    case albumArtist = "album_artist"
    case album
    case composer
    case genre
}

public enum SmartOperator: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case equals
    case notEquals = "not_equals"
    case contains
    case notContains = "not_contains"
    case startsWith = "starts_with"
    case endsWith = "ends_with"
}

public enum MatchMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case all
    case any
}

public enum SmartSort: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case title
    case artist
    case album
    case genre
}

public struct SmartCondition: Codable, Sendable, Equatable, Hashable {
    public let field: SmartField
    public let op: SmartOperator
    public let value: String

    public init(field: SmartField, op: SmartOperator, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case op
        case value
    }
}

public struct SmartFilter: Codable, Sendable, Equatable, Hashable {
    public let matchMode: MatchMode
    public let conditions: [SmartCondition]

    public init(matchMode: MatchMode, conditions: [SmartCondition]) {
        self.matchMode = matchMode
        self.conditions = conditions
    }

    private enum CodingKeys: String, CodingKey {
        case matchMode = "match_mode"
        case conditions
    }
}

public enum PlaylistKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case normal
    case smart
}

/// A user-curated playlist (`normal`) or dynamic playlist (`smart`).
///
/// The `kind` field discriminates between the two variants. Smart playlists
/// carry an additional `filter` plus optional `limit` and `sortBy` describing
/// how the contents are computed against the library.
public struct Playlist: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let kind: PlaylistKind
    public let createdAt: Int64
    public let updatedAt: Int64

    public let filter: SmartFilter?
    public let limit: Int?
    public let sortBy: SmartSort?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        kind: PlaylistKind,
        createdAt: Int64,
        updatedAt: Int64,
        filter: SmartFilter? = nil,
        limit: Int? = nil,
        sortBy: SmartSort? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.filter = filter
        self.limit = limit
        self.sortBy = sortBy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case kind
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case filter
        case limit
        case sortBy = "sort_by"
    }
}
