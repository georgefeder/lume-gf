import Foundation
import OSLog
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
        let asked = Date()
        do {
            answer = try await fetcher.fetch(urlString: url, etag: conditional ? state.etag : nil,
                                             lastModified: conditional ? state.lastModified : nil)
        } catch {
            let reason = Self.reason(error)
            states.update(sourceID) { $0.recordFailure(reason, at: now()) }
            let text = "Guide: download stopped after \(Self.seconds(since: asked)) s (\(reason))"
            Logger.database.info("\(text, privacy: .public)")
            throw error
        }
        let fetched = Self.seconds(since: asked)
        Logger.database.info("Guide: \(Self.describe(answer), privacy: .public) in \(fetched, privacy: .public) s")
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
            let index = index ?? Self.readStored(applier, now: now())
            self.index = index
            // a stale stored guide (a phone not opened for a day, a first import): what is on now goes in first
            let mine = state.channelIDs.intersection(knownChannelIDs)
            let at = now()
            let stale = GuideDiffPlanner.wantsNowFirst(stored: index.rows,
                                                       channels: mine.isEmpty ? knownChannelIDs : mine, now: at)
            let nowFirst = stale ? DateInterval(start: at, duration: GuideDiffPlanner.nowFirstSpan) : nil
            let nowReady = onNowReady
            let logged: () -> Void = {
                let took = Self.seconds(since: started)
                Logger.database.info("Guide: what is on now is in after \(took, privacy: .public) s")
                nowReady()
            }
            let result = applier.apply(fileURL: file, claimableChannels: knownChannelIDs, index: index, now: at,
                                       allChannels: allChannelIDs, nowFirst: nowFirst, onNowReady: logged)
            if Task.isCancelled || !result.completed {
                let text = "Guide: import stopped after \(Self.seconds(since: started)) s, \(result.inserted) in so far"
                Logger.database.info("\(text, privacy: .public)")
            }
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
            let took = Self.seconds(since: started)
            return Outcome(claimedChannelIDs: result.claimedChannels,
                           summary: "+\(result.inserted) ~\(result.updated) -\(result.deleted) in \(took) s"
                               + (stale ? " (now first)" : ""))
        }
    }

    /// The stored guide, read once per run, after the programmes long over have gone
    /// (`GuideListingApplier.deleteEnded`). Logged with its size: Lume's diagnostic report shows where the time goes.
    private static func readStored(_ applier: GuideListingApplier, now: Date) -> GuideStoredIndex {
        let started = Date()
        let removed = applier.deleteEnded(before: now.addingTimeInterval(-GuideListingApplier.pruneAfter))
        let index = GuideStoredIndex(rows: applier.loadStored())
        let took = seconds(since: started)
        let text = "Guide: \(removed) long-over programmes removed, \(index.rows.count) read in \(took) s"
        Logger.database.info("\(text, privacy: .public)")
        return index
    }

    private static func describe(_ answer: GuideFetcher.Result) -> String {
        switch answer {
        case .unchanged: return "unchanged"
        case let .file(file, _, _, _, _):
            let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return "new guide file, \(bytes / 1_000_000) MB"
        }
    }

    private static func seconds(since start: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(start))
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
