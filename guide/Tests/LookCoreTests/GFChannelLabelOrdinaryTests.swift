import Foundation
@testable import LookCore
import Testing

/// Ordinary channels: our server appends the measured quality ("BBC One FHD", organise.py).
struct GFChannelLabelOrdinaryTests {
    @Test(arguments: [
        ("BBC One FHD", "BBC One", "FHD"),
        ("ITV1 HD", "ITV1", "HD"),
        ("Sky Sports F1 4K", "Sky Sports F1", "4K"),
        ("Nature Channel UHD", "Nature Channel", "UHD"),
        ("Old Feed SD", "Old Feed", "SD"),
        ("Match Feed RAW", "Match Feed", "RAW"),
        ("AR| MBC VARIETY PLUS FHD", "AR| MBC VARIETY PLUS", "FHD")
    ])
    func `a trailing quality word becomes the badge`(raw: String, title: String, quality: String) {
        #expect(GFChannelLabel.parse(raw) == GFChannelLabel(title: title, secondLine: nil, quality: quality, status: .none))
    }

    @Test(arguments: ["Channel 4", "BBC ONE HD+", "Sky Sports hd", "FHD", "HD FHD Channel", "", "TV3 LIVE"])
    func `anything else is shown as written`(raw: String) {
        #expect(GFChannelLabel.parse(raw) == .unchanged(raw))
    }

    @Test func `spaces around the name are tidied`() {
        #expect(GFChannelLabel.parse("  BBC One FHD ").title == "BBC One")
    }
}
