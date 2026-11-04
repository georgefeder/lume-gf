import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
    import UserNotifications
#endif

// Following shows (Georgs, 4 Nov: "I could follow shows ... it would send me out a notification an hour before that
// it's going to be on the TV in an hour"): the Follow button in the guide's programme sheet, the Coming Up row on
// Home, and on iPhone and iPad a heads-up on the day and a reminder an hour before (tvOS shows apps' notices as a badge
// at most). The logic is GFFollowedShows; the list syncs to every device with the settings.

/// The shows followed, as the app shares them. Kept in the settings as JSON (synced to every device by
/// GFSettingsSync); a list arriving from another device is read when the settings change.
@MainActor
@Observable
final class GFFollowStore {
    static let shared = GFFollowStore(defaults: .standard)

    private(set) var shows: [GFFollowedShow]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        shows = GFFollowedShows.decode(defaults.string(forKey: GFFollowedShows.storageKey))
        #if GF_DEMO
            if let demo = GFDemo.followedShows {
                shows = demo
                return
            }
        #endif
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func isFollowed(title: String, streamName: String) -> Bool {
        GFFollowedShows.isFollowed(shows, title: title, streamName: streamName)
    }

    func toggle(title: String, streamName: String) {
        let next = GFFollowedShows.toggled(shows, title: title, streamName: streamName, now: Date())
        guard next != shows else { return }
        let followed = next.count > shows.count
        shows = next
        defaults.set(GFFollowedShows.encode(next), forKey: GFFollowedShows.storageKey)
        if followed { GFShowReminders.askPermission() }
        GFShowReminders.rescheduleSoon()
    }

    private func reload() {
        let stored = GFFollowedShows.decode(defaults.string(forKey: GFFollowedShows.storageKey))
        guard stored != shows else { return }
        shows = stored
        GFShowReminders.rescheduleSoon()
    }
}

/// The followed shows' airings in the guide on this device.
enum GFComingUp {
    /// How far ahead the guide is searched.
    nonisolated static let horizon: TimeInterval = 8 * 86400

    /// The next airings of `shows` on the channels of the playlist whose streams' ids start with `prefix`, in a
    /// context of its own (it runs away from the main actor: the guide is narrowed by title, a scan of its table).
    nonisolated static func airings(of shows: [GFFollowedShow], container: ModelContainer, prefix: String, now: Date,
                                    perShow: Int) -> [GFFollowedShows.Airing] {
        guard !shows.isEmpty, !prefix.isEmpty else { return [] }
        let context = ModelContext(container)
        let until = now.addingTimeInterval(horizon)
        var listings: [GFFollowedShows.Listing] = []
        for word in Set(shows.compactMap { GFFollowedShows.searchWord($0.title) }) {
            var descriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { $0.end > now && $0.start < until && $0.title.localizedStandardContains(word) }
            )
            descriptor.fetchLimit = 2000
            listings += ((try? context.fetch(descriptor)) ?? []).map {
                GFFollowedShows.Listing(title: $0.title, channelId: $0.channelId, start: $0.start, end: $0.end)
            }
        }
        guard !listings.isEmpty else { return [] }
        let wanted = Set(listings.map(\.channelId))
        var streams = FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.id.starts(with: prefix) && $0.isHidden == false },
            sortBy: [SortDescriptor(\.num)]
        )
        streams.propertiesToFetch = [\.epgChannelId, \.name]
        let channels = ((try? context.fetch(streams)) ?? []).compactMap { stream -> GFFollowedShows.Channel? in
            guard let epg = stream.epgChannelId, wanted.contains(epg) else { return nil }
            return GFFollowedShows.Channel(epgId: epg, name: stream.name, streamID: stream.id)
        }
        return GFFollowedShows.airings(of: shows, listings: listings, channels: channels, now: now, perShow: perShow)
    }

    /// The chosen playlist's stream id prefix ("<playlist id>-"), as the app's other screens pick the playlist.
    static func activePrefix(context: ModelContext) -> String {
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        let selected = UserDefaults.standard.string(forKey: PlaylistSelectionStore.key) ?? ""
        return playlists.active(for: selected).map { $0.id.uuidString + "-" } ?? ""
    }
}

/// Home's Coming Up row's airings: loaded by `gfComingUpSource` on Home, again when the follows, the playlist or the
/// guide change, and at each airing's start and end (so "Live now" comes and goes).
@MainActor
@Observable
final class GFComingUpModel {
    private(set) var airings: [GFFollowedShows.Airing] = []
    private(set) var now = Date()

    /// The row's most cards.
    static let rowLimit = 12

