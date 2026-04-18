import Foundation

public struct TrackByteCacheContentInfo: Sendable, Equatable {
    public let mimeType: String?
    public let contentLength: Int64?
    public let fileExtension: String?
    public let supportsByteRange: Bool
    public let isComplete: Bool

    public init(
        mimeType: String?,
        contentLength: Int64?,
        fileExtension: String?,
        supportsByteRange: Bool,
        isComplete: Bool
    ) {
        self.mimeType = mimeType
        self.contentLength = contentLength
        self.fileExtension = fileExtension
        self.supportsByteRange = supportsByteRange
        self.isComplete = isComplete
    }
}

public struct TrackByteCacheSnapshot: Sendable, Equatable {
    public let trackId: String
    public let backingFileURL: URL
    public let downloadedRanges: [Range<Int64>]
    public let contentInfo: TrackByteCacheContentInfo

    public init(trackId: String, backingFileURL: URL, downloadedRanges: [Range<Int64>], contentInfo: TrackByteCacheContentInfo) {
        self.trackId = trackId
        self.backingFileURL = backingFileURL
        self.downloadedRanges = downloadedRanges
        self.contentInfo = contentInfo
    }
}

public enum TrackByteCacheError: Error, Sendable, Equatable {
    case invalidRange
    case missingCachedRange(Range<Int64>)
}

public final class TrackByteCacheEntry: @unchecked Sendable {
    public let trackId: String

    private let mediaClient: MediaClient

    internal init(trackId: String, mediaClient: MediaClient) {
        self.trackId = trackId
        self.mediaClient = mediaClient
    }

    deinit {
        mediaClient.releaseTrackByteCache(trackId: trackId)
    }

    public func snapshot() throws -> TrackByteCacheSnapshot {
        return try mediaClient.trackByteCacheSnapshot(for: trackId)
    }

    public func contentInfo() throws -> TrackByteCacheContentInfo {
        return try mediaClient.trackContentInfo(trackId: trackId)
    }

    @discardableResult
    public func warmInitialBytes(byteCount: Int64 = 256 * 1024) async throws -> TrackByteCacheContentInfo {
        return try await mediaClient.warmTrackInitialBytes(trackId: trackId, byteCount: byteCount)
    }

    @discardableResult
    public func ensureCached(range: Range<Int64>) async throws -> TrackByteCacheContentInfo {
        return try await mediaClient.ensureTrackBytesCached(trackId: trackId, range: range)
    }

    public func read(range: Range<Int64>) throws -> Data {
        return try mediaClient.readCachedTrackBytes(trackId: trackId, range: range)
    }
}

internal struct TrackByteCacheFetchResult: Sendable {
    let actualRange: Range<Int64>
    let contentLength: Int64?
    let mimeType: String?
    let fileExtension: String?
    let supportsByteRange: Bool
}

internal final class TrackByteCacheStore: @unchecked Sendable {
    private static let metadataFileName = "metadata.json"
    private static let defaultBackingFileName = "content.track"

    private let cacheDirectoryURL: URL
    private let maxCachedTrackCount: Int
    private let activeTrackProtectionInterval: TimeInterval
    private let fileManager: FileManager
    private let lock = NSLock()
    private var activeReferenceCounts: [String: Int] = [:]

    init(
        cacheDirectoryURL: URL,
        maxCachedTrackCount: Int,
        activeTrackProtectionInterval: TimeInterval,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectoryURL = cacheDirectoryURL
        self.maxCachedTrackCount = maxCachedTrackCount
        self.activeTrackProtectionInterval = activeTrackProtectionInterval
        self.fileManager = fileManager
    }

    func retain(trackId: String) throws {
        try withLock {
            _ = try loadOrCreateRecord(for: trackId)
            activeReferenceCounts[trackId, default: 0] += 1
            _ = try touch(trackId: trackId)
        }
    }

    func release(trackId: String) {
        withLock {
            guard let count = activeReferenceCounts[trackId] else { return }
            if count <= 1 {
                activeReferenceCounts.removeValue(forKey: trackId)
            } else {
                activeReferenceCounts[trackId] = count - 1
            }
        }
    }

    func snapshot(for trackId: String) throws -> TrackByteCacheSnapshot {
        try withLock {
            let record = try touch(trackId: trackId)
            return snapshot(from: record)
        }
    }

