import Foundation
import Security

public final class MediaClient: @unchecked Sendable {
    private static let trackCacheDirectoryName = "kanade_tracks"
    private static let maxCachedTrackCount = 12
    private static let activeTrackProtectionInterval: TimeInterval = 300

    public static let defaultTrackWarmupByteCount: Int64 = 256 * 1024

    private let baseURL: URL
    private let session: URLSession
    private let cacheStore: TrackByteCacheStore
    private let stateLock = NSLock()
    private var mediaAuthSigner: MediaAuthSigner?

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        self.session = session
        let cacheDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.trackCacheDirectoryName, isDirectory: true)
        self.cacheStore = TrackByteCacheStore(
            cacheDirectoryURL: cacheDirectoryURL,
            maxCachedTrackCount: Self.maxCachedTrackCount,
            activeTrackProtectionInterval: Self.activeTrackProtectionInterval
        )
    }

    public convenience init(host: String, port: Int, useTLS: Bool = false, tlsConfiguration: TLSConfiguration? = nil) {
        let scheme = useTLS ? "https" : "http"
        let url = URL(string: "\(scheme)://\(host):\(port)")!
        let session: URLSession
        if let tlsConfig = tlsConfiguration,
           tlsConfig.clientIdentity != nil
            || tlsConfig.trustedCACertificates?.isEmpty == false
            || tlsConfig.allowSelfSignedServer {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            let credential = tlsConfig.clientIdentity.map {
                URLCredential(identity: $0, certificates: nil, persistence: .forSession)
            }
            session = URLSession(
                configuration: config,
                delegate: TLSURLSessionDelegate(
                    clientCredential: credential,
                    trustedCertificates: tlsConfig.trustedCACertificates ?? [],
                    allowSelfSignedServer: tlsConfig.allowSelfSignedServer
                ),
                delegateQueue: nil
            )
        } else {
            session = .shared
        }
        self.init(baseURL: url, session: session)
    }

    public func setMediaAuthSigner(_ signer: MediaAuthSigner) {
        stateLock.lock()
        mediaAuthSigner = signer
        stateLock.unlock()
    }

    public func clearMediaAuthSigner() {
        stateLock.lock()
        let signer = mediaAuthSigner
        mediaAuthSigner = nil
        stateLock.unlock()

        if let signer {
            Task {
                await signer.clear()
            }
        }
    }

    public func trackURL(trackId: String) -> URL {
        baseURL.appendingPathComponent("media/tracks/\(trackId)")
    }

    public func signedTrackURL(trackId: String, refresh: Bool = false) async throws -> URL {
        try await resolvedURL(path: mediaPath("tracks/\(trackId)"), refresh: refresh)
    }

    /// Returns the HLS path for a track (used with signer for signed URLs)
    public func hlsPath(trackId: String, variant: String = "lossless") -> String {
        return "/media/hls/\(trackId)/\(variant)/index.m3u8"
    }

    /// Returns a signed HLS manifest URL for streaming playback
    public func signedHLSURL(trackId: String, variant: String = "lossless") async throws -> URL {
        return try await resolvedURL(path: hlsPath(trackId: trackId, variant: variant))
    }

    public func artwork(albumId: String) async throws -> Data {
        let path = mediaPath("art/\(albumId)")
        let (data, response) = try await performDataRequest(path: path)

        guard (200...299).contains(response.statusCode) else {
            throw KanadeError.httpError(statusCode: response.statusCode)
        }

        return data
    }

    public func trackByteCacheEntry(trackId: String) throws -> TrackByteCacheEntry {
        try cacheStore.retain(trackId: trackId)
        return TrackByteCacheEntry(trackId: trackId, mediaClient: self)
    }

    public func warmTrackInitialBytes(trackId: String, byteCount: Int64 = 256 * 1024) async throws -> TrackByteCacheContentInfo {
        guard byteCount > 0 else {
            return try trackContentInfo(trackId: trackId)
        }
        return try await ensureTrackBytesCached(trackId: trackId, range: 0..<byteCount)
    }

    @discardableResult
    public func ensureTrackBytesCached(trackId: String, range: Range<Int64>) async throws -> TrackByteCacheContentInfo {
        let missingRanges = try cacheStore.missingRanges(for: trackId, requestedRange: range)
        if missingRanges.isEmpty {
            return try cacheStore.contentInfo(for: trackId)
        }

        var lastSnapshot: TrackByteCacheSnapshot?
        for missingRange in missingRanges {
            let (data, response) = try await fetchTrackData(trackId: trackId, range: missingRange)
            let result = try makeFetchResult(from: response, requestedRange: missingRange, receivedByteCount: data.count)
            lastSnapshot = try cacheStore.applyFetchedData(trackId: trackId, data: data, result: result)
        }

        try cleanupTrackCache()
        if let contentInfo = lastSnapshot?.contentInfo {
            return contentInfo
        }
        return try cacheStore.contentInfo(for: trackId)
    }

    public func readCachedTrackBytes(trackId: String, range: Range<Int64>) throws -> Data {
        try cacheStore.read(trackId: trackId, range: range)
    }

    public func trackContentInfo(trackId: String) throws -> TrackByteCacheContentInfo {
        try cacheStore.contentInfo(for: trackId)
    }

    public func trackByteCacheSnapshot(trackId: String) throws -> TrackByteCacheSnapshot {
        try cacheStore.snapshot(for: trackId)
    }

    public func trackData(trackId: String, range: Range<Int>? = nil) async throws -> (Data, HTTPURLResponse) {
        try await fetchTrackData(trackId: trackId, range: range.map { Int64($0.lowerBound)..<Int64($0.upperBound) })
    }

    public func downloadTrack(trackId: String) async throws -> URL {
        if let completedFileURL = try cacheStore.completedFileURL(for: trackId) {
            try cleanupTrackCache()
            return completedFileURL
        }

        let path = mediaPath("tracks/\(trackId)")
        let (temporaryURL, httpResponse) = try await performDownloadRequest(path: path)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw KanadeError.httpError(statusCode: httpResponse.statusCode)
        }

        let snapshot = try cacheStore.replaceWithCompleteFile(
            trackId: trackId,
            sourceURL: temporaryURL,
            contentLength: resolvedContentLength(from: httpResponse),
            mimeType: httpResponse.mimeType,
            fileExtension: mediaFileExtension(forMimeType: httpResponse.mimeType)
        )

        try cleanupTrackCache()
        return snapshot.backingFileURL
    }

    public func cleanupTrackCache() throws {
        try cacheStore.cleanup()
    }

    internal func releaseTrackByteCache(trackId: String) {
        cacheStore.release(trackId: trackId)
    }

    internal func trackByteCacheSnapshot(for trackId: String) throws -> TrackByteCacheSnapshot {
        try cacheStore.snapshot(for: trackId)
    }

    private func fetchTrackData(trackId: String, range: Range<Int64>?) async throws -> (Data, HTTPURLResponse) {
        let path = mediaPath("tracks/\(trackId)")
        let (data, httpResponse) = try await performDataRequest(path: path, range: range)

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
            throw KanadeError.httpError(statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    private func performDataRequest(path: String, range: Range<Int64>? = nil) async throws -> (Data, HTTPURLResponse) {
        var didRefresh = false

        while true {
            let request = try await makeSignedRequest(path: path, range: range, refresh: didRefresh)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KanadeError.httpError(statusCode: -1)
            }

            if httpResponse.statusCode == 403, !didRefresh {
                didRefresh = true
                continue
            }

            return (data, httpResponse)
        }
    }

    private func performDownloadRequest(path: String) async throws -> (URL, HTTPURLResponse) {
        var didRefresh = false

        while true {
            let request = try await makeSignedRequest(path: path, refresh: didRefresh)
            let (temporaryURL, response) = try await session.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw KanadeError.httpError(statusCode: -1)
            }

            if httpResponse.statusCode == 403, !didRefresh {
                didRefresh = true
                continue
            }

            return (temporaryURL, httpResponse)
        }
    }

    private func makeSignedRequest(path: String, range: Range<Int64>? = nil, refresh: Bool = false) async throws -> URLRequest {
        let url = try await resolvedURL(path: path, refresh: refresh)
        var request = URLRequest(url: url)
        if let range {
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func resolvedURL(path: String) async throws -> URL {
        try await resolvedURL(path: path, refresh: false)
    }

    private func resolvedURL(path: String, refresh: Bool) async throws -> URL {
        let normalizedPath = normalizeMediaPath(path)

        if let signer = mediaAuthSignerReference() {
            if refresh {
                await signer.invalidate(path: normalizedPath)
            }
            let signedURLString = try await signer.getSignedUrl(path: normalizedPath)
            guard let signedURL = URL(string: signedURLString) else {
                throw KanadeError.unknownResponse("signed_urls")
            }
            return signedURL
        }

        guard !refresh else {
            throw KanadeError.notConnected
        }

        return baseURL.appending(path: normalizedPath)
    }

    public func mediaAuthSignerReference() -> MediaAuthSigner? {
        stateLock.lock()
        let signer = mediaAuthSigner
        stateLock.unlock()
        return signer
    }

    private func mediaPath(_ pathComponent: String) -> String {
        "/media/\(pathComponent)"
    }

    private func normalizeMediaPath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }

    private func makeFetchResult(from response: HTTPURLResponse, requestedRange: Range<Int64>, receivedByteCount: Int) throws -> TrackByteCacheFetchResult {
        let contentLength = resolvedContentLength(from: response)
        let mimeType = response.mimeType
        let fileExtension = mediaFileExtension(forMimeType: mimeType)
        let supportsByteRange = response.statusCode == 206 || response.value(forHTTPHeaderField: "Accept-Ranges")?.localizedCaseInsensitiveContains("bytes") == true

        if response.statusCode == 206,
           let contentRangeHeader = response.value(forHTTPHeaderField: "Content-Range"),
           let parsedRange = parseContentRange(contentRangeHeader) {
            return TrackByteCacheFetchResult(
                actualRange: parsedRange.range,
                contentLength: parsedRange.totalLength ?? contentLength,
                mimeType: mimeType,
                fileExtension: fileExtension,
                supportsByteRange: true
            )
        }

        if response.statusCode == 200 {
            let actualLength = Int64(receivedByteCount)
            return TrackByteCacheFetchResult(
                actualRange: 0..<actualLength,
                contentLength: contentLength ?? actualLength,
                mimeType: mimeType,
                fileExtension: fileExtension,
                supportsByteRange: supportsByteRange
            )
        }

        let actualLength = Int64(receivedByteCount)
        return TrackByteCacheFetchResult(
            actualRange: requestedRange.lowerBound..<(requestedRange.lowerBound + actualLength),
            contentLength: contentLength,
            mimeType: mimeType,
            fileExtension: fileExtension,
            supportsByteRange: supportsByteRange
        )
    }

    private func resolvedContentLength(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let parsed = parseContentRange(contentRange),
           let totalLength = parsed.totalLength {
            return totalLength
        }

        if response.expectedContentLength > 0 {
            return response.expectedContentLength
        }

        if let contentLengthHeader = response.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int64(contentLengthHeader) {
            return contentLength
        }

        return nil
    }

    private func parseContentRange(_ headerValue: String) -> (range: Range<Int64>, totalLength: Int64?)? {
        guard headerValue.lowercased().hasPrefix("bytes ") else { return nil }
        let components = headerValue.dropFirst(6).split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }

        let rangePart = components[0]
        let totalPart = components[1]
        let bounds = rangePart.split(separator: "-", maxSplits: 1).map(String.init)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let endInclusive = Int64(bounds[1]),
              endInclusive >= start else {
            return nil
        }

        let totalLength = totalPart == "*" ? nil : Int64(totalPart)
        return (start..<(endInclusive + 1), totalLength)
    }
}

private final class TLSURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let clientCredential: URLCredential?
    private let trustedCertificates: [SecCertificate]
    private let allowSelfSignedServer: Bool

    init(
        clientCredential: URLCredential?,
        trustedCertificates: [SecCertificate],
        allowSelfSignedServer: Bool
    ) {
        self.clientCredential = clientCredential
        self.trustedCertificates = trustedCertificates
        self.allowSelfSignedServer = allowSelfSignedServer
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let clientCredential {
                completionHandler(.useCredential, clientCredential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            if !trustedCertificates.isEmpty {
                SecTrustSetAnchorCertificates(trust, trustedCertificates as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            } else if allowSelfSignedServer {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}
