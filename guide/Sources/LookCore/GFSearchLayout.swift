import Foundation

/// How search lays out what it found (Georgs, 29 Oct: "All" was films first whatever he typed). In "All", the best
/// few of any kind lead as Top Results, then one section per kind, the kind with the best match first: "finland"
/// opens on the Finland category, "dune" on the film, "warriors" on the game in the guide. Favourite and recently
/// watched channels, and programmes on now or soon (or in the time asked for: "tonight"), count a little more.
nonisolated enum GFSearchLayout {
    struct Row<ID: Hashable & Sendable>: Equatable, Sendable {
        let kind: GFSearchIndex.Kind
        let id: ID
        let score: Double
    }

    struct Section<ID: Hashable & Sendable>: Equatable, Sendable {
        /// Nil for Top Results.
        let kind: GFSearchIndex.Kind?
        let ids: [ID]
    }

    static let topCount = 3

    /// `rows` as sections. Top Results only when `allKinds` (the "All" filter) and rows of two kinds or more came;
    /// what is in it is not repeated below.
    static func sections<ID>(_ rows: [Row<ID>], allKinds: Bool) -> [Section<ID>] {
        let best = rows.enumerated().sorted { lhs, rhs in
            lhs.element.score != rhs.element.score ? lhs.element.score > rhs.element.score : lhs.offset < rhs.offset
        }.map(\.element)
        var rest = best
        var result: [Section<ID>] = []
        if allKinds, Set(best.map(\.kind)).count >= 2, best.count > topCount + 1 {
            result.append(Section(kind: nil, ids: best.prefix(topCount).map(\.id)))
            rest = Array(best.dropFirst(topCount))
        }
        var order: [GFSearchIndex.Kind] = []
        var byKind: [GFSearchIndex.Kind: [ID]] = [:]
        for row in rest {
            if byKind[row.kind] == nil { order.append(row.kind) }
            byKind[row.kind, default: []].append(row.id)
        }
        result += order.map { Section(kind: $0, ids: byKind[$0] ?? []) }
        return result
    }

    /// A channel's score, a little more when it is a favourite or was watched in the last week.
    static func channelScore(_ score: Double, isFavorite: Bool, lastWatched: Date?, now: Date) -> Double {
        var score = score
        if isFavorite { score *= 1.06 }
        if let lastWatched, now.timeIntervalSince(lastWatched) < 7 * 86400 { score *= 1.03 }
        return score
    }

    /// A programme's score at one airing: more on now or within three hours, and in the time asked for (less outside
    /// it).
    static func programmeScore(_ score: Double, start: Date, end: Date, now: Date, time: GFSearchQuery.Time?,
                               calendar: Calendar) -> Double {
        var score = score
        if start <= now, now < end {
            score *= 1.06
        } else if start.timeIntervalSince(now) < 3 * 3600 {
            score *= 1.03
        }
        if let time {
            score *= time.contains(start: start, end: end, now: now, calendar: calendar) ? 1.2 : 0.8
        }
        return score
    }

    /// The most airings of one programme listed: the rest of the week's repeats would push other programmes out.
    static let airingsPerProgramme = 4
}
