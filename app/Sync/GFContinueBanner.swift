import SwiftData
import SwiftUI

/// The continue banner's state (spec section 5): on coming to the front with nothing playing, it reads the note and
/// offers it when `GFContinueOffer` says so and this device's catalogue has the item.
@MainActor
@Observable
final class GFContinueBannerModel {
    private(set) var offered: GFLastPlayedNote?
    private let store: GFLastPlayedStoring?
    private let context: ModelContext
    private let dismissedDefaults: UserDefaults
    private static let dismissedKey = "gf.banner.dismissed"

    init(store: GFLastPlayedStoring?, context: ModelContext, dismissedDefaults: UserDefaults = .standard) {
        self.store = store
        self.context = context
        self.dismissedDefaults = dismissedDefaults
    }

    /// `playingHere`: whether video plays on this device (nil: ask Lume; tests pass it).
    func refresh(now: Date, playingHere: Bool? = nil) async {
        guard let store else {
            offered = nil
            return
        }
        let note = await store.load()
        let dismissed = Set(dismissedDefaults.stringArray(forKey: Self.dismissedKey) ?? [])
        offered = GFContinueOffer.offer(note, myDeviceID: GFLastPlayed.deviceID, now: now, dismissed: dismissed,
                                        inCatalog: note.map { inCatalog($0) } ?? false,
                                        playingHere: playingHere ?? ContentIndexingService.shared.isPlaybackActive)
    }

    func dismiss() {
        guard let offered else { return }
        var dismissed = dismissedDefaults.stringArray(forKey: Self.dismissedKey) ?? []
        dismissed.append(GFContinueOffer.dismissalKey(offered))
        dismissedDefaults.set(Array(dismissed.suffix(50)), forKey: Self.dismissedKey)
        self.offered = nil
    }

    func media(playlists: [Playlist], selectedID: String) -> PlayableMedia? {
        guard let note = offered,
              let playlist = playlists.owner(ofContentID: note.contentId) ?? playlists.active(for: selectedID)
        else { return nil }
        let id = note.contentId
        switch note.kind {
        case .channel:
            guard let stream = try? context.fetch(FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id }))
                .first else { return nil }
            return PlayableMedia.from(stream: stream, playlist: playlist)
        case .film:
            guard let movie = try? context.fetch(FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })).first,
                  let media = PlayableMedia.from(movie: movie, playlist: playlist) else { return nil }
            return media.startingAt(note.position)
        case .episode:
            guard let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id }))
                .first, let media = PlayableMedia.from(episode: episode, playlist: playlist) else { return nil }
            return media.startingAt(note.position)
        }
    }

    private func inCatalog(_ note: GFLastPlayedNote) -> Bool {
        let id = note.contentId
        switch note.kind {
        case .channel:
            return ((try? context.fetchCount(FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id }))) ?? 0)
                > 0
        case .film:
            return ((try? context.fetchCount(FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
        case .episode:
            return ((try? context.fetchCount(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
        }
    }
}

extension PlayableMedia {
    /// The same media resuming at `seconds` (the minute the other device stopped).
    func startingAt(_ seconds: Double) -> PlayableMedia {
        guard seconds > 0 else { return self }
        return PlayableMedia(id: id, url: url, title: title, subtitle: subtitle, posterURL: posterURL, kind: kind,
                             startTime: seconds, contentRef: contentRef, channelScope: channelScope,
                             httpHeaders: httpHeaders)
    }
}

/// Where the banner sits: iPhone and iPad at the top under the Dynamic Island, Apple TV top-right.
enum GFContinueBannerLayout {
    static var alignment: Alignment {
        #if os(tvOS)
            .topTrailing
        #else
            .top
        #endif
    }

    static var padding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 60)
        #else
            EdgeInsets(top: 4, leading: 10, bottom: 0, trailing: 10)
        #endif
    }
}

/// The banner itself: Liquid Glass, artwork, title, where and when, a play button (iPhone/iPad) or the remote's
/// Play/Pause hint (Apple TV); never focusable on the Apple TV.
struct GFContinueBannerView: View {
    let note: GFLastPlayedNote
    let now: Date
    var onPlay: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(note.kind == .channel ? "Continue \(note.title)" : note.title)
                    .font(.headline).lineLimit(1)
                Text(GFContinueOffer.subtitle(note, now: now))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if note.kind != .channel, note.duration > 0 {
                    ProgressView(value: min(1, note.position / note.duration)).tint(.primary).frame(maxWidth: 160)
                }
            }
            Spacer(minLength: 8)
            #if os(tvOS)
                // a fixed size: the TV's title3 drew the wide play-pause glyph past its circle
                Image(systemName: "playpause.fill").font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 64).glassEffectCompat(.regular, in: Circle())
            #else
                Button(action: onPlay) {
                    Image(systemName: "play.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffectCompat(.regularInteractive, in: Circle())
                .accessibilityLabel(Text("Play"))
            #endif
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffectCompat(.regular, in: Capsule())
        #if os(tvOS)
            .frame(width: 640)
            .focusable(false)
        #else
            .frame(maxWidth: 520) // an iPad's banner stays phone-sized
        #endif
    }

    @ViewBuilder private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        AsyncImage(url: note.artworkURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: note.kind == .channel ? "dot.radiowaves.left.and.right" : "film")
                .foregroundStyle(.secondary)
        }
        .frame(width: note.kind == .channel ? 46 : 34, height: 46)
        .background(.quaternary, in: shape)
        .clipShape(shape)
    }
}

