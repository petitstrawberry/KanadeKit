import Foundation

/// HTTP client for Kanade media surface (track streaming + artwork).
/// Endpoints:
///   GET /media/tracks/<track_id>  — audio (supports Range)
///   GET /media/art/<album_id>     — image (jpg/png)
public final class MediaClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    
    public init(baseURL: URL, session: URLSession = .shared) {
        // Ensure baseURL doesn't have trailing slash
        self.baseURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        self.session = session
    }
    
    // MARK: - Track URL
    
    /// Returns a URL for the given track, suitable for AVPlayer.
    /// AVPlayer handles Range requests automatically.
    public func trackURL(trackId: String) -> URL {
        baseURL.appendingPathComponent("media/tracks/\(trackId)")
    }
    
    // MARK: - Artwork
    
    /// Fetches artwork image data for the given album.
    public func artwork(albumId: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("media/art/\(albumId)")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KanadeError.httpError(statusCode: -1)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw KanadeError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    // MARK: - Raw Track Data
    
    /// Fetches raw track data with optional byte range.
    /// Useful for scenarios outside AVPlayer.
    public func trackData(trackId: String, range: Range<Int>? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = baseURL.appendingPathComponent("media/tracks/\(trackId)")
        var request = URLRequest(url: url)
        
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