    func keepLoading(shows: [GFFollowedShow], container: ModelContainer, prefix: String) async {
        while !Task.isCancelled {
            let now = Date()
            let found = await Task.detached(priority: .utility) {
                GFComingUp.airings(of: shows, container: container, prefix: prefix, now: now, perShow: 3)
            }.value
            guard !Task.isCancelled else { return }
            self.now = now
            airings = Array(found.prefix(Self.rowLimit))
            let next = found.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min() ?? now.addingTimeInterval(900)
            try? await Task.sleep(for: .seconds(min(max(next.timeIntervalSince(now) + 1, 60), 900)))
        }
    }
}

extension View {
    /// Home: loads the Coming Up row's airings (`GFComingUpRow` reads them from the environment). On Home itself, not
    /// on the row, so a row with nothing to show leaves no gap.
    func gfComingUpSource(playlistPrefix: String) -> some View {
        modifier(GFComingUpSource(playlistPrefix: playlistPrefix))
    }
}

private struct GFComingUpSource: ViewModifier {
    let playlistPrefix: String
    @Environment(\.modelContext) private var context
    @State private var model = GFComingUpModel()

    private struct Key: Equatable {
        var shows: [GFFollowedShow]
        var prefix: String
        var guide: String
    }

    func body(content: Content) -> some View {
        content
            .environment(model)
            .task(id: Key(shows: GFFollowStore.shared.shows, prefix: playlistPrefix, guide: GuideStatus.shared.line)) {
                await model.keepLoading(shows: GFFollowStore.shared.shows, container: context.container,
                                        prefix: playlistPrefix)
            }
    }
}

/// Home's Coming Up row: the followed shows' next airings, live ones first in time, each on the best picture of its
/// channel. A card plays the channel; held, it unfollows. Nothing at all while there is nothing coming up.
struct GFComingUpRow: View {
    let onPlay: (LiveStream) -> Void
    @Environment(GFComingUpModel.self) private var model: GFComingUpModel?
    @Environment(\.modelContext) private var context

    var body: some View {
        if let model, !model.airings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coming Up")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(model.airings) { airing in
                            GFComingUpCard(airing: airing, now: model.now) { play(airing) }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, Self.verticalPadding)
                }
                .scrollClipDisabled()
            }
        }
    }

    private static var spacing: CGFloat {
        #if os(tvOS)
            40
        #else
            12
        #endif
    }

    private static var verticalPadding: CGFloat {
        #if os(tvOS)
            24
        #else
            0
        #endif
    }

    private func play(_ airing: GFFollowedShows.Airing) {
        let id = airing.channel.streamID
        guard let stream = try? context.fetch(FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id }))
            .first else { return }
        onPlay(stream)
    }
}

/// One airing: when ("Live now" in red, "Tonight 01:00"), the show, the channel.
private struct GFComingUpCard: View {
    let airing: GFFollowedShows.Airing
    let now: Date
    let onPlay: () -> Void

