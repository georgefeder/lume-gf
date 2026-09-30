import Foundation

/// Event start times in our server's names. events.py writes Riga time (Europe/Riga): "20:30" for today there,
/// "Sun 17:55" for another day. Lume GF resolves the moment and shows it in the device's own time zone.
nonisolated enum GFChannelLabelTime {
    static let serverTimeZone = TimeZone(identifier: "Europe/Riga")!

    private static let weekdays = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]

    /// "hh:mm" or "Ddd hh:mm" (English day abbreviation; weekday 1 = Sunday, as `Calendar`); nil for anything else.
    static func clock(_ text: String) -> (weekday: Int?, hour: Int, minute: Int)? {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: false)
        let time: Substring
        var weekday: Int?
        switch pieces.count {
        case 1:
            time = pieces[0]
        case 2:
            guard let day = weekdays[String(pieces[0])] else { return nil }
            weekday = day
            time = pieces[1]
        default:
            return nil
        }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1 ... 2).contains(parts[0].count), parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0 ..< 24).contains(hour), (0 ..< 60).contains(minute)
        else { return nil }
        return (weekday, hour, minute)
    }

    /// The moment a server time means. "hh:mm": its nearest occurrence (at most 12 hours away). "Ddd hh:mm": the
    /// first such day from yesterday on (up to a week ahead) whose time is not more than 12 hours ago.
    static func resolve(_ text: String, now: Date, serverTimeZone: TimeZone = serverTimeZone) -> Date? {
        guard let clock = clock(text) else { return nil }
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = serverTimeZone
            return calendar
        }()
        let today = calendar.startOfDay(for: now)
        func occurrence(dayOffset: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            if let weekday = clock.weekday, calendar.component(.weekday, from: day) != weekday { return nil }
            return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
        }
        if clock.weekday != nil {
            let earliest = now.addingTimeInterval(-12 * 3600)
            for offset in -1 ... 7 {
                if let start = occurrence(dayOffset: offset), start >= earliest { return start }
            }
            return nil
        }
        return (-1 ... 1).compactMap { occurrence(dayOffset: $0) }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    /// "15:55" when the start is today in `zone`, otherwise "Sun 15:55"; the locale decides 12- or 24-hour style.
    static func badgeText(start: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        let time = start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                    calendar: calendar, timeZone: zone))
        guard !calendar.isDate(start, inSameDayAs: now) else { return time }
        let day = start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
            .weekday(.abbreviated))
        return "\(day) \(time)"
    }

    /// For a badge with little room (the iPhone guide's channel column): today's time, or only the weekday.
    static func compactBadgeText(start: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        guard !calendar.isDate(start, inSameDayAs: now) else {
            return badgeText(start: start, now: now, zone: zone, locale: locale)
        }
        return start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
            .weekday(.abbreviated))
    }
}
