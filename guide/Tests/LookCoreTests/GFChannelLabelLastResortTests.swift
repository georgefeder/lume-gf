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

    @Test func `more words than lines stay as written`() {
        let fit = GFChannelLabel.lastResortLines("SKY SPORTS MAIN EVENT", lineLimit: 2)
        #expect(fit.text == "SKY SPORTS MAIN EVENT")
        #expect(fit.lineLimit == 2)
    }

    @Test func `spaces around a word and an empty name`() {
        #expect(GFChannelLabel.lastResortLines("  CNN  ", lineLimit: 2).text == "CNN")
        #expect(GFChannelLabel.lastResortLines("  CNN  ", lineLimit: 2).lineLimit == 1)
        #expect(GFChannelLabel.lastResortLines("", lineLimit: 2).text == "")
    }
}
