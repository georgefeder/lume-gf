import Foundation

/// A show Georgs follows (4 Nov: "I could follow shows ... it would send me out a notification an hour before that it's
/// going to be on the TV in an hour"): a programme's title on one channel, Shark Tank on ABC. The channel keeps the
/// repeats other channels show out; any of its pictures counts (ABC HD, ABC 4K), the best one is offered.
nonisolated struct GFFollowedShow: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// As the guide showed it when followed.
    var title: String
    /// The channel's name without its picture quality ("ABC" for "ABC 4K").
    var channel: String
    var followedAt: Date

    var id: String {
        GFFollowedShows.key(title: title, channel: channel)
    }
}

/// Following shows: the list as stored, which guide listings are a followed show, their next airings, how the Coming
/// Up row says when, and the reminders (on the day, and an hour before), in the device's own time zone.
nonisolated enum GFFollowedShows {
    /// The list as JSON in the app's settings, synced to every device (GFSettingsCatalog).
    static let storageKey = "gf.follow.shows"
    /// The hour of the day's heads-up ("Tonight at 01:00 on ABC"), on the airing's TV day.
    static let headsUpHour = 10
    /// A TV day runs from five in the morning: a programme at one in the morning is the evening before's.
    static let tvDayStartHour = 5
    /// The most reminders handed to the system at once (iOS keeps 64 for an app).
    static let reminderLimit = 48

    // MARK: - The list

    static func decode(_ text: String?) -> [GFFollowedShow] {
        guard let data = text?.data(using: .utf8),
              let shows = try? JSONDecoder().decode([GFFollowedShow].self, from: data) else { return [] }
        return shows
    }

    static func encode(_ shows: [GFFollowedShow]) -> String {
        guard let data = try? JSONEncoder().encode(shows) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `shows` with the programme `title` on the channel `streamName` followed, or no longer followed if it was.
    static func toggled(_ shows: [GFFollowedShow], title: String, streamName: String, now: Date) -> [GFFollowedShow] {
        guard let channel = channel(ofStreamName: streamName) else { return shows }
        let key = key(title: title, channel: channel)
        if shows.contains(where: { $0.id == key }) { return shows.filter { $0.id != key } }
        return shows + [GFFollowedShow(title: title, channel: channel, followedAt: now)]
    }

    static func isFollowed(_ shows: [GFFollowedShow], title: String, streamName: String) -> Bool {
        guard let channel = channel(ofStreamName: streamName) else { return false }
        let key = key(title: title, channel: channel)
        return shows.contains { $0.id == key }
    }

    // MARK: - Matching

    /// The channel a show is followed on: the name without its picture quality ("ABC" for "ABC 4K"). Nil for an
    /// event slot ("🔴 LIVE 20:00 · Arsenal v Chelsea"), which never shows the same thing twice.
    static func channel(ofStreamName name: String) -> String? {
        let label = GFChannelLabel.parse(name)
        guard label.status == .none else { return nil }
        let title = label.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    static func key(title: String, channel: String) -> String {
        titleWords(title).joined(separator: " ") + "|" + GFSearchText.fold(channel)
    }

    /// A title's words as compared: folded, without picture quality, numbers and episode marks ("S17E03", "Ep4"), so
    /// "Shark Tank S17E03" is Shark Tank. A title of numbers alone keeps them ("24", "9-1-1").
    static func titleWords(_ title: String) -> [String] {
        let words = GFSearchText.words(title).filter { !GFSearchText.noiseWords.contains($0) && !isEpisodeMark($0) }
        let named = words.filter { !$0.allSatisfy(\.isNumber) }
        return named.isEmpty ? words : named
    }

    /// Whether a programme's title can be followed: it has words to find it by.
    static func canFollow(title: String) -> Bool {
        !titleWords(title).isEmpty
    }

    /// Words a guide adds to a show's title for one airing: "Shark Tank (New)", "Shark Tank - Season Finale",
    /// "Shark Tank: Best Of".
    static let extraWords: Set<String> = ["new", "premiere", "finale", "special", "live", "season", "series",
                                          "episode", "ep", "part", "repeat", "encore", "best", "of"]

    /// Whether a listing titled with `listing`'s words is the show titled with `show`'s: the same words, or the show's
    /// then only words a guide adds ("Shark Tank Mexico" is another show).
    static func titleMatches(_ show: [String], _ listing: [String]) -> Bool {
        guard !show.isEmpty, listing.count >= show.count, Array(listing.prefix(show.count)) == show else { return false }
        return listing.dropFirst(show.count).allSatisfy(extraWords.contains)
    }

    private static func isEpisodeMark(_ word: String) -> Bool {
        word.range(of: "^(s[0-9]+(e[0-9]+)?|e[0-9]+|ep[0-9]+)$", options: .regularExpression) != nil
    }

    // MARK: - Airings

    struct Listing: Equatable, Sendable {
        var title: String
        /// The guide's channel id (LiveStream.epgChannelId).
        var channelId: String
        var start: Date
        var end: Date
    }

    struct Channel: Equatable, Sendable {
        var epgId: String
        var name: String
        /// The LiveStream's id, to play it.
        var streamID: String
    }

    struct Airing: Equatable, Sendable, Identifiable {
        var show: GFFollowedShow
        /// As the guide has it for this airing.
        var title: String
        var start: Date
        var end: Date
        /// The best picture of the show's channel.
        var channel: Channel

        var id: String {
            show.id + "@" + String(Int(start.timeIntervalSince1970))
        }
    }

    /// The airings of `shows` in `listings` that have not ended, one for each start on the best picture of the show's
    /// channel, the earliest `perShow` of each show, earliest first.
    static func airings(of shows: [GFFollowedShow], listings: [Listing], channels: [Channel], now: Date,
                        perShow: Int = 8) -> [Airing] {
        guard !shows.isEmpty else { return [] }
        let byEPG = Dictionary(grouping: channels, by: \.epgId)
        let wanted: [(show: GFFollowedShow, words: [String], channel: String)] = shows.map { show in
            (show: show, words: titleWords(show.title), channel: GFSearchText.fold(show.channel))
        }
        var best: [String: Airing] = [:]
        for listing in listings where listing.end > now {
            let words = titleWords(listing.title)
            for channel in byEPG[listing.channelId] ?? [] {
                guard let base = self.channel(ofStreamName: channel.name).map(GFSearchText.fold) else { continue }
                for followed in wanted where followed.channel == base && titleMatches(followed.words, words) {
                    let airing = Airing(show: followed.show, title: listing.title, start: listing.start,
                                        end: listing.end, channel: channel)
                    if let current = best[airing.id], quality(current.channel) >= quality(channel) { continue }
                    best[airing.id] = airing
                }
            }
        }
        // split up: as one chain the type checker gave up (CI run 41876824587)
        let byShow: [String: [Airing]] = Dictionary(grouping: Array(best.values), by: { $0.show.id })
        var result: [Airing] = []
        for airings in byShow.values {
            let soonest: [Airing] = airings.sorted { $0.start < $1.start }
            result += soonest.prefix(perShow)
        }
        result.sort(by: Self.earlier)
        return result
    }

    private static func earlier(_ lhs: Airing, _ rhs: Airing) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.show.title < rhs.show.title
    }

    private static func quality(_ channel: Channel) -> Double {
        GFSearchEvents.quality(channelName: channel.name)
    }

    // MARK: - When

    /// The TV day a moment belongs to (from five in the morning), as the start of its calendar day: by the clock, so
    /// the days the clocks change are no different.
    static func tvDay(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < tvDayStartHour else { return day }
        return calendar.date(byAdding: .day, value: -1, to: day) ?? day
    }

    /// Whether a programme starting at `date` is an evening one (from five in the afternoon into the night).
    static func isEvening(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 17 || hour < tvDayStartHour
    }

    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                        timeZone: calendar.timeZone))
    }

    /// When an airing is, as the Coming Up row says it: "Live now", "Tonight 01:00", "Today 14:00", "Tomorrow 20:00",
    /// "Tomorrow night 01:00", "Friday 20:00", then the date. Counted from today's date (at two in the morning,
    /// this evening is tonight), the airing's day being its TV day.
    static func when(_ airing: Airing, now: Date, calendar: Calendar, locale: Locale) -> String {
        if airing.start <= now { return "Live now" }
        let clock = Self.time(airing.start, calendar: calendar, locale: locale)
        let night = calendar.component(.hour, from: airing.start) < tvDayStartHour
        let offset: Int = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                  to: tvDay(of: airing.start, calendar: calendar)).day ?? 0
        let days = max(0, offset)
        switch days {
        case 0:
            let part = isEvening(airing.start, calendar: calendar) ? "Tonight" : "Today"
            return "\(part) \(clock)"
        case 1:
            return night ? "Tomorrow night \(clock)" : "Tomorrow \(clock)"
        case 2 ..< 7:
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            let day = tvDay(of: airing.start, calendar: calendar)
                .addingTimeInterval(12 * 3600).formatted(style.weekday(.wide))
            return night ? "\(day) night \(clock)" : "\(day) \(clock)"
        default:
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return airing.start.formatted(style.day().month(.abbreviated)) + " " + clock
        }
    }

    // MARK: - One a show a day

    /// A show's first airing of a TV day and the day's later starts: one card on the Coming Up row, one heads-up and
    /// one reminder (Georgs, 4 Nov: Shark Tank's two episodes back to back, 03:00 and 04:00, made two cards).
    struct Entry: Equatable, Sendable, Identifiable {
        var airing: Airing
        var later: [Date]

        var id: String {
            airing.id
        }
    }

    /// `airings` as one entry a show a TV day, soonest first.
    static func days(_ airings: [Airing], calendar: Calendar) -> [Entry] {
        var order: [String] = []
        var entries: [String: Entry] = [:]
        for airing in airings.sorted(by: { $0.start < $1.start }) {
            let day = tvDay(of: airing.start, calendar: calendar)
            let key = airing.show.id + "@" + String(Int(day.timeIntervalSince1970))
            if entries[key] == nil {
                entries[key] = Entry(airing: airing, later: [])
                order.append(key)
            } else {
                entries[key]?.later.append(airing.start)
            }
        }
        return order.compactMap { entries[$0] }
    }

    /// The Coming Up row: each show once, its next day with airings.
    static func row(_ airings: [Airing], calendar: Calendar) -> [Entry] {
        var shown = Set<String>()
        return days(airings, calendar: calendar).filter { shown.insert($0.airing.show.id).inserted }
    }

    /// A card's "when" with the day's later starts: "Tonight 03:00 · 04:00".
    static func when(_ entry: Entry, now: Date, calendar: Calendar, locale: Locale) -> String {
        let later: [String] = entry.later.map { time($0, calendar: calendar, locale: locale) }
        return ([when(entry.airing, now: now, calendar: calendar, locale: locale)] + later).joined(separator: " · ")
    }

    /// "03:00", "03:00 and 04:00", "03:00, 04:00 and 05:00".
    static func times(_ dates: [Date], calendar: Calendar, locale: Locale) -> String {
        let clocks: [String] = dates.map { time($0, calendar: calendar, locale: locale) }
        guard clocks.count > 1, let last = clocks.last else { return clocks.first ?? "" }
        return clocks.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Reminders

    struct Reminder: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            /// On the airing's TV day, at `headsUpHour`.
            case headsUp
            /// An hour before it starts.
            case hourBefore
        }

        var kind: Kind
        var airing: Airing
        var fire: Date
        /// The same day's later starts of the show (back-to-back episodes), named in the heads-up.
        var later: [Date] = []

        var id: String {
            "gf.follow." + airing.id + "." + kind.rawValue
        }

        var title: String {
            airing.show.title
        }

        func body(calendar: Calendar, locale: Locale) -> String {
            let clock = GFFollowedShows.time(airing.start, calendar: calendar, locale: locale)
            switch kind {
            case .headsUp:
                let part = GFFollowedShows.isEvening(airing.start, calendar: calendar) ? "Tonight" : "Today"
                let clocks = GFFollowedShows.times([airing.start] + later, calendar: calendar, locale: locale)
                return "\(part) at \(clocks) on \(airing.show.channel)"
            case .hourBefore:
                return "Starts in an hour, at \(clock), on \(airing.show.channel)"
            }
        }
    }

    /// The reminders for `airings` still to come, for each show's first airing of a TV day (back-to-back episodes or a
    /// later repeat get none of their own; one already on gets none for the rest of its day): an hour before, and a
    /// heads-up at `headsUpHour` unless that would come after the hour-before one. The soonest `limit`, soonest first.
    static func reminders(for airings: [Airing], now: Date, calendar: Calendar,
                          limit: Int = reminderLimit) -> [Reminder] {
        var result: [Reminder] = []
        for entry in days(airings, calendar: calendar) where entry.airing.start > now {
            let airing = entry.airing
            let hourBefore = airing.start.addingTimeInterval(-3600)
            if hourBefore > now {
                result.append(Reminder(kind: .hourBefore, airing: airing, fire: hourBefore, later: entry.later))
            }
            let day = tvDay(of: airing.start, calendar: calendar)
            guard let headsUp = calendar.date(bySettingHour: headsUpHour, minute: 0, second: 0, of: day),
                  headsUp > now, headsUp < hourBefore else { continue }
            result.append(Reminder(kind: .headsUp, airing: airing, fire: headsUp, later: entry.later))
        }
        result.sort { $0.fire < $1.fire }
        return Array(result.prefix(limit))
    }
}
