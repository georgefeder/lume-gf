import Foundation

/// Lume GF: seeking in a catch-up programme by asking the archive again from a later minute, instead of seeking inside
/// the file (18 Nov 2026). Georgs' provider does not answer byte ranges precisely and its timestamps reset inside an
/// archive file, so a scrub in KSPlayer jumped to the end. The Xtream timeshift address takes its start to the minute:
/// `/timeshift/{user}/{pass}/{minutes}/{yyyy-MM-dd:HH-mm}/{id}.ts`. A jump rebuilds that address from the programme's
/// own one (the start moved on, the minutes cut to what is left) and plays it as a new item; the position bar shows
/// the programme's time, the minutes skipped plus the time played.
nonisolated enum GFCatchupSeek {
    /// The programme a catch-up item plays and where in it the archive address starts.
    nonisolated struct Window: Hashable, Codable {
        /// The programme's own address (from its start, for its whole length) and its media id.
        let baseURL: URL
        let baseID: String
        /// The programme's length, seconds.
        let length: TimeInterval
        /// How far into the programme the playing address starts, whole minutes in seconds.
        let offset: TimeInterval
        /// How many jumps led here: each jump is a new item even when it restarts the minute playing.
        var jumps: Int? = nil
    }

    /// What the viewer asked for: a place on the position bar, or a step from the current time.
    nonisolated enum Jump: Equatable {
        case to(TimeInterval)
        case by(TimeInterval)
    }

    /// The window for a programme that just opened from its own address; `nil` when the address is not an Xtream
    /// timeshift one (m3u catch-up dialects keep seeking inside the file).
    static func window(url: URL, id: String, start: Date, end: Date) -> Window? {
        guard timeshiftIndex(in: url) != nil else { return nil }
        return Window(baseURL: url, baseID: id, length: max(60, end.timeIntervalSince(start)), offset: 0)
    }

    /// The offset the archive should start at for `jump`, from the programme time on screen (`current`); `nil` when
    /// nothing changes (a step forward that stays inside the minute already playing would land where it plays).
    /// A place on the bar rounds down to its minute. A step forward goes at least to the next minute, so a 15-second
    /// skip still moves; a step back restarts its minute.
    static func offset(for jump: Jump, current: TimeInterval, in window: Window) -> TimeInterval? {
        let target: TimeInterval
        let forward: Bool
        switch jump {
        case let .to(time):
            target = time
            forward = time > current
        case let .by(step):
            target = current + step
            forward = step > 0
        }
        let last = max(0, ((window.length - 1) / 60).rounded(.down) * 60)
        var minute = (max(0, target) / 60).rounded(.down) * 60
        if forward, case .by = jump { minute = max(minute, window.offset + 60) }
        minute = min(minute, last)
        if minute == window.offset, forward { return nil }
        return minute
    }

    /// The archive address starting `offset` seconds into the programme, for what is left of it.
    static func url(_ window: Window, offset: TimeInterval) -> URL? {
        guard var parts = URLComponents(url: window.baseURL, resolvingAgainstBaseURL: false),
              let index = timeshiftIndex(in: window.baseURL)
        else { return nil }
        var path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let start = formatter.date(from: path[index + 4]) else { return nil }
        let minutes = Int(offset / 60)
        let left = max(1, Int(((window.length - offset) / 60).rounded(.up)))
        path[index + 3] = String(left)
        path[index + 4] = formatter.string(from: start.addingTimeInterval(TimeInterval(minutes * 60)))
        parts.percentEncodedPath = path.joined(separator: "/")
        return parts.url
    }

    /// The media id for the next jump, to `offset` into the programme: the programme's own with the minute and the
    /// jump's number (a new id is what makes the player take it as a new item, a restart of the same minute too).
    static func id(_ window: Window, offset: TimeInterval) -> String {
        "\(window.baseID)+\(Int(offset / 60))m.\((window.jumps ?? 0) + 1)"
    }

    /// Where `timeshift` sits in the path, when it is followed by user, password, minutes, start and stream.
    private static func timeshiftIndex(in url: URL) -> Int? {
        let path = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: false)
        guard let index = path.lastIndex(of: "timeshift"), path.count == index + 6,
              Int(path[index + 3]) != nil, formatter.date(from: String(path[index + 4])) != nil
        else { return nil }
        return index
    }

    /// The start as the panel wrote it, in its own wall-clock time; minutes are added to that wall clock as they are.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

extension GFCatchupSeek {
    /// The item a player shows, for closures it hands out once (the lock screen, the Apple TV engine) that would
    /// otherwise keep the item they were made with.
    @MainActor
    final class Playing {
        var media: PlayableMedia?
    }
}
