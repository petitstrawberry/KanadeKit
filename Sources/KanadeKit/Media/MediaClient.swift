import Foundation

public final class MediaClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private var mediaAuth: MediaAuth?

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        self.session = session
    }

    public convenience init(host: String, port: Int, useTLS: Bool = false, tlsConfiguration: TLSConfiguration? = nil) {
        let scheme = useTLS ? "https" : "http"
        let url = URL(string: "\(scheme)://\(host):\(port)")!
        let session: URLSession
        if let tlsConfig = tlsConfiguration, let identity = tlsConfig.clientIdentity {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpShouldSetCookies = true
            config.urlCredentialStorage = nil
            let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
            session = URLSession(configuration: config, delegate: ClientCertDelegate(credential: credential), delegateQueue: nil)
        } else {
            session = .shared
        }
        self.init(baseURL: url, session: session)
    }

    public func setMediaAuthKey(_ keyId: String, host: String) {
        let auth = MediaAuth(keyId: keyId, host: host)
        auth.setCookie()
        self.mediaAuth = auth
    }

    public func clearMediaAuth() {
        if let auth = mediaAuth {
            MediaAuth.clearCookie(host: auth.host)
        }
        mediaAuth = nil
    }

    // MARK: - Track URL

    public func trackURL(trackId: String) -> URL {
        baseURL.appendingPathComponent("media/tracks/\(trackId)")
    }

    // MARK: - Artwork

    public func artwork(albumId: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("media/art/\(albumId)")
        var request = URLRequest(url: url)
        mediaAuth?.apply(to: &request)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KanadeError.httpError(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw KanadeError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: - Raw Track Data

    public func trackData(trackId: String, range: Range<Int>? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = baseURL.appendingPathComponent("media/tracks/\(trackId)")
        var request = URLRequest(url: url)
        mediaAuth?.apply(to: &request)

        if let range {
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KanadeError.httpError(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            throw KanadeError.httpError(statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }
}

private final class ClientCertDelegate: NSObject, URLSessionDelegate, Sendable {
    private let credential: URLCredential

    init(credential: URLCredential) {
        self.credential = credential
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