    func contentInfo(for trackId: String) throws -> TrackByteCacheContentInfo {
        try withLock {
            let record = try touch(trackId: trackId)
            return contentInfo(from: record)
        }
    }

    func completedFileURL(for trackId: String) throws -> URL? {
        try withLock {
            let record = try touch(trackId: trackId)
            guard record.isComplete else { return nil }
            return entryDirectoryURL(for: trackId).appendingPathComponent(record.backingFileName, isDirectory: false)
        }
    }

    func missingRanges(for trackId: String, requestedRange: Range<Int64>) throws -> [Range<Int64>] {
        try withLock {
            let normalizedRange = try normalize(requestedRange)
            guard !normalizedRange.isEmpty else { return [] }

            let record = try touch(trackId: trackId)
            let clampedRange = clamp(normalizedRange, to: record.contentLength)
            guard !clampedRange.isEmpty else { return [] }

            return subtract(clampedRange, coveredBy: record.downloadedRanges.map(\.rangeValue))
        }
    }

    func applyFetchedData(trackId: String, data: Data, result: TrackByteCacheFetchResult) throws -> TrackByteCacheSnapshot {
        try withLock {
            var record = try loadOrCreateRecord(for: trackId)
            let entryDirectoryURL = self.entryDirectoryURL(for: trackId)

            if let mimeType = result.mimeType {
                record.mimeType = mimeType
            }
            if let contentLength = result.contentLength {
                record.contentLength = contentLength
            }
            if let fileExtension = result.fileExtension {
                record.fileExtension = fileExtension
                let desiredName = Self.backingFileName(for: fileExtension)
                if record.backingFileName != desiredName {
                    try moveBackingFileIfNeeded(from: record.backingFileName, to: desiredName, in: entryDirectoryURL)
                    record.backingFileName = desiredName
                }
            }
            record.supportsByteRange = record.supportsByteRange || result.supportsByteRange

            let fileURL = entryDirectoryURL.appendingPathComponent(record.backingFileName, isDirectory: false)
            try ensureFileExists(at: fileURL)
            try write(data, to: fileURL, atOffset: result.actualRange.lowerBound)

            let mergedRanges = merge(record.downloadedRanges.map(\.rangeValue) + [result.actualRange])
            record.downloadedRanges = mergedRanges.map(TrackByteCachePersistedRange.init)
            if let contentLength = record.contentLength {
                record.isComplete = contains(mergedRanges, requiredRange: 0..<contentLength)
            } else {
                record.isComplete = false
            }
            record.lastAccessedAt = Date()

            try persist(record, for: trackId)
            return snapshot(from: record)
        }
    }

