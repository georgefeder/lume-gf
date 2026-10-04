import Foundation

/// What Lume GF remembers about one guide source between checks.
nonisolated struct GuideSourceState: Codable, Equatable {
    /// The server's fingerprint and date of the guide currently imported (sent back as If-None-Match /
    /// If-Modified-Since). They change only after a new guide was imported completely.
    var etag: String?
    var lastModified: String?
    /// The server's build time of that guide (the parsed Last-Modified).
    var serverBuild: Date?
    /// Last good check: a new guide imported completely, or "unchanged".
    var lastCheck: Date?
    /// Last try of any outcome, good or failed.
    var lastAttempt: Date?
    /// Last time a new guide was imported completely.
    var lastUpdate: Date?
    /// Short, credential-free reason the last try failed; nil after a good check.
    var lastError: String?
    /// Channels this source guided in its last complete import, so an "unchanged" answer keeps its claims.
    var channelIDs: Set<String> = []
    /// SHA-256 of the guide file last imported, and the channels it was imported for (`GuideFingerprint.ofSet`): the
    /// same file for the same channels is not imported again (a server that sends no ETag or Last-Modified hands out
    /// the whole guide every time), and changed channels download the guide in full instead of asking "changed?".
    var fileHash: String?
    var channelsKey: UInt64?

    /// Whether the server may be asked "changed since?": only for the channels the stored guide was imported for.
    func mayAskUnchanged(channelsKey key: UInt64) -> Bool {
        channelsKey == key
    }

    /// The downloaded file is the one already imported, for the same channels.
    func isSameFile(hash: String?, channelsKey key: UInt64) -> Bool {
        hash != nil && hash == fileHash && channelsKey == key
    }

    mutating func recordUnchanged(at now: Date) {
        lastCheck = now
        lastAttempt = now
        lastError = nil
    }

    mutating func recordImported(etag: String?, lastModified: String?, serverBuild: Date?, channelIDs: Set<String>,
                                 at now: Date, fileHash: String? = nil, channelsKey: UInt64? = nil) {
        self.fileHash = fileHash
        self.channelsKey = channelsKey
        self.etag = etag
        self.lastModified = lastModified
        self.serverBuild = serverBuild
        self.channelIDs = channelIDs
        lastCheck = now
        lastAttempt = now
        lastUpdate = now
        lastError = nil
    }

    /// The server sent the file already imported: a good check, and its new validators are kept for next time.
    mutating func recordSameFile(etag: String?, lastModified: String?, serverBuild: Date?, at now: Date) {
        self.etag = etag
        self.lastModified = lastModified
        self.serverBuild = serverBuild
        lastCheck = now
        lastAttempt = now
        lastError = nil
    }

    /// A failed or cut-off try keeps the previous guide's validators, so the next check downloads again.
    mutating func recordFailure(_ reason: String, at now: Date) {
        lastAttempt = now
        lastError = reason
    }
}

/// Every source's state in one small JSON file, safe to use from any thread. The shared store sits next to Lume's
/// own database (`default.store` in Application Support), so a storage cleanup removes both together.
nonisolated final class GuideSourceStateStore: @unchecked Sendable {
    static let shared = GuideSourceStateStore(
        fileURL: URL.applicationSupportDirectory.appending(path: "GuideSourceState.json")
    )

    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: GuideSourceState]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func state(for sourceID: UUID) -> GuideSourceState {
        lock.withLock { load()[sourceID.uuidString] ?? GuideSourceState() }
    }

    func all() -> [String: GuideSourceState] {
        lock.withLock { load() }
    }

    func update(_ sourceID: UUID, _ mutate: (inout GuideSourceState) -> Void) {
        lock.withLock {
            var states = load()
            var state = states[sourceID.uuidString] ?? GuideSourceState()
            mutate(&state)
            states[sourceID.uuidString] = state
            cache = states
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(states) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Every source downloads and imports in full next time (a guide-schema bump back-fills new columns).
    func forgetFiles() {
        for id in all().keys.compactMap(UUID.init(uuidString:)) {
            update(id) {
                $0.fileHash = nil
                $0.channelsKey = nil
                $0.etag = nil
                $0.lastModified = nil
            }
        }
    }

    private func load() -> [String: GuideSourceState] {
        if let cache { return cache }
        let decoded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: GuideSourceState].self, from: $0) } ?? [:]
        cache = decoded
        return decoded
    }
}
