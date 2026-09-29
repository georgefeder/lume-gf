#if GF_DEMO
    import SwiftData
    import SwiftUI

    /// Screenshot build only (compiled with `-D GF_DEMO` by ci/screenshots.sh, never in a TestFlight build). Started
    /// with `-GFDemo guide` or `-GFDemo list`, the app shows Lume's own guide or channel list over made-up channels named
    /// like our server names them. `-GFDemoMoves right,down` moves the Apple TV guide's focus after it lands; `end`
    /// scrolls the iPhone guide to its last row. `-GFDemoChannels 3` shows a short category.
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
    }

    /// An in-memory store: one category of made-up channels and programmes from three hours ago to nine ahead.
    @MainActor
    final class GFDemoStore {
        let container: ModelContainer
        let scope: LiveChannelScope

        init(count: Int = GFDemo.channelCount, now: Date = .now) {
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(
                for: Playlist.self, Category.self, LiveStream.self, EPGListing.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = container.mainContext
            let playlist = Playlist(name: "Demo", serverURL: "http://example.com", username: "u", password: "p")
            context.insert(playlist)
            let category = Category(apiId: "1", name: "Sport", parentId: 0, type: .live, playlist: playlist)
            context.insert(category)
            for (index, name) in Self.channelNames(now: now).prefix(count).enumerated() {
                let channelId = "demo-\(index)"
                context.insert(LiveStream(
                    id: "\(playlist.id.uuidString)-live-\(index)", streamId: 100 + index, name: name,
                    epgChannelId: channelId, tvArchive: index % 4 == 3 ? 1 : 0, tvArchiveDuration: 7,
                    num: index + 1, categoryId: category.id
                ))
                for listing in Self.programmes(channelId: channelId, index: index, name: name, now: now) {
                    context.insert(listing)
                }
            }
            try? context.save()
            self.container = container
            scope = .category(category.id)
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
            let label = GFChannelLabel.parse(name, now: now)
            let quarter: TimeInterval = 15 * 60
            var start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / quarter).rounded(.down) * quarter)
                .addingTimeInterval(-3 * 3600 - Double(index % 4) * quarter)
            let lengths: [TimeInterval] = [30, 60, 45, 90, 60].map { $0 * 60 }
            var result: [EPGListing] = []
            var slot = index
            while start < now.addingTimeInterval(9 * 3600) {
                let end = start.addingTimeInterval(lengths[slot % lengths.count])
                let isEvent = label.status != .none && start <= now && now < end
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

    /// The demo's screen: Lume's own guide or list for the demo category.
    struct GFDemoRoot: View {
        @State private var store = GFDemoStore()
        @State private var focusToken = 1

        var body: some View {
            content.modelContainer(store.container)
        }

        @ViewBuilder private var content: some View {
            #if os(tvOS)
                if GFDemo.mode == "list" {
                    TVChannelsList(scope: store.scope, playlistPrefix: "", sort: .playlist, sourceType: nil,
                                   onStartMultiView: { _ in }, onPlay: { _ in })
                } else {
                    EPGGuideView(scope: store.scope, playlistPrefix: "", sort: .playlist, onPlay: { _ in },
                                 focusToken: focusToken, onDidClaimFocus: { focusToken = 0 })
                }
            #elseif os(iOS)
                TabView {
                    Tab("Live TV", systemImage: "tv") {
                        NavigationStack {
                            Group {
                                if GFDemo.mode == "list" {
                                    ChannelsList(scope: store.scope, playlistPrefix: "", sort: .playlist,
                                                 onStartMultiView: { _ in }, onPlay: { _ in })
                                } else {
                                    EPGGuideView(scope: store.scope, playlistPrefix: "", sort: .playlist,
                                                 onPlay: { _ in })
                                }
                            }
                            .navigationTitle("Sport")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    Tab("Movies", systemImage: "film") { Color.clear }
                    Tab("Series", systemImage: "rectangle.stack") { Color.clear }
                    Tab("Search", systemImage: "magnifyingglass") { Color.clear }
                }
            #endif
        }
    }
#endif