/// At the app's root: refreshes when the app comes to the front, shows the banner for ten seconds (iPhone/iPad: top,
/// tap or swipe up; Apple TV: top-right, Play/Pause), and opens the player. Never on a child profile: the note can be
/// a grown-up's channel.
private struct GFContinueBannerHost: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
    @Query private var playlists: [Playlist]
    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID = ""
    @State private var model: GFContinueBannerModel?
    @State private var playing: PlayableMedia?
    @State private var shownAt = Date()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: GFContinueBannerLayout.alignment) { banner }
        #if os(tvOS)
            .onPlayPauseCommand(perform: playPauseAction)
        #endif
        #if !os(macOS)
            // above MainTabView, so the player gets the child lock the way the macOS player window does
            .fullScreenCover(item: $playing) { media in
                ContentRestrictionProvider { FullScreenPlayerView(media: media) }
            }
        #endif
            .task(id: scenePhase) { await refresh() }
            .animation(.smooth, value: model?.offered)
    }

    @ViewBuilder private var banner: some View {
        if let note = model?.offered {
            GFContinueBannerView(note: note, now: shownAt, onPlay: play)
                .padding(GFContinueBannerLayout.padding)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gfBannerGestures(onTap: play, onSwipeUp: dismiss)
                .task(id: note.updatedAt) {
                    try? await Task.sleep(for: .seconds(10))
                    if model?.offered == note { dismiss() }
                }
        }
    }

    /// Apple TV: Play/Pause plays the banner's item while it shows; with no banner the press goes on as usual.
    private var playPauseAction: (() -> Void)? {
        guard model?.offered != nil else { return nil }
        return { play() }
    }

    private func refresh() async {
        guard scenePhase == .active, profileManager?.activeProfileIsChild != true else { return }
        if model == nil { model = GFContinueBannerModel(store: GFLastPlayed.store, context: context) }
        shownAt = Date()
        await model?.refresh(now: shownAt)
    }

    private func play() {
        guard let media = model?.media(playlists: playlists, selectedID: selectedPlaylistID) else {
            dismiss()
            return
        }
        model?.dismiss()
        playing = media
    }

    private func dismiss() {
        model?.dismiss()
    }
}

private extension View {
    /// iPhone and iPad: tap to play, swipe up to dismiss (the Apple TV uses Play/Pause).
    @ViewBuilder func gfBannerGestures(onTap: @escaping () -> Void, onSwipeUp: @escaping () -> Void) -> some View {
        #if os(tvOS)
            self
        #else
            onTapGesture(perform: onTap)
                .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < 0 { onSwipeUp() } })
        #endif
    }
}

extension View {
    /// Lume GF (Part 4): continue on this device what another one played.
    func gfContinueBanner() -> some View {
        modifier(GFContinueBannerHost())
    }
}