    func replaceWithCompleteFile(trackId: String, sourceURL: URL, contentLength: Int64?, mimeType: String?, fileExtension: String?) throws -> TrackByteCacheSnapshot {
        try withLock {
            var record = try loadOrCreateRecord(for: trackId)
            let entryDirectoryURL = self.entryDirectoryURL(for: trackId)

            let resolvedExtension = fileExtension ?? record.fileExtension
            record.fileExtension = resolvedExtension
            if let mimeType {
                record.mimeType = mimeType
            }

            let destinationFileName = Self.backingFileName(for: resolvedExtension)
            let destinationURL = entryDirectoryURL.appendingPathComponent(destinationFileName, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path()) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)

            let finalContentLength: Int64
            if let contentLength {
                finalContentLength = contentLength
            } else {
                finalContentLength = try fileSize(for: destinationURL)
            }

            if record.backingFileName != destinationFileName {
                let oldURL = entryDirectoryURL.appendingPathComponent(record.backingFileName, isDirectory: false)
                if fileManager.fileExists(atPath: oldURL.path()) {
                    try? fileManager.removeItem(at: oldURL)
                }
            }

            record.backingFileName = destinationFileName
            record.contentLength = finalContentLength
            record.supportsByteRange = true
            record.isComplete = true
            record.downloadedRanges = finalContentLength > 0 ? [TrackByteCachePersistedRange(0..<finalContentLength)] : []
            record.lastAccessedAt = Date()

            try persist(record, for: trackId)
            return snapshot(from: record)
        }
    }

    func read(trackId: String, range: Range<Int64>) throws -> Data {
        try withLock {
            let normalizedRange = try normalize(range)
            let record = try touch(trackId: trackId)
            let clampedRange = clamp(normalizedRange, to: record.contentLength)

            guard !clampedRange.isEmpty else { return Data() }

            let downloadedRanges = record.downloadedRanges.map(\.rangeValue)
            guard contains(downloadedRanges, requiredRange: clampedRange) else {
                throw TrackByteCacheError.missingCachedRange(clampedRange)
            }

            let fileURL = entryDirectoryURL(for: trackId).appendingPathComponent(record.backingFileName, isDirectory: false)
            let byteCount = Int(clampedRange.upperBound - clampedRange.lowerBound)
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(clampedRange.lowerBound))
            let data = try handle.read(upToCount: byteCount) ?? Data()
            guard data.count == byteCount else {
                throw TrackByteCacheError.missingCachedRange(clampedRange)
            }
            return data
        }
    }

    func cleanup() throws {
        try withLock {
            try ensureCacheDirectoryExists()

            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
            let entries = try fileManager.contentsOfDirectory(
                at: cacheDirectoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            let trackDirectories = entries.filter {
                (try? $0.resourceValues(forKeys: resourceKeys).isDirectory) == true
            }

            guard trackDirectories.count > maxCachedTrackCount else { return }

            let protectedCutoff = Date().addingTimeInterval(-activeTrackProtectionInterval)
            var removableDirectories: [(URL, Date)] = []
            for directoryURL in trackDirectories {
                guard let record = try loadRecordIfPresent(atMetadataURL: directoryURL.appendingPathComponent(Self.metadataFileName, isDirectory: false)) else {
                    continue
                }
                guard activeReferenceCounts[record.trackId, default: 0] == 0 else {
                    continue
                }
                guard record.lastAccessedAt < protectedCutoff else {
                    continue
                }
                removableDirectories.append((directoryURL, record.lastAccessedAt))
            }
            removableDirectories.sort { $0.1 < $1.1 }

            var excessCount = trackDirectories.count - maxCachedTrackCount
            guard excessCount > 0 else { return }

            for (directoryURL, _) in removableDirectories where excessCount > 0 {
                try? fileManager.removeItem(at: directoryURL)
                excessCount -= 1
            }
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func ensureCacheDirectoryExists() throws {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func loadOrCreateRecord(for trackId: String) throws -> TrackByteCacheRecord {
        try ensureCacheDirectoryExists()

        let entryDirectoryURL = self.entryDirectoryURL(for: trackId)
        let metadataURL = entryDirectoryURL.appendingPathComponent(Self.metadataFileName, isDirectory: false)
        if let existing = try loadRecordIfPresent(atMetadataURL: metadataURL) {
            try ensureBackingFileExists(for: existing, trackId: trackId)
            return existing
        }

        if let migrated = try migrateLegacyCacheIfNeeded(for: trackId) {
            return migrated
        }

        try fileManager.createDirectory(at: entryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let record = TrackByteCacheRecord(
            trackId: trackId,
            contentLength: nil,
            mimeType: nil,
            fileExtension: nil,
            supportsByteRange: false,
            isComplete: false,
            downloadedRanges: [],
            backingFileName: Self.defaultBackingFileName,
            lastAccessedAt: Date()
        )
        try ensureBackingFileExists(for: record, trackId: trackId)
        try persist(record, for: trackId)
        return record
    }

    private func touch(trackId: String) throws -> TrackByteCacheRecord {
        var record = try loadOrCreateRecord(for: trackId)
        record.lastAccessedAt = Date()
        try persist(record, for: trackId)
        return record
    }

    private func persist(_ record: TrackByteCacheRecord, for trackId: String) throws {
        let metadataURL = entryDirectoryURL(for: trackId).appendingPathComponent(Self.metadataFileName, isDirectory: false)
        let data = try JSONEncoder().encode(record)
        try data.write(to: metadataURL, options: [.atomic])
    }

    private func loadRecordIfPresent(atMetadataURL metadataURL: URL) throws -> TrackByteCacheRecord? {
        guard fileManager.fileExists(atPath: metadataURL.path()) else { return nil }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(TrackByteCacheRecord.self, from: data)
    }

    private func ensureBackingFileExists(for record: TrackByteCacheRecord, trackId: String) throws {
        try fileManager.createDirectory(at: entryDirectoryURL(for: trackId), withIntermediateDirectories: true, attributes: nil)
        try ensureFileExists(at: entryDirectoryURL(for: trackId).appendingPathComponent(record.backingFileName, isDirectory: false))
    }

    private func ensureFileExists(at fileURL: URL) throws {
        guard !fileManager.fileExists(atPath: fileURL.path()) else { return }
        if !fileManager.createFile(atPath: fileURL.path(), contents: nil) {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func moveBackingFileIfNeeded(from currentFileName: String, to newFileName: String, in directoryURL: URL) throws {
        guard currentFileName != newFileName else { return }
        let currentURL = directoryURL.appendingPathComponent(currentFileName, isDirectory: false)
        let newURL = directoryURL.appendingPathComponent(newFileName, isDirectory: false)
        if fileManager.fileExists(atPath: currentURL.path()) {
            if fileManager.fileExists(atPath: newURL.path()) {
                try fileManager.removeItem(at: newURL)
            }
            try fileManager.moveItem(at: currentURL, to: newURL)
        } else {
            try ensureFileExists(at: newURL)
        }
    }

    private func write(_ data: Data, to fileURL: URL, atOffset offset: Int64) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
    }

    private func fileSize(for fileURL: URL) throws -> Int64 {
        Int64((try fileManager.attributesOfItem(atPath: fileURL.path())[.size] as? NSNumber)?.int64Value ?? 0)
    }

    private func migrateLegacyCacheIfNeeded(for trackId: String) throws -> TrackByteCacheRecord? {
        let prefix = mediaTrackCacheFilePrefix(for: trackId)
        let legacyEntries = try fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.deletingLastPathComponent() == cacheDirectoryURL &&
            $0.lastPathComponent.hasPrefix(prefix) &&
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        guard let legacyFileURL = legacyEntries.first(where: { $0.pathExtension != "track" }) else {
            legacyEntries
                .filter { $0.pathExtension == "track" }
                .forEach { try? fileManager.removeItem(at: $0) }
            return nil
        }

        let entryDirectoryURL = self.entryDirectoryURL(for: trackId)
        try fileManager.createDirectory(at: entryDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let fileExtension = legacyFileURL.pathExtension.isEmpty ? nil : legacyFileURL.pathExtension.lowercased()
        let destinationFileName = Self.backingFileName(for: fileExtension)
        let destinationURL = entryDirectoryURL.appendingPathComponent(destinationFileName, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: legacyFileURL, to: destinationURL)

        legacyEntries
            .filter { $0 != legacyFileURL }
            .forEach { try? fileManager.removeItem(at: $0) }

        let contentLength = try fileSize(for: destinationURL)
        let record = TrackByteCacheRecord(
            trackId: trackId,
            contentLength: contentLength,
            mimeType: mediaMimeType(forFileExtension: fileExtension),
            fileExtension: fileExtension,
            supportsByteRange: true,
            isComplete: true,
            downloadedRanges: contentLength > 0 ? [TrackByteCachePersistedRange(0..<contentLength)] : [],
            backingFileName: destinationFileName,
            lastAccessedAt: Date()
        )
        try persist(record, for: trackId)
        return record
    }

    private func entryDirectoryURL(for trackId: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(mediaTrackCacheFilePrefix(for: trackId), isDirectory: true)
    }

    private func contentInfo(from record: TrackByteCacheRecord) -> TrackByteCacheContentInfo {
        TrackByteCacheContentInfo(
            mimeType: record.mimeType,
            contentLength: record.contentLength,
            fileExtension: record.fileExtension,
            supportsByteRange: record.supportsByteRange,
            isComplete: record.isComplete
        )
    }

    private func snapshot(from record: TrackByteCacheRecord) -> TrackByteCacheSnapshot {
        TrackByteCacheSnapshot(
            trackId: record.trackId,
            backingFileURL: entryDirectoryURL(for: record.trackId).appendingPathComponent(record.backingFileName, isDirectory: false),
            downloadedRanges: record.downloadedRanges.map(\.rangeValue),
            contentInfo: contentInfo(from: record)
        )
    }

    private func normalize(_ range: Range<Int64>) throws -> Range<Int64> {
        guard range.lowerBound >= 0, range.upperBound >= range.lowerBound else {
            throw TrackByteCacheError.invalidRange
        }
        return range
    }

    private func clamp(_ range: Range<Int64>, to contentLength: Int64?) -> Range<Int64> {
        guard let contentLength else { return range }
        let upperBound = min(range.upperBound, contentLength)
        let lowerBound = min(range.lowerBound, upperBound)
        return lowerBound..<upperBound
    }

    private func contains(_ ranges: [Range<Int64>], requiredRange: Range<Int64>) -> Bool {
        guard !requiredRange.isEmpty else { return true }
        return ranges.contains { $0.lowerBound <= requiredRange.lowerBound && $0.upperBound >= requiredRange.upperBound }
    }

    private func subtract(_ requestedRange: Range<Int64>, coveredBy coveredRanges: [Range<Int64>]) -> [Range<Int64>] {
        var missingRanges: [Range<Int64>] = [requestedRange]
        for coveredRange in merge(coveredRanges) {
            missingRanges = missingRanges.flatMap { missingRange in
                guard let overlap = intersection(missingRange, coveredRange) else {
                    return [missingRange]
                }

                var segments: [Range<Int64>] = []
                if missingRange.lowerBound < overlap.lowerBound {
                    segments.append(missingRange.lowerBound..<overlap.lowerBound)
                }
                if overlap.upperBound < missingRange.upperBound {
                    segments.append(overlap.upperBound..<missingRange.upperBound)
                }
                return segments
            }
        }
        return missingRanges
    }

    private func merge(_ ranges: [Range<Int64>]) -> [Range<Int64>] {
        let sortedRanges = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }

        var merged: [Range<Int64>] = []
        for range in sortedRanges {
            guard !range.isEmpty else { continue }
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private func intersection(_ lhs: Range<Int64>, _ rhs: Range<Int64>) -> Range<Int64>? {
        let lowerBound = max(lhs.lowerBound, rhs.lowerBound)
        let upperBound = min(lhs.upperBound, rhs.upperBound)
        guard lowerBound < upperBound else { return nil }
        return lowerBound..<upperBound
    }

    private static func backingFileName(for fileExtension: String?) -> String {
        let ext = (fileExtension?.isEmpty == false ? fileExtension : nil) ?? "track"
        return "content.\(ext)"
    }
}

internal struct TrackByteCacheRecord: Codable, Sendable {
    let trackId: String
    var contentLength: Int64?
    var mimeType: String?
    var fileExtension: String?
    var supportsByteRange: Bool
    var isComplete: Bool
    var downloadedRanges: [TrackByteCachePersistedRange]
    var backingFileName: String
    var lastAccessedAt: Date
}

internal struct TrackByteCachePersistedRange: Codable, Sendable {
    let lowerBound: Int64
    let upperBound: Int64

    init(_ range: Range<Int64>) {
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    var rangeValue: Range<Int64> {
        lowerBound..<upperBound
    }
}

internal func mediaTrackCacheFilePrefix(for trackId: String) -> String {
    Data(trackId.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "=", with: "")
}

internal func mediaMimeType(forFileExtension fileExtension: String?) -> String? {
    switch fileExtension?.lowercased() {
    case "mp3": return "audio/mpeg"
    case "flac": return "audio/flac"
    case "wav": return "audio/wav"
    case "m4a", "mp4": return "audio/mp4"
    case "aac": return "audio/aac"
    case "ogg": return "audio/ogg"
    case "aiff", "aif": return "audio/aiff"
    case "dsf": return "audio/x-dsf"
    default: return nil
    }
}

internal func mediaFileExtension(forMimeType mimeType: String?) -> String? {
    guard let mimeType else { return nil }
    switch mimeType.lowercased() {
    case "audio/mpeg", "audio/mp3": return "mp3"
    case "audio/flac": return "flac"
    case "audio/wav", "audio/wave": return "wav"
    case "audio/mp4", "audio/x-m4a": return "m4a"
    case "audio/aac": return "aac"
    case "audio/ogg": return "ogg"
    case "audio/aiff", "audio/x-aiff": return "aiff"
    case "audio/x-dsf": return "dsf"
    default: return nil
    }
}
