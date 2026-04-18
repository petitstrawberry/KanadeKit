import Foundation

public struct MediaAuth: Sendable, Equatable {
    public let keyId: String
    public let host: String

    public init(keyId: String, host: String) {
        self.keyId = keyId
        self.host = host
    }

    public func setCookie() {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "kanade_session",
            .value: keyId,
            .domain: host,
            .path: "/media",
            .secure: true,
            .expires: NSDate(timeIntervalSinceNow: 86400),
        ]
        if let cookie = HTTPCookie(properties: properties) {
            DispatchQueue.global(qos: .utility).async {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    public func apply(to request: inout URLRequest) {
        request.setValue("kanade_session=\(keyId)", forHTTPHeaderField: "Cookie")
    }

    public static func clearCookie(host: String) {
        DispatchQueue.global(qos: .utility).async {
            let storage = HTTPCookieStorage.shared
            if let cookies = storage.cookies {
                for cookie in cookies where cookie.name == "kanade_session" && cookie.domain == host {
                    storage.deleteCookie(cookie)
                }
            }
        }
    }
}
