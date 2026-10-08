import Foundation

/// A guide programme search found (Georgs, 8 Oct: searching "Shark Tank", when and where will it air?).
nonisolated struct GFGuideSearchHit: Equatable, Sendable {
    var listingID: String
    var channelId: String
    var title: String
    var subtitle: String?
    var detail: String
    var start: Date
    var end: Date

    func isLive(at now: Date) -> Bool {
        start <= now && now < end
    }
}

/// Which programmes search lists under "On TV", and how it words their time.
nonisolated enum GFGuideSearch {
    static let limit = 30

    /// Programmes matched by title, on channels this playlist has, that have not ended: on now first, then by start
    /// time; each listing once; at most `limit`.
    static func hits(_ listings: [GFGuideSearchHit], channels: Set<String>, now: Date,
                     limit: Int = limit) -> [GFGuideSearchHit] {
        var seen = Set<String>()
        let kept = listings.filter {
            $0.end > now && channels.contains($0.channelId) && seen.insert($0.listingID).inserted
        }
        let sorted = kept.sorted { lhs, rhs in
            let lhsLive = lhs.isLive(at: now), rhsLive = rhs.isLive(at: now)
            if lhsLive != rhsLive { return lhsLive }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.channelId < rhs.channelId
        }
        return Array(sorted.prefix(limit))
    }

    /// "Live now", "Today 21:00", "Tomorrow 09:30", "Sat 20:00" within the week, "18 Oct 20:00" after it.
    static func whenLabel(start: Date, end: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if start <= now, now < end { return "Live now" }
        let time = formatter("jmm", calendar: calendar, locale: locale).string(from: start)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case 0: return "Today \(time)"
        case 1: return "Tomorrow \(time)"
        case 2 ... 6: return "\(formatter("EEE", calendar: calendar, locale: locale).string(from: start)) \(time)"
        default: return "\(formatter("dMMM", calendar: calendar, locale: locale).string(from: start)) \(time)"
        }
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
