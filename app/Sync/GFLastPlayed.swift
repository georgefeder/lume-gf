import CloudKit
import Foundation
import OSLog
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

protocol GFLastPlayedStoring: Sendable {
    func save(_ note: GFLastPlayedNote) async
    func load() async -> GFLastPlayedNote?
}

/// The note as one record (`GFLastPlayed` / `last-played`) in the private database's default zone; a save overwrites
/// whatever is there (the most recent player wins).
struct GFLastPlayedCloudStore: GFLastPlayedStoring {
    private var database: CKDatabase {
        CKContainer(identifier: GFCloudConfig.containerID).privateCloudDatabase
    }

    private var recordID: CKRecord.ID {
        CKRecord.ID(recordName: GFCloudConfig.lastPlayedRecordName)
    }

    func save(_ note: GFLastPlayedNote) async {
        let record = CKRecord(recordType: GFCloudConfig.lastPlayedRecordType, recordID: recordID)
        record["deviceID"] = note.deviceID
        record["deviceKind"] = note.deviceKind
        record["kind"] = note.kind.rawValue
        record["contentId"] = note.contentId
        record["title"] = note.title
        record["artworkURL"] = note.artworkURL
        record["position"] = note.position
        record["duration"] = note.duration
        record["playing"] = note.playing ? 1 : 0
        record["updatedAt"] = note.updatedAt
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            Logger.sync.error("Lume GF last played: save failed: \(error)")
        }
    }

    func load() async -> GFLastPlayedNote? {
        guard let record = try? await database.record(for: recordID),
              let kind = (record["kind"] as? String).flatMap(GFLastPlayedNote.Kind.init(rawValue:)),
              let contentId = record["contentId"] as? String, let updatedAt = record["updatedAt"] as? Date
        else { return nil }
        return GFLastPlayedNote(
            deviceID: record["deviceID"] as? String ?? "", deviceKind: record["deviceKind"] as? String ?? "",
            kind: kind, contentId: contentId, title: record["title"] as? String ?? "",
            artworkURL: record["artworkURL"] as? String, position: record["position"] as? Double ?? 0,
            duration: record["duration"] as? Double ?? 0, playing: (record["playing"] as? Int ?? 0) == 1,
            updatedAt: updatedAt
        )
    }
}

enum GFLastPlayed {
    /// iCloud's store in signed builds; nil in tests, previews and the demo.
    static let store: GFLastPlayedStoring? = GFCloud.isAvailable ? GFLastPlayedCloudStore() : nil

    /// One random id per install (this device only; never synced as a setting).
    static let deviceID: String = {
        let key = "gf.lastPlayed.deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    static var deviceKind: String {
        #if os(tvOS)
            "Apple TV"
        #elseif os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
            "Mac"
        #endif
    }

    /// nil for a recording on Lume's recording server (Lume 2.4): not in any catalogue, nothing to continue.
    static func note(for media: PlayableMedia, position: Double, duration: Double, playing: Bool,
                     now: Date = Date()) -> GFLastPlayedNote? {
        let ref: (kind: GFLastPlayedNote.Kind, id: String)? = switch media.contentRef {
        case let .live(id): (.channel, id)
        case let .movie(id): (.film, id)
        case let .episode(id): (.episode, id)
        case .recording: nil
        }
        guard let ref else { return nil }
        return GFLastPlayedNote(deviceID: deviceID, deviceKind: deviceKind, kind: ref.kind, contentId: ref.id,
                                title: media.title, artworkURL: media.posterURL?.absoluteString,
                                position: media.isLive ? 0 : position, duration: media.isLive ? 0 : duration,
                                playing: playing, updatedAt: now)
    }
}

extension View {
    /// The player tells iCloud what plays: on start and channel change, every minute for films and episodes, and when
    /// it closes.
    func gfReportsLastPlayed(media: PlayableMedia, position: @escaping () -> Double,
                             duration: @escaping () -> Double) -> some View {
        task(id: media.contentRef) {
            guard let store = GFLastPlayed.store,
                  let first = GFLastPlayed.note(for: media, position: position(), duration: duration(), playing: true)
            else { return }
            await store.save(first)
            while !media.isLive, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled,
                      let note = GFLastPlayed.note(for: media, position: position(), duration: duration(),
                                                   playing: true) else { break }
                await store.save(note)
            }
        }
        .onDisappear {
            guard let store = GFLastPlayed.store,
                  let note = GFLastPlayed.note(for: media, position: position(), duration: duration(), playing: false)
            else { return }
            Task { await store.save(note) }
        }
    }
}
