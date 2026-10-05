import Foundation
@testable import LookCore
import Testing

/// The narrow column's last resort, once no text size fits every word on a line (the iPhone guide's channel column).
struct GFChannelLabelLastResortTests {
    @Test func `a single word stays on one line, to shrink rather than break`() {
        // Georgs on build 16: "BLOOMBER / G" in the iPhone guide
        let fit = GFChannelLabel.lastResortLines("BLOOMBERG", lineLimit: 2)
        #expect(fit.text == "BLOOMBERG")
        #expect(fit.lineLimit == 1)
    }

    @Test func `words that fit the lines get one line each`() {
        let fit = GFChannelLabel.lastResortLines("NEWS NATION", lineLimit: 2)
        #expect(fit.text == "NEWS\nNATION")
        #expect(fit.lineLimit == 2)
    }

    @Test func `more words than lines are split where the lines come out most even`() {
        // Georgs before build 23: "Sky / Sports…" in the iPhone guide
        let fit = GFChannelLabel.lastResortLines("Sky Sports Main Event", lineLimit: 2)
        #expect(fit.text == "Sky Sports\nMain Event")
        #expect(fit.lineLimit == 2)
        #expect(GFChannelLabel.lastResortLines("Sky Sports Premier League", lineLimit: 2).text
            == "Sky Sports\nPremier League")
        #expect(GFChannelLabel.lastResortLines("A B C D E", lineLimit: 3).text == "A B\nC D\nE")
    }

    @Test func `the column tries fewer lines first, then the longest first line`() {
        #expect(GFChannelLabel.lineSplits("BBC One", lineLimit: 2) == [["BBC One"], ["BBC", "One"]])
        #expect(GFChannelLabel.lineSplits("Sky Sports Main Event", lineLimit: 2) == [
            ["Sky Sports Main Event"], ["Sky Sports Main", "Event"], ["Sky Sports", "Main Event"],
            ["Sky", "Sports Main Event"]
        ])
        #expect(GFChannelLabel.lineSplits("Sky Sports Main Event", lineLimit: 1) == [["Sky Sports Main Event"]])
        #expect(GFChannelLabel.lineSplits("A B C D", lineLimit: 3).count == 1 + 3 + 3)
        #expect(GFChannelLabel.lineSplits("A B C D", lineLimit: 3)[4] == ["A B", "C", "D"])
    }

    @Test func `a long name gives at most 24 ways, and an empty one a single empty line`() {
        let many = (1 ... 30).map(String.init).joined(separator: " ")
        #expect(GFChannelLabel.lineSplits(many, lineLimit: 3).count == 24)
        #expect(GFChannelLabel.lineSplits("  ", lineLimit: 2) == [[""]])
    }

    @Test func `spaces around a word and an empty name`() {
        #expect(GFChannelLabel.lastResortLines("  CNN  ", lineLimit: 2).text == "CNN")
        #expect(GFChannelLabel.lastResortLines("  CNN  ", lineLimit: 2).lineLimit == 1)
        #expect(GFChannelLabel.lastResortLines("", lineLimit: 2).text == "")
    }
}