    private var isLive: Bool {
        airing.start <= now
    }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                HStack(spacing: 6) {
                    if isLive {
                        Circle().fill(.red).frame(width: Self.dot, height: Self.dot)
                    }
                    Text(GFFollowedShows.when(airing, now: now, calendar: .current, locale: .current))
                        .font(Self.whenFont)
                        .foregroundStyle(isLive ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Text(airing.show.title)
                    .font(Self.titleFont)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(GFChannelNames.title(for: airing.channel.name))
                    .font(Self.channelFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(Self.padding)
            .frame(width: Self.width, alignment: .leading)
            #if !os(tvOS)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(GFPressStyle())
        #endif
        .contextMenu {
            Button(role: .destructive) {
                GFFollowStore.shared.toggle(title: airing.show.title, streamName: airing.channel.name)
            } label: {
                Label("Unfollow \(airing.show.title)", systemImage: "bell.slash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLive ? "Plays the channel" : "Plays the channel; the show is still to come")
    }

    #if os(tvOS)
        private static let width: CGFloat = 420
        private static let padding: CGFloat = 28
        private static let lineSpacing: CGFloat = 8
        private static let dot: CGFloat = 12
        private static let whenFont = Font.callout.weight(.semibold)
        private static let titleFont = Font.headline
        private static let channelFont = Font.callout
    #else
        private static let width: CGFloat = 200
        private static let padding: CGFloat = 14
        private static let lineSpacing: CGFloat = 4
        private static let dot: CGFloat = 7
        private static let whenFont = Font.caption.weight(.semibold)
        private static let titleFont = Font.headline
        private static let channelFont = Font.subheadline
    #endif
}

/// Pressed, a card gives a little at once and springs back (no lag before the press shows).
private struct GFPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}

/// The guide's programme sheet: follow the programme on this channel, or stop. Not for an event slot, which never
/// shows the same thing twice.
struct GFFollowButton: View {
    let title: String
    let streamName: String

    private var store: GFFollowStore {
        .shared
    }

    var body: some View {
        if GFFollowedShows.channel(ofStreamName: streamName) != nil {
            let followed = store.isFollowed(title: title, streamName: streamName)
            #if os(tvOS)
                TVPlayButton(title: followed ? "Following" : "Follow", systemImage: followed ? "bell.fill" : "bell") {
                    store.toggle(title: title, streamName: streamName)
                }
            #else
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        store.toggle(title: title, streamName: streamName)
                    } label: {
                        Label(followed ? "Following" : "Follow", systemImage: followed ? "bell.fill" : "bell")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .sensoryFeedback(.selection, trigger: followed)
                    Text(followed
                        ? "On Home's Coming Up, with a reminder on the day and an hour before it starts."
                        : "Follow to see it on Home's Coming Up and get a reminder an hour before it starts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .contain)
            #endif
        }
    }
}

/// A channel to open, asked for by a reminder's tap (the root's player shows it: GFContinueBannerHost).
@MainActor
@Observable
final class GFShowOpenRequest {
    static let shared = GFShowOpenRequest()
    var streamID: String?

    private init() {}
}

/// The reminders handed to iOS: worked out again after each guide refresh, when the follows change, on coming to the
/// front and when the time zone changes (travelling: the times are the phone's own). A reminder's tap opens its
/// channel. Nothing on the Apple TV.
@MainActor
enum GFShowReminders {
    private static var pending: Task<Void, Never>?
    private static var started = false
    private static let userInfoKey = "gf.follow.stream"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lume", category: "follow")

    /// At launch (LumeAppDelegate), before a reminder's tap can arrive.
    static func installDelegate() {
        #if os(iOS)
            UNUserNotificationCenter.current().delegate = GFShowReminderDelegate.shared
        #endif
    }

    /// Once, from the app's root: watches the time zone and works the reminders out.
    static func start() {
        guard !started else { return }
        started = true
        #if os(iOS)
            for name in [NSNotification.Name.NSSystemTimeZoneDidChange,
                         UIApplication.significantTimeChangeNotification] {
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { rescheduleSoon() }
                }
            }
        #endif
        rescheduleSoon()
    }

    /// After the first follow: iOS asks once whether Lume GF may send them.
    static func askPermission() {
        #if os(iOS)
            guard !LumeApp.isTestOrPreviewHost else { return }
            Task {
                let center = UNUserNotificationCenter.current()
                guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                rescheduleSoon()
            }
        #endif
    }

    /// Works them out a moment from now: several changes at once make one.
    static func rescheduleSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    static func reschedule() async {
        #if os(iOS)
            guard let container = GuideScheduler.shared.currentContainer else { return }
            let center = UNUserNotificationCenter.current()
            let shows = GFFollowStore.shared.shows
            let now = Date()
            let prefix = GFComingUp.activePrefix(context: ModelContext(container))
            let airings = await Task.detached(priority: .utility) {
                GFComingUp.airings(of: shows, container: container, prefix: prefix, now: now, perShow: 8)
            }.value
            let calendar = Calendar.current
            let reminders = GFFollowedShows.reminders(for: airings, now: now, calendar: calendar)
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("gf.follow.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            let status = await center.notificationSettings().authorizationStatus
            guard !reminders.isEmpty, status == .authorized || status == .provisional || status == .ephemeral
            else {
                log.info("Follow: \(shows.count) shows, no reminders set")
                return
            }
            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body(calendar: calendar, locale: .current)
                content.sound = .default
                content.threadIdentifier = "gf.follow." + reminder.airing.show.id
                content.userInfo = [userInfoKey: reminder.airing.channel.streamID]
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, reminder.fire.timeIntervalSince(now)), repeats: false
                )
                try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                            trigger: trigger))
            }
            log.info("Follow: \(shows.count) shows, \(reminders.count) reminders set")
        #endif
    }

    /// A reminder was tapped: its channel opens.
    fileprivate static func opened(streamID: String) {
        GFShowOpenRequest.shared.streamID = streamID
    }
}

#if os(iOS)
    /// Shows reminders while the app is open too, and opens a tapped one's channel.
    nonisolated private final class GFShowReminderDelegate: NSObject, UNUserNotificationCenterDelegate,
        @unchecked Sendable {
        static let shared = GFShowReminderDelegate()

        nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification)
            async -> UNNotificationPresentationOptions {
            [.banner, .list, .sound]
        }

        nonisolated func userNotificationCenter(_: UNUserNotificationCenter,
                                                didReceive response: UNNotificationResponse) async {
            let info = response.notification.request.content.userInfo
            guard let streamID = info["gf.follow.stream"] as? String else { return }
            await MainActor.run { GFShowReminders.opened(streamID: streamID) }
        }
    }
#endif
