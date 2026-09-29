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

    mutating func recordUnchanged(at now: Date) {
        lastCheck = now
        lastAttempt = now
        lastError = nil
    }

    mutating func recordImported(etag: String?, lastModified: String?, serverBuild: Date?, channelIDs: Set<String>,
                                 at now: Date) {
        self.etag = etag
        self.lastModified = lastModified
        self.serverBuild = serverBuild
        self.channelIDs = channelIDs
        lastCheck = now
        lastAttempt = now
        lastUpdate = now
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

    private func load() -> [String: GuideSourceState] {
        if let cache { return cache }
        let decoded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: GuideSourceState].self, from: $0) } ?? [:]
        cache = decoded
        return decoded
    }
}
