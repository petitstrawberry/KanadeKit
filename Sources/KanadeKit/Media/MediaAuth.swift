import Foundation

public actor MediaAuthSigner {
    public typealias SignURLsHandler = @Sendable ([String]) async throws -> [String: String]

    private struct CachedSignedURL: Sendable {
        let url: String
        let expiry: Date

        func isValid(at date: Date) -> Bool {
            expiry > date.addingTimeInterval(1)
        }
    }

    private let signURLs: SignURLsHandler
    private var cache: [String: CachedSignedURL] = [:]
    private var pendingContinuations: [String: [CheckedContinuation<String, Error>]] = [:]
    private var batchTask: Task<Void, Never>?

    public init(_ signURLs: @escaping SignURLsHandler) {
        self.signURLs = signURLs
    }

    public func getSignedUrl(path: String) async throws -> String {
        let normalizedPath = Self.normalize(path: path)
        let now = Date()

        if let cached = cache[normalizedPath], cached.isValid(at: now) {
            return cached.url
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[normalizedPath, default: []].append(continuation)
            scheduleBatchIfNeeded()
        }
    }

    public func invalidate(path: String) {
        cache.removeValue(forKey: Self.normalize(path: path))
    }

    public func prefetch(paths: [String]) async {
        let normalized = paths.map { Self.normalize(path: $0) }
        let now = Date()
        let missing = normalized.filter { cache[$0]?.isValid(at: now) != true }
        guard !missing.isEmpty else { return }

        do {
            let signedURLs = try await signURLs(missing)
            for path in missing {
                guard let signedURL = signedURLs[path] else { continue }
                let expiry = try? Self.expiryDate(from: signedURL)
                if let expiry, expiry > now.addingTimeInterval(1) {
                    cache[path] = CachedSignedURL(url: signedURL, expiry: expiry)
                }
            }
        } catch {}
    }

    public func clear() {
        cache.removeAll()
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        batchTask?.cancel()
        batchTask = nil

        for continuations in pending.values {
            continuations.forEach { $0.resume(throwing: KanadeError.connectionLost) }
        }
    }

    private func scheduleBatchIfNeeded() {
        guard batchTask == nil else { return }
        batchTask = Task { [weak self] in
            await Task.yield()
            await self?.flushPendingRequests()
        }
    }

    private func flushPendingRequests() async {
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        batchTask = nil

        guard !pending.isEmpty else { return }

        let paths = Array(pending.keys).sorted()

        do {
            let signedURLs = try await signURLs(paths)
            let now = Date()

            for path in paths {
                guard let signedURL = signedURLs[path] else {
                    throw KanadeError.unknownResponse("signed_urls")
                }

                let expiry = try Self.expiryDate(from: signedURL)
                let cached = CachedSignedURL(url: signedURL, expiry: expiry)
                if cached.isValid(at: now) {
                    cache[path] = cached
                } else {
                    cache.removeValue(forKey: path)
                }

                pending[path]?.forEach { $0.resume(returning: signedURL) }
            }
        } catch {
            for continuations in pending.values {
                continuations.forEach { $0.resume(throwing: error) }
            }
        }
    }

    private static func normalize(path: String) -> String {
        path.hasPrefix("/") ? path : "/\(path)"
    }

    private static func expiryDate(from signedURL: String) throws -> Date {
        guard let components = URLComponents(string: signedURL),
              let expValue = components.queryItems?.first(where: { $0.name == "exp" })?.value,
              let exp = TimeInterval(expValue)
        else {
            throw KanadeError.unknownResponse("signed_urls.exp")
        }

        return Date(timeIntervalSince1970: exp)
    }
}
