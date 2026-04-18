import Foundation
import Testing
@testable import KanadeKit

@Suite("MediaClient")
struct MediaClientTests {
    @Test func trackURLConstruction() {
        let client = MediaClient(baseURL: URL(string: "http://localhost:8081")!)
        let url = client.trackURL(trackId: "abc123")
        #expect(url.absoluteString == "http://localhost:8081/media/tracks/abc123")
    }

    @Test func trackURLWithTrailingSlash() {
        let client = MediaClient(baseURL: URL(string: "http://localhost:8081/")!)
        let url = client.trackURL(trackId: "abc123")
        #expect(url.absoluteString == "http://localhost:8081/media/tracks/abc123")
    }

    @Test func trackURLWithPathBaseURL() {
        let client = MediaClient(baseURL: URL(string: "https://kanade.example.com/api/")!)
        let url = client.trackURL(trackId: "track-xyz")
        #expect(url.absoluteString == "https://kanade.example.com/api/media/tracks/track-xyz")
    }

    @Test func sendableConformance() {
        requireSendable(MediaClient.self)
        let client = MediaClient(baseURL: URL(string: "http://localhost:8081")!)
        let box = Box(client)
        #expect(ObjectIdentifier(box.client) == ObjectIdentifier(client))
    }

    @Test func byteCacheEntryCreation() throws {
        let client = MediaClient(baseURL: URL(string: "http://localhost:8081")!)
        let entry = try client.trackByteCacheEntry(trackId: "abc123")

        let snapshot = try entry.snapshot()
        #expect(snapshot.trackId == "abc123")
        #expect(snapshot.downloadedRanges.isEmpty)
        #expect(snapshot.backingFileURL.deletingLastPathComponent().lastPathComponent == "YWJjMTIz")
        #expect(snapshot.contentInfo.contentLength == nil)
        #expect(snapshot.contentInfo.mimeType == nil)
        #expect(snapshot.contentInfo.fileExtension == nil)
        #expect(snapshot.contentInfo.supportsByteRange == false)
        #expect(snapshot.contentInfo.isComplete == false)
    }
}

private final class Box: Sendable {
    let client: MediaClient

    init(_ client: MediaClient) {
        self.client = client
    }
}

private func requireSendable<T: Sendable>(_: T.Type) {}
