import Foundation
@testable import GuideCore
import Testing

struct GuideFingerprintTests {
    let end = Date(timeIntervalSince1970: 1_790_000_000)

    func fp(title: String = "News", subtitle: String? = "Late", category: String? = "News, Sport",
            description: String = "d", end: Date? = nil) -> UInt64 {
        GuideFingerprint.of(end: end ?? self.end, title: title, subtitle: subtitle, category: category,
                            description: description)
    }

    @Test func `same programme gives the same fingerprint`() {
        #expect(fp() == fp())
    }

    @Test func `pinned value never changes between launches or devices`() {
        #expect(fp() == 0x8F5B_2E2E_845F_AF1D)
        #expect(fp(subtitle: nil, category: nil, description: "") == 0x8719_506B_265F_5A94)
    }

    @Test func `each field changes the fingerprint`() {
        let base = fp()
        #expect(fp(end: end.addingTimeInterval(60)) != base)
        #expect(fp(title: "Newz") != base)
        #expect(fp(subtitle: "Early") != base)
        #expect(fp(category: "News") != base)
        #expect(fp(description: "e") != base)
    }

    @Test func `field boundaries matter`() {
        #expect(fp(title: "ab", description: "c") != fp(title: "a", description: "bc"))
    }

    @Test func `missing sub-title differs from an empty one`() {
        #expect(fp(subtitle: nil) != fp(subtitle: ""))
    }

    @Test func `categories are joined the way Lume stores them`() {
        #expect(GuideFingerprint.category(["News", "Sport"]) == "News, Sport")
        #expect(GuideFingerprint.category([]) == nil)
    }

    @Test func `a channel set has one fingerprint whatever its order, and another set another`() {
        #expect(GuideFingerprint.ofSet(["a", "b"]) == GuideFingerprint.ofSet(["b", "a"]))
        #expect(GuideFingerprint.ofSet(["a", "b"]) != GuideFingerprint.ofSet(["ab"]))
        #expect(GuideFingerprint.ofSet(["a"]) != GuideFingerprint.ofSet(["a", "b"]))
    }
}
