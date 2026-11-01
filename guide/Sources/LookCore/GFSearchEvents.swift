import Foundation

/// Which programmes search finds are one broadcast event (Georgs, 1 Nov: searching "celtic", Falkirk v Celtic was on
/// five channels under four titles, "Live SPFL: Falkirk v Celtic", "SPFL: Falkirk vs Celtic", "Liga Escocesa
/// 2026-27 - Falkirk x Celtic"): airings at overlapping times whose titles share two distinctive words (or are made of
/// the same one). Top Results shows an event once, and an event on many channels at once counts for more.
nonisolated enum GFSearchEvents {
    struct Airing: Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
    }

    /// A title's distinctive words: without little words, time words ("live"), picture quality and numbers.
    static func words(_ title: String) -> Set<String> {
        Set(GFSearchText.words(title).filter { word in
            !GFSearchQuery.littleWords.contains(word) && GFSearchQuery.timeWords[word] == nil
                && !GFSearchText.noiseWords.contains(word) && !word.allSatisfy(\.isNumber)
        })
    }

    /// For each airing, the number of its event (the first airing's index in that event).
    static func events(_ airings: [Airing]) -> [Int] {
        var parent = Array(airings.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        let words = airings.map { Self.words($0.title) }
        for lhs in airings.indices {
            for rhs in airings.indices where rhs > lhs {
                guard airings[lhs].start < airings[rhs].end, airings[rhs].start < airings[lhs].end else { continue }
                let shared = words[lhs].intersection(words[rhs]).count
                let same = !words[lhs].isEmpty && words[lhs] == words[rhs]
                guard shared >= 2 || same else { continue }
                let (left, right) = (root(lhs), root(rhs))
                if left != right { parent[max(left, right)] = min(left, right) }
            }
        }
        return airings.indices.map(root)
    }

    /// How much more an event on `channels` channels at once counts: four per cent a channel, up to six.
    static func popularity(channels: Int) -> Double {
        1 + 0.04 * Double(min(max(channels - 1, 0), 5))
    }

    /// How much more a channel counts for its picture: 4K and UHD most, then FHD, then HD (the best of a match's
    /// channels leads; Georgs, 1 Nov: the Apple TV led with ESPN 2's HD where Sky Sports Football is 4K).
    static func quality(channelName: String) -> Double {
        switch GFChannelLabel.parse(channelName).quality?.uppercased() {
        case "4K", "UHD": 1.06
        case "FHD": 1.04
        case "HD": 1.02
        default: 1
        }
    }
}
