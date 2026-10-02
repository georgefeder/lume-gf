#if GF_DEMO
    import SwiftData
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #endif

    /// Screenshot build only (compiled with `-D GF_DEMO` by ci/screenshots.sh, never in a TestFlight build). Started
    /// with `-GFDemo guide` or `-GFDemo list`, the app shows Lume's own guide or channel list over made-up channels named
    /// like our server names them. `-GFDemoMoves right,down` moves the Apple TV guide's focus after it lands; `end`
    /// scrolls the iPhone guide to its last row, `landscape` turns the iPhone sideways. `-GFDemoChannels 3` shows a short
    /// category. `-GFDemoNoPanel 1` hides the channel column, glass and all (ci/guide-check.py sees what the programmes
    /// leave under it: the simulator's glass is too frosted to show it, a real Apple TV's bends it into view).
    /// `-GFDemo home`, `movies` or `series` shows Lume's own Home, Movies or Series screen over made-up films and
    /// series (some with long titles) and a few watched channels.
    enum GFDemo {
        static var mode: String? {
            value(after: "-GFDemo")
        }

        static var moves: [String] {
            value(after: "-GFDemoMoves")?.split(separator: ",").map(String.init) ?? []
        }

        static var channelCount: Int {
            value(after: "-GFDemoChannels").flatMap(Int.init) ?? 12
        }

        static var noPanel: Bool {
            value(after: "-GFDemoNoPanel") == "1"
        }

        /// For ci/guide-check.py, in points on screen: the guide, the glass panel, the fades and where the programmes
        /// fade out under the panel.
        static func logGeometry(guide: CGRect, columnWidth: CGFloat, rowSpacing: CGFloat, topFade: CGFloat) {
            let tv = GFGuideGlass.isTV
            let insets = GFGuideGlass.sidebarInsets(tv: tv)
            let under = GFGuideGlass.underPanelFade(columnWidth: columnWidth, tv: tv)
            let fields: [(String, CGFloat)] = [
                ("scale", screenScale), ("guideX", guide.minX), ("guideY", guide.minY),
                ("guideW", guide.width), ("guideH", guide.height),
                ("panelMinX", guide.minX + insets.leading), ("panelMaxX", guide.minX + columnWidth - insets.trailing),
                ("panelTop", guide.minY + GFGuideGlass.panelTop(tv: tv, rowSpacing: rowSpacing)),
                ("fade", topFade), ("room", GFGuideGlass.gridTopRoom(tv: tv, rowSpacing: rowSpacing)),
                ("rowSpacing", rowSpacing), ("gone", guide.minX + under.gone), ("clear", guide.minX + under.clear)
            ]
            log("guide geometry: " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
        }

        /// For ci/guide-check.py: a card in a horizontal row of posters, where it sits on screen (the first six).
        static func logRailCard(rail: String, index: Int, frame: CGRect) {
            guard index < 6 else { return }
            log("rail card: \(index) \(frame.minY) \(frame.height) \(rail)")
        }

        /// The text of a row title given as a localized key (demo logs only).
        static func text(_ key: LocalizedStringKey) -> String {
            Mirror(reflecting: key).children.first { $0.label == "key" }?.value as? String ?? "\(key)"
        }

        /// For ci/guide-check.py: the focused programme's frame on screen as drawn (grown by `scale`).
        static func logFocusedProgramme(_ frame: CGRect, scale: CGFloat) {
            log("focused programme: x=\(frame.minX) y=\(frame.minY) w=\(frame.width) h=\(frame.height) scale=\(scale)")
        }

        private static var screenScale: CGFloat {
            #if canImport(UIKit)
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.scale ?? 0
            #else
                0
            #endif
        }

        private static func log(_ line: String) {
            FileHandle.standardError.write(Data(("GFDemo " + line + "\n").utf8))
        }

        private static func value(after flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        #if os(tvOS)
            /// The scripted remote presses, half a second apart so each scroll settles.
            static func playMoves(_ move: (MoveCommandDirection) -> Void) async {
                for name in moves {
                    try? await Task.sleep(for: .milliseconds(500))
                    switch name {
                    case "right": move(.right)
                    case "left": move(.left)
                    case "up": move(.up)
                    case "down": move(.down)
                    default: break
                    }
                }
            }
        #endif

        #if os(iOS)
            /// `-GFDemoMoves landscape`: the iPhone turns sideways.
            static func turnToLandscape() {
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        #endif
    }

    /// An in-memory store: one category of made-up channels and programmes from three hours ago to nine ahead, and a
    /// few empty categories for the Apple TV's category list.
    @MainActor
    final class GFDemoStore {
        let container: ModelContainer
        let scope: LiveChannelScope
        let categories: [Category]
        let playlist: Playlist
        /// The first channel, for `-GFDemoMoves play` (the iPhone opens it as Lume's Live TV screen does).
        let firstStream: LiveStream?

        init(count: Int = GFDemo.channelCount, now: Date = .now) {
            // every catalog model, as in Lume's own catalog store (LumeApp): a model left out here is never stored, so
            // the films and series would be missing from Home, Movies and Series
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(
                for: Playlist.self, Category.self, LiveStream.self, Movie.self, Series.self, Episode.self,
                CastMember.self, EPGListing.self, EPGSource.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            let playlist = Playlist(name: "Demo", serverURL: "http://example.com", username: "u", password: "p")
            context.insert(playlist)
            let names = ["Sport", "Entertainment", "News", "Films", "Documentaries", "Kids", "Latvia"]
            let categories = names.enumerated().map {
                Category(apiId: "\($0.offset + 1)", name: $0.element, parentId: 0, type: .live, playlist: playlist)
            }
            categories.forEach { context.insert($0) }
            let category = categories[0]
            Self.insertFilmsAndSeries(into: context, playlist: playlist, now: now)
            var streams: [LiveStream] = []
            for (index, name) in Self.channelNames(now: now).prefix(count).enumerated() {
                let channelId = "demo-\(index)"
                streams.append(LiveStream(
                    id: "\(playlist.id.uuidString)-live-\(index)", streamId: 100 + index, name: name,
                    epgChannelId: channelId, tvArchive: index % 4 == 3 ? 1 : 0, tvArchiveDuration: 7,
                    num: index + 1, categoryId: category.id
                ))
                context.insert(streams[streams.count - 1])
                // watched a little while ago (Home's Recently Watched) and one favourite
                switch index {
                case 0: streams[index].lastWatchedDate = now.addingTimeInterval(-10 * 60)
                case 3: streams[index].lastWatchedDate = now.addingTimeInterval(-3600)
                case 5: streams[index].lastWatchedDate = now.addingTimeInterval(-3 * 3600)
                case 1: streams[index].isFavorite = true
                default: break
                }
                for listing in Self.programmes(channelId: channelId, index: index, name: name, now: now) {
                    context.insert(listing)
                }
            }
            try? context.save()
            self.container = container
            self.categories = categories
            self.playlist = playlist
            firstStream = streams.first
            scope = .category(category.id)
        }

        /// Films and series as a server lists them, newest first; some titles run onto two lines (Georgs' photo of the
        /// Series page, 2 Oct: their posters sat higher than the others).
        private static func insertFilmsAndSeries(into context: ModelContext, playlist: Playlist, now: Date) {
            let films = Category(apiId: "100", name: "New Films", parentId: 0, type: .vod, playlist: playlist)
            let shows = Category(apiId: "200", name: "Drama", parentId: 0, type: .series, playlist: playlist)
            context.insert(films)
            context.insert(shows)
            let filmNames = ["Dune: Part Two", "The Lord of the Rings: The Return of the King", "Oppenheimer",
                             "Everything Everywhere All at Once", "Barbie", "Mission: Impossible - Dead Reckoning",
                             "Past Lives", "Top Gun: Maverick"]
            for (index, name) in filmNames.enumerated() {
                let added = Int(now.timeIntervalSince1970) - index * 3600
                context.insert(Movie(id: "\(playlist.id.uuidString)-movie-\(500 + index)", streamId: 500 + index,
                                     name: name, added: "\(added)", categoryId: films.id))
            }
            let seriesNames = ["War", "The Sisters Grimm", "Agent Kim Reactivated", "Age of the Living Dead",
                               "Break Clause", "Slow Horses"]
            for (index, name) in seriesNames.enumerated() {
                let modified = Int(now.timeIntervalSince1970) - index * 3600
                context.insert(Series(id: "\(playlist.id.uuidString)-series-\(700 + index)", seriesId: 700 + index,
                                      name: name, lastModified: "\(modified)", categoryId: shows.id))
            }
        }

        static func channelNames(now: Date) -> [String] {
            [
                "BBC One FHD",
                "ITV1 FHD",
                "🔴 LIVE \(riga(now.addingTimeInterval(-40 * 60), weekday: false)) · Arsenal v Chelsea · Premier League · FHD",
                "Sky Sports F1 4K",
                "⏰ \(riga(now.addingTimeInterval(2 * 86400), weekday: true)) · Japanese GP · Formula 1 · 4K",
                "Sky Sports Main Event FHD",
                "TNT Sports 1 HD",
                "Channel 4",
                "▪ Darts Night · HD",
                "BBC Two FHD",
                "⏰ \(riga(now.addingTimeInterval(3 * 3600), weekday: false)) · Rangers v Celtic · Premiership · FHD",
                "Eurosport 1 HD"
            ]
        }

        /// Riga time as events.py writes it ("20:30" or "Sun 17:55").
        private static func riga(_ date: Date, weekday: Bool) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = GFChannelLabelTime.serverTimeZone
            formatter.dateFormat = weekday ? "EEE HH:mm" : "HH:mm"
            return formatter.string(from: date)
        }

        private static let titles = ["Evening News", "Pointless", "The One Show", "Film: The Long Way Home",
                                     "Grand Designs", "Live Football", "Motorsport Tonight", "Question Time",
                                     "Darts Night", "Sports Centre"]

        private static func programmes(channelId: String, index: Int, name: String, now: Date) -> [EPGListing] {
            if index == 1 {
                // ITV1: nothing until twenty minutes ago (Lume's "No Programme"), then six hours of one programme, as
                // BBC Parliament in Georgs' photo of build 9 (focused, it spread over the "No Programme" before it)
                let start = now.addingTimeInterval(-20 * 60)
                return [EPGListing(id: "\(channelId)-long", channelId: channelId, title: "Parliament Live",
                                   listingDescription: "Made-up programme for Lume GF's screenshots.", start: start,
                                   end: start.addingTimeInterval(6 * 3600), subtitle: nil, category: nil)]
            }
            let label = GFChannelLabel.parse(name, now: now)
            let quarter: TimeInterval = 15 * 60
            var start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / quarter).rounded(.down) * quarter)
                .addingTimeInterval(-3 * 3600 - Double(index % 4) * quarter)
            let lengths: [TimeInterval] = [30, 60, 45, 90, 60].map { $0 * 60 }
            var result: [EPGListing] = []
            var slot = index
            while start < now.addingTimeInterval(9 * 3600) {
                let end = start.addingTimeInterval(lengths[slot % lengths.count])
                let isEvent = label.status == .live && start <= now && now < end
                result.append(EPGListing(
                    id: "\(channelId)-\(Int(start.timeIntervalSince1970))",
                    channelId: channelId,
                    title: isEvent ? label.title : titles[slot % titles.count],
                    listingDescription: "Made-up programme for Lume GF's screenshots.",
                    start: start,
                    end: end,
                    subtitle: nil,
                    category: nil
                ))
                start = end
                slot += 1
            }
            return result
        }
    }

    /// The demo's screen: Lume's own Live TV screen for the demo category — on Apple TV with its category list beside
    /// the guide or list, as in the app.
    struct GFDemoRoot: View {
        @State private var store: GFDemoStore
        @State private var section: LiveTVSection?
        @State private var layoutMode = (GFDemo.mode == "list" ? LiveTVLayoutMode.list : .guide).rawValue
        @State private var playing: PlayableMedia?
        /// As MainTabView hands it to its tabs: the Apple TV's Home requires it.
        @State private var router = DeepLinkRouter()
        #if os(iOS)
            /// The demo's first tab: Live TV unless `-GFDemo home`, `movies` or `series` asks for another.
            @State private var tab = ["home", "movies", "series"].contains(GFDemo.mode ?? "") ? GFDemo.mode ?? "live" : "live"
        #endif

        init() {
            let store = GFDemoStore()
            _store = State(initialValue: store)
            _section = State(initialValue: store.categories.first.map { LiveTVSection.category($0) })
        }

        var body: some View {
            content
                .environment(router)
                .modelContainer(store.container)
        }

        private func play(_ stream: LiveStream) {
            playing = PlayableMedia.from(stream: stream, playlist: store.playlist)
        }

        @ViewBuilder private var content: some View {
            #if os(tvOS)
                switch GFDemo.mode ?? "" {
                case "home": HomeView()
                case "movies": MoviesView()
                case "series": SeriesView()
                default: liveTV
                }
            #elseif os(iOS)
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house", value: "home") { HomeView() }
                    Tab("Live TV", systemImage: "tv", value: "live") { liveTV }
                    Tab("Movies", systemImage: "film", value: "movies") { MoviesView() }
                    Tab("Series", systemImage: "rectangle.stack", value: "series") { SeriesView() }
                }
                // as in the app (MainTabView): the tab bar shrinks while the guide scrolls down
                .tabBarMinimizeOnScrollDownIfAvailable()
                .task {
                    if GFDemo.moves.contains("landscape") { GFDemo.turnToLandscape() }
                    if GFDemo.moves.contains("play"), let stream = store.firstStream {
                        // -GFDemoMoves play: the first channel opens after four seconds (filmed by ci/screenshots.sh)
                        try? await Task.sleep(for: .seconds(4))
                        play(stream)
                    }
                }
            #endif
        }

        @ViewBuilder private var liveTV: some View {
            #if os(tvOS)
                TVLiveTVScreen(
                    sections: store.categories.map { LiveTVSection.category($0) },
                    selectedSection: $section,
                    displayedSection: section,
                    layoutModeRaw: $layoutMode,
                    contentSort: .playlist,
                    onPlay: { _ in },
                    onPlayCatchup: { _, _ in },
                    onOpenMultiView: {},
                    onStartMultiView: { _ in },
                    playlistPrefix: "",
                    sourceType: nil
                )
            #elseif os(iOS)
                NavigationStack {
                    Group {
                        if GFDemo.mode == "list" {
                            ChannelsList(scope: store.scope, playlistPrefix: "", sort: .playlist,
                                         onStartMultiView: { _ in }, onPlay: play)
                        } else {
                            EPGGuideView(scope: store.scope, playlistPrefix: "", sort: .playlist, onPlay: play)
                        }
                    }
                    .navigationTitle("Sport")
                    .navigationBarTitleDisplayMode(.inline)
                    // as Lume's Live TV screen opens a channel (LiveTVView)
                    .fullScreenCover(item: $playing) { media in
                        FullScreenPlayerView(media: media)
                    }
                }
            #endif
        }
    }

    extension View {
        /// For ci/guide-check.py: logs where a card of a horizontal poster row sits (Lume GF screenshot build only).
        func gfDemoRailCard(rail: String, index: Int) -> some View {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                GFDemo.logRailCard(rail: rail, index: index, frame: frame)
            }
        }

        func gfDemoRailCard(rail: LocalizedStringKey, index: Int) -> some View {
            gfDemoRailCard(rail: GFDemo.text(rail), index: index)
        }
    }
#endif
