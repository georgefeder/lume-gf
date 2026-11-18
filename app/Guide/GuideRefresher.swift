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
    /// This refresh's timings, sent to the server when it ends however it ends (GFGuideReporter).
    private var timing: GFGuideTiming?
    /// False during a short background wake (the server's push, a background refresh: about 25 s), which a whole import
    /// never fits (15 Nov 2026: after the playlist's channels changed, every wake for hours downloaded the whole guide
    /// and was cut short). Such a wake then takes the server's hourly changes even when the channels changed; the
    /// whole import their new channels need waits for the app being open or the overnight import. A device too far
    /// behind for a change file takes the whole guide in such a wake anyway, as far as it gets (18 Nov). GuideScheduler
    /// counts the short wakes running (overlapping ones too: a push and a background refresh came together).
    nonisolated(unsafe) static var shortWakes = 0
    static var wholeImportAllowed: Bool {
        shortWakes == 0
    }

    init(container: ModelContainer, fetcher: GuideFetcher = GuideFetcher(), states: GuideSourceStateStore = .shared,
         now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.fetcher = fetcher
        self.states = states
        self.now = now
    }

    func refresh(sourceID: UUID, url: String, knownChannelIDs: Set<String>, force: Bool) async throws -> Outcome {
        // one report per refresh, from the outermost call (the full-guide fallback calls this again)
        let reports = timing == nil
        if reports { timing = GFGuideTiming(kind: Self.wholeImportAllowed ? "app" : "wake") }
        defer {
            if reports, let timing {
                GFGuideReporter.send(timing, guideURL: url)
                self.timing = nil
            }
        }
        let state = states.state(for: sourceID)
        // A cleared store (storage cleanup, reinstall) must not trust "unchanged" for a guide that is gone.
        var probe = FetchDescriptor<EPGListing>()
        probe.fetchLimit = 1
        probe.propertiesToFetch = [\.id]
        let hasGuide = !((try? ModelContext(container).fetch(probe)) ?? []).isEmpty
        // Channels added since the last import may have programmes in a file the server calls unchanged: ask only
        // for the same channels.
        let channelsKey = GuideFingerprint.ofSet(knownChannelIDs)
        let sameChannels = state.mayAskUnchanged(channelsKey: channelsKey)
        let whole = Self.wholeImportAllowed // decided once: a wake's end must not change it halfway
        let conditional = !force && hasGuide && (sameChannels || !whole)
        // the server's change file since the build this device has (GuideDelta), when it still keeps one; else it
        // answers with the full guide. Asked by date alone: a change file's ETag is not the full guide's, so an ETag
        // kept from one would make the server send the full guide again instead of "unchanged".
        let since = conditional ? state.serverBuild.map { Int($0.timeIntervalSince1970) } : nil
        let answer: GuideFetcher.Result
        let asked = Date()
        do {
            answer = try await fetcher.fetch(urlString: since.map { GuideDelta.url(url, since: $0) } ?? url,
                                             etag: conditional && since == nil ? state.etag : nil,
                                             lastModified: conditional ? state.lastModified : nil)
        } catch {
            // iOS ending a background wake mid-download is no failure of the guide (it showed as "last check failed
            // (NSURLErrorDomain -999)")
            timing?.download = GFGuideTiming.ms(since: asked)
            if Task.isCancelled {
                timing?.why = "stopped"
                states.update(sourceID) { $0.lastAttempt = now() } // the usual 15 minutes before the next try
                throw CancellationError()
            }
            timing?.why = "error"
            let reason = Self.reason(error)
            states.update(sourceID) { $0.recordFailure(reason, at: now()) }
            let text = "Guide: download stopped after \(Self.seconds(since: asked)) s (\(reason))"
            Logger.database.info("\(text, privacy: .public)")
            throw error
        }
        let fetched = Self.seconds(since: asked)
        timing?.download = GFGuideTiming.ms(since: asked)
        Logger.database.info("Guide: \(Self.describe(answer), privacy: .public) in \(fetched, privacy: .public) s")
        switch answer {
        case .unchanged:
            timing?.path = "unchanged"
            timing?.finished = true
            states.update(sourceID) { $0.recordUnchanged(at: now()) }
            return Outcome(claimedChannelIDs: state.channelIDs.intersection(knownChannelIDs), summary: "unchanged")
        case let .file(file, etag, lastModified, serverBuild, isTemporary):
            defer { if isTemporary { try? FileManager.default.removeItem(at: file) } }
            if let delta = GuideDelta.header(ofFileAt: file) {
                guard let since, delta.since == since else {
                    // a change file for another build than this device's: the full guide instead, asked once (a
                    // change file to a plain request too is the server's fault, not something to ask again)
                    Logger.database.info("Guide: change file for another build, asking for the full guide")
                    guard since != nil else {
                        states.update(sourceID) { $0.recordFailure("change file instead of the guide", at: now()) }
                        throw Failure.incompleteFile
                    }
                    return try await refresh(sourceID: sourceID, url: url, knownChannelIDs: knownChannelIDs,
                                             force: true)
                }
                // channels changed since the last whole import: their key stays the old one, so the whole import they
                // need still comes when there is time
                return try applyChanges(delta, file: file, sourceID: sourceID, state: state,
                                        knownChannelIDs: knownChannelIDs,
                                        channelsKey: sameChannels ? channelsKey : state.channelsKey, etag: etag,
                                        lastModified: lastModified, serverBuild: serverBuild,
                                        wholeImportOwed: !sameChannels, whole: whole)
            }
            // the whole guide (the server keeps no change file for a device more than 6 hours behind) goes in even in a
            // short wake, as far as the wake lasts: put off, it never came (18 Nov 2026: the iPhone 12 hours behind
            // after a night of wakes). What is on now goes in first (a stale guide), and the rest is saved every
            // batch (GuideListingApplier.wakeSaveThreshold), so the next wake goes on from there: what is stored and
            // the same is not written again.
            // the same file for the same channels: nothing to import (servers without ETag or Last-Modified)
            let fileHash = M3UClient.sha256Hex(ofFileAt: file)
            if hasGuide, state.isSameFile(hash: fileHash, channelsKey: channelsKey) {
                timing?.path = "same"
                timing?.finished = true
                states.update(sourceID) {
                    $0.recordSameFile(etag: etag, lastModified: lastModified, serverBuild: serverBuild, at: now())
                }
                return Outcome(claimedChannelIDs: state.channelIDs.intersection(knownChannelIDs), summary: "same file")
            }
            timing?.path = "whole"
            let started = Date()
            let applier = GuideListingApplier(container: container)
            let at = now()
            let index: GuideStoredIndex
            if let read = self.index {
                index = read
            } else {
                index = readStored(applier, file: file, state: state, now: at)
                timing?.readStored = GFGuideTiming.ms(since: started)
                timing?.storedRows = index.rows.count
                if Task.isCancelled { // a partly read store is no index
                    timing?.why = "stopped"
                    throw CancellationError()
                }
                self.index = index
            }
            let applying = Date()
            // a stale stored guide (a phone not opened for a day, a first import): what is on now goes in first
            let mine = state.channelIDs.intersection(knownChannelIDs)
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
                                       allChannels: allChannelIDs, nowFirst: nowFirst, onNowReady: logged,
                                       saveEvery: whole ? GuideListingApplier.saveThreshold
                                           : GuideListingApplier.wakeSaveThreshold)
            timing?.apply = GFGuideTiming.ms(since: applying)
            timing?.inserted = result.inserted
            timing?.updated = result.updated
            timing?.deleted = result.deleted
            timing?.finished = result.completed
            if !result.completed { timing?.why = Task.isCancelled ? "stopped" : "incomplete" }
            // a complete import counts even when a stop came at its very end: the next run must not do it again
            guard result.completed else {
                let why = Task.isCancelled ? "stopped" : "file not read to the end"
                let text = "Guide: import \(why) after \(Self.seconds(since: started)) s, \(result.inserted) in so far"
                Logger.database.info("\(text, privacy: .public)")
                if Task.isCancelled { throw CancellationError() }
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

    /// The server's change file (GuideDelta): only its programmes are written, the stored guide is not read.
    private func applyChanges(_ delta: GuideDelta.Header, file: URL, sourceID: UUID, state: GuideSourceState,
                              knownChannelIDs: Set<String>, channelsKey: UInt64?, etag: String?, lastModified: String?,
                              serverBuild: Date?, wholeImportOwed: Bool, whole: Bool) throws -> Outcome {
        let started = Date()
        let removed = delta.removed.compactMap { gone in
            XMLTVDate.parse(gone.start).map { GuideDiffPlanner.id(channelId: gone.channel, start: $0) }
        }
        timing?.path = "delta"
        let result = GuideListingApplier(container: container)
            .applyChanges(fileURL: file, claimableChannels: knownChannelIDs, removed: removed,
                          saveEvery: whole ? GuideListingApplier.saveThreshold : GuideListingApplier.wakeSaveThreshold)
        timing?.apply = GFGuideTiming.ms(since: started)
        timing?.inserted = result.inserted
        timing?.updated = result.updated
        timing?.deleted = result.deleted
        timing?.finished = result.completed
        if !result.completed { timing?.why = Task.isCancelled ? "stopped" : "incomplete" }
        index = nil // read before this run's changes: no longer the stored guide
        guard result.completed else {
            let why = Task.isCancelled ? "stopped" : "file not read to the end"
            let text = "Guide: changes \(why) after \(Self.seconds(since: started)) s, \(result.inserted) in so far"
            Logger.database.info("\(text, privacy: .public)")
            if Task.isCancelled { throw CancellationError() }
            states.update(sourceID) { $0.recordFailure("guide file incomplete", at: now()) }
            throw Failure.incompleteFile
        }
        let claimed = state.channelIDs.intersection(knownChannelIDs).union(result.claimedChannels)
        states.update(sourceID) {
            $0.recordImported(etag: etag, lastModified: lastModified, serverBuild: serverBuild, channelIDs: claimed,
                              at: now(), fileHash: nil, channelsKey: channelsKey)
            if wholeImportOwed { $0.wholeImportOwed = true }
        }
        // a change file never names the programmes that simply ended (a whole import dropped them): those over for
        // a day go here, so the stored guide does not grow by an hour's programmes every hour. The server's guide
        // reaches back about 17 hours (14 Nov 2026: the 18:27 build starts at 01:00), and a whole import itself
        // drops what ended 12 hours ago and is no longer in the file, so a day keeps at least as much as a whole
        // import would.
        let cleared = GuideListingApplier(container: container)
            .deleteEnded(before: now().addingTimeInterval(-GuideListingApplier.pruneAfter))
        let took = Self.seconds(since: started)
        return Outcome(claimedChannelIDs: claimed,
                       summary: "changes +\(result.inserted) ~\(result.updated) -\(result.deleted + cleared) in \(took) s")
    }

    /// A short wake got the whole guide: left for the app being open or the overnight import (`wholeImportDue`).

    /// The stored guide, read once per run and logged with its size (Lume's diagnostic report shows where the time
    /// goes). A source with no complete import for a day first clears the programmes long over: they ended before a
    /// day ago and before the new file's earliest programme, so nothing the file carries goes (its catch-up days stay).
    /// Another source's may go too; its next check then downloads and imports in full.
    private func readStored(_ applier: GuideListingApplier, file: URL, state: GuideSourceState,
                            now: Date) -> GuideStoredIndex {
        let started = Date()
        var removed = 0
        let behind = state.lastUpdate.map { now.timeIntervalSince($0) > GuideListingApplier.pruneAfter } ?? true
        if behind, let earliest = GuideListingApplier.earliestStart(inFileAt: file) {
            let dayAgo = now.addingTimeInterval(-GuideListingApplier.pruneAfter)
            removed = applier.deleteEnded(before: min(earliest, dayAgo))
            if removed > 0 { states.forgetFiles() }
        }
        let index = GuideStoredIndex(rows: applier.loadStored())
        let took = Self.seconds(since: started)
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
