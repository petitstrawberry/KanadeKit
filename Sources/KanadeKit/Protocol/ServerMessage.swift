import Foundation

enum ServerMessage: Codable, Sendable, Equatable {
    case state(PlaybackState)
    case response(reqId: UInt64, response: WsResponse)
    case mediaAuth(mediaAuthKey: String, mediaAuthKeyId: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case reqId = "req_id"
        case data
        case mediaAuthKey = "media_auth_key"
        case mediaAuthKeyId = "media_auth_key_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "state":
            self = .state(try container.decode(PlaybackState.self, forKey: .state))
        case "response":
            self = .response(
                reqId: try container.decode(UInt64.self, forKey: .reqId),
                response: try container.decode(WsResponse.self, forKey: .data)
            )
        case "media_auth":
            self = .mediaAuth(
                mediaAuthKey: try container.decode(String.self, forKey: .mediaAuthKey),
                mediaAuthKeyId: try container.decode(String.self, forKey: .mediaAuthKeyId)
            )
        default:
            throw KanadeError.unknownMessageType(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .state(let state):
            try container.encode("state", forKey: .type)
            try container.encode(state, forKey: .state)
        case .response(let reqId, let response):
            try container.encode("response", forKey: .type)
            try container.encode(reqId, forKey: .reqId)
            try container.encode(response, forKey: .data)
        case .mediaAuth(let mediaAuthKey, let mediaAuthKeyId):
            try container.encode("media_auth", forKey: .type)
            try container.encode(mediaAuthKey, forKey: .mediaAuthKey)
            try container.encode(mediaAuthKeyId, forKey: .mediaAuthKeyId)
        }
    }
}
