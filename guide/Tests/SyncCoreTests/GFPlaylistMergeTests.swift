import Foundation
@testable import SyncCore
import Testing

struct GFPlaylistMergeTests {
    private func identity(_ id: String, server: String = "http://tv.example:8080", user: String = "georgs",
                          type: String = "xtream", mac: String = "") -> GFPlaylistMerge.Identity {
        GFPlaylistMerge.Identity(id: UUID(uuidString: id)!, sourceType: type, server: server, username: user, mac: mac)
    }

    private let a = "00000000-0000-0000-0000-00000000000A"
    private let b = "00000000-0000-0000-0000-00000000000B"
    private let c = "00000000-0000-0000-0000-00000000000C"

    @Test func `server addresses compare without case, default port and trailing slash`() {
        let one = GFPlaylistMerge.sameSourceKey(identity(a, server: "HTTP://Server.example:80/"))
        let two = GFPlaylistMerge.sameSourceKey(identity(b, server: "http://server.example"))
        #expect(one == two)
        let tls = GFPlaylistMerge.sameSourceKey(identity(a, server: "https://server.example:443/"))
        #expect(tls == GFPlaylistMerge.sameSourceKey(identity(b, server: "https://server.example")))
        #expect(tls != one) // https and http are different sources
    }

    @Test func `another user or another type is another playlist`() {
        let base = GFPlaylistMerge.sameSourceKey(identity(a))
        #expect(GFPlaylistMerge.sameSourceKey(identity(b, user: "other")) != base)
        #expect(GFPlaylistMerge.sameSourceKey(identity(b, type: "m3u")) != base)
        #expect(GFPlaylistMerge.sameSourceKey(identity(b, server: "http://tv.example:8081")) != base)
    }

    @Test func `a portal without a username is told apart by its MAC address`() {
        let one = GFPlaylistMerge.sameSourceKey(identity(a, user: "", type: "stalker", mac: "00:1A:79:00:00:01"))
        let two = GFPlaylistMerge.sameSourceKey(identity(b, user: "", type: "stalker", mac: "00:1a:79:00:00:01"))
        let three = GFPlaylistMerge.sameSourceKey(identity(c, user: "", type: "stalker", mac: "00:1A:79:00:00:02"))
        #expect(one == two)
        #expect(one != three)
    }

    @Test func `the copy with the smallest id stays, whatever the order`() {
        let plans = [
            GFPlaylistMerge.plan([identity(c), identity(a), identity(b)]),
            GFPlaylistMerge.plan([identity(b), identity(c), identity(a)])
        ]
        for plan in plans {
            #expect(plan == [
                GFPlaylistMerge.Merge(keep: UUID(uuidString: a)!, drop: UUID(uuidString: b)!),
                GFPlaylistMerge.Merge(keep: UUID(uuidString: a)!, drop: UUID(uuidString: c)!)
            ])
        }
    }

    @Test func `different playlists are left alone`() {
        #expect(GFPlaylistMerge.plan([identity(a), identity(b, user: "other")]).isEmpty)
        #expect(GFPlaylistMerge.plan([identity(a)]).isEmpty)
        #expect(GFPlaylistMerge.plan([]).isEmpty)
    }

    @Test func `the same playlist seen twice (local and cloud) is one playlist`() {
        #expect(GFPlaylistMerge.plan([identity(a), identity(a)]).isEmpty)
    }

    @Test func `content ids move from the dropped copy to the kept one`() {
        let keep = UUID(uuidString: a)!, drop = UUID(uuidString: b)!
        #expect(GFPlaylistMerge.reprefixed("\(b)-live-42", from: drop, to: keep) == "\(a)-live-42")
        #expect(GFPlaylistMerge.reprefixed("\(b)-vod-7", from: drop, to: keep) == "\(a)-vod-7")
        #expect(GFPlaylistMerge.reprefixed("\(c)-live-42", from: drop, to: keep) == nil)
        #expect(GFPlaylistMerge.reprefixed(b, from: drop, to: keep) == nil) // the playlist id itself is no content id
    }

    @Test func `the kill switch and names are what the spec says`() {
        #expect(GFCloudConfig.enabled)
        #expect(GFCloudConfig.containerID == "iCloud.lv.georgefeder.lume")
        #expect(GFCloudConfig.lastPlayedRecordType == "GFLastPlayed")
        #expect(GFCloudConfig.lastPlayedRecordName == "last-played")
        #expect(GFCloudConfig.settingsPrefix == "gf.settings.")
    }
}
