import Foundation
import SwiftData

/// One guide source's refresh for Lume GF: a conditional download, then an only-what-changed import that never
/// empties the stored guide. One instance serves one `EPGSyncManager.syncAllSources` run (all its sources).
nonisolated final class GuideRefresher {
    enum Failure: Error, Equatable {
        case incompleteFile
    }

    struct Outcome: Equatable {
        var claimedChannelIDs: Set<String>
        var summary: String
    }

    let container: ModelContainer
    let fetcher: GuideFetcher
    let states: GuideSourceStateStore
    let now: () -> Date
    /// Every channel of every playlist this run (EPGSyncManager): old programmes of other channels are orphans.
    var allChannelIDs: Set<String>?
    /// A stale guide's programmes on now are in, ahead of the rest of its file (EPGSyncManager tells the guide screens).
    var onNowReady: @Sendable () -> Void = {}
    private var index: GuideStoredIndex?

    init(container: ModelContainer, fetcher: GuideFetcher = GuideFetcher(), states: GuideSourceStateStore = .shared,
         now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.fetcher = fetcher
        self.states = states
        self.now = now
    }

    func refresh(sourceID: UUID, url: String, knownChannelIDs: Set<String>, force: Bool) async throws -> Outcome {
        let state = states.state(for: sourceID)
        // A cleared store (storage cleanup, reinstall) must not trust "unchanged" for a guide that is gone.
        var probe = FetchDescriptor<EPGListing>()
        probe.fetchLimit = 1
        probe.propertiesToFetch = [\.id]
        let hasGuide = !((try? ModelContext(container).fetch(probe)) ?? []).isEmpty
        // Channels added since the last import may have programmes in a file the server calls unchanged: ask only
        // for the same channels.
        let channelsKey = GuideFingerprint.ofSet(knownChannelIDs)
        let conditional = !force && hasGuide && state.mayAskUnchanged(channelsKey: channelsKey)
        let answer: GuideFetcher.Result
        do {
            answer = try await fetcher.fetch(urlString: url, etag: conditional ? state.etag : nil,
                                             lastModified: conditional ? state.lastModified : nil)
        } catch {
            let reason = Self.reason(error)
            states.update(sourceID) { $0.recordFailure(reason, at: now()) }
            throw error
        }
        switch answer {
        case .unchanged:
            states.update(sourceID) { $0.recordUnchanged(at: now()) }
            return Outcome(claimedChannelIDs: state.channelIDs.intersection(knownChannelIDs), summary: "unchanged")
        case let .file(file, etag, lastModified, serverBuild, isTemporary):
            defer { if isTemporary { try? FileManager.default.removeItem(at: file) } }
            // the same file for the same channels: nothing to import (servers without ETag or Last-Modified)
            let fileHash = M3UClient.sha256Hex(ofFileAt: file)
            if hasGuide, state.isSameFile(hash: fileHash, channelsKey: channelsKey) {
                states.update(sourceID) {
                    $0.recordSameFile(etag: etag, lastModified: lastModified, serverBuild: serverBuild, at: now())
                }
                return Outcome(claimedChannelIDs: state.channelIDs.intersection(knownChannelIDs), summary: "same file")
            }
            let started = Date()
            let applier = GuideListingApplier(container: container)
            let index = index ?? GuideStoredIndex(rows: applier.loadStored())
            self.index = index
            // a stale stored guide (a phone not opened for a day, a first import): what is on now goes in first
            let mine = state.channelIDs.intersection(knownChannelIDs)
            let at = now()
            let stale = GuideDiffPlanner.wantsNowFirst(stored: index.rows,
                                                       channels: mine.isEmpty ? knownChannelIDs : mine, now: at)
            let nowFirst = stale ? DateInterval(start: at, duration: GuideDiffPlanner.nowFirstSpan) : nil
            let result = applier.apply(fileURL: file, claimableChannels: knownChannelIDs, index: index, now: at,
                                       allChannels: allChannelIDs, nowFirst: nowFirst, onNowReady: onNowReady)
            if Task.isCancelled { throw CancellationError() }
            guard result.completed else {
                states.update(sourceID) { $0.recordFailure("guide file incomplete", at: now()) }
                throw Failure.incompleteFile
            }
            states.update(sourceID) {
                $0.recordImported(etag: etag, lastModified: lastModified, serverBuild: serverBuild,
                                  channelIDs: result.claimedChannels, at: now(), fileHash: fileHash,
                                  channelsKey: channelsKey)
            }
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            return Outcome(claimedChannelIDs: result.claimedChannels,
                           summary: "+\(result.inserted) ~\(result.updated) -\(result.deleted) in \(seconds) s"
                               + (stale ? " (now first)" : ""))
        }
    }

    /// A source with nothing to download this time (all its channels are guided by an earlier source, or no channel
    /// has a guide yet) still counts as checked, so it never keeps the app "due".
    func recordSkipped(sourceID: UUID) {
        states.update(sourceID) { $0.recordUnchanged(at: now()) }
    }

    /// Credential-free reason (never a URL), like Lume's own guide logging.
    static func reason(_ error: Error) -> String {
        if let m3u = error as? M3UError { return m3u.logDescription }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
