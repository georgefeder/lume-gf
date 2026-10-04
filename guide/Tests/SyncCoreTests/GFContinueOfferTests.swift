import Foundation
@testable import SyncCore
import Testing

struct GFContinueOfferTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(device: String = "phone-1", kind: GFLastPlayedNote.Kind = .channel, minutesAgo: Double = 3,
                      position: Double = 0) -> GFLastPlayedNote {
        GFLastPlayedNote(deviceID: device, deviceKind: "iPhone", kind: kind, contentId: "p-live-1", title: "BBC One",
                         artworkURL: nil, position: position, duration: kind == .channel ? 0 : 7200, playing: false,
                         updatedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func offer(_ n: GFLastPlayedNote?, me: String = "tv-1", dismissed: Set<String> = [], inCatalog: Bool = true,
                       playingHere: Bool = false) -> GFLastPlayedNote? {
        GFContinueOffer.offer(n, myDeviceID: me, now: now, dismissed: dismissed, inCatalog: inCatalog,
                              playingHere: playingHere)
    }

    @Test func `something watched a few minutes ago on another device is offered`() {
        #expect(offer(note()) != nil)
    }

    @Test func `not what this device played itself`() {
        #expect(offer(note(device: "tv-1")) == nil)
    }

    @Test func `not after three hours`() {
        #expect(offer(note(minutesAgo: 179)) != nil)
        #expect(offer(note(minutesAgo: 181)) == nil)
    }

    @Test func `not once waved away here`() {
        let n = note()
        #expect(offer(n, dismissed: [GFContinueOffer.dismissalKey(n)]) == nil)
    }

    @Test func `not when this device lacks it, or something plays here`() {
        #expect(offer(note(), inCatalog: false) == nil)
        #expect(offer(note(), playingHere: true) == nil)
        #expect(offer(nil) == nil)
    }

    @Test func `the subtitle says where from and how long ago, a film also where it stopped`() {
        #expect(GFContinueOffer.subtitle(note(), now: now) == "from iPhone · 3 min ago")
        #expect(GFContinueOffer.subtitle(note(kind: .film, minutesAgo: 20, position: 4323), now: now)
            == "1:12:03 · from iPhone · 20 min ago")
        #expect(GFContinueOffer.subtitle(note(minutesAgo: 0.2), now: now) == "from iPhone · just now")
        #expect(GFContinueOffer.subtitle(note(minutesAgo: 125), now: now) == "from iPhone · 2 h ago")
    }
}
