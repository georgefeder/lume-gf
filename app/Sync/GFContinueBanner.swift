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

    /// With the playlists as they are now: the tab bar's accessory can ask long after the host last drew.
    func media(selectedID: String) -> PlayableMedia? {
        media(playlists: (try? context.fetch(FetchDescriptor<Playlist>())) ?? [], selectedID: selectedID)
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

/// Where the banner sits (Georgs, 3 Nov: on every device it "feels geometrically wrong"). iPhone and iPad, iOS 26.1
/// on: in the tab bar's accessory place, above the tab bar and as wide as it, where Lume's Chromecast mini player sits
/// (`GFContinueAccessory`); the system lays it out on every screen, the Duo's two included. Before 26.1: at the top,
/// on the screen's 16-point margins. Apple TV: top right, where tvOS shows its own notices, on the safe area's top,
/// its right edge on the margin Home's rows start at on the left.
enum GFContinueBannerLayout {
    /// iOS 26.1's `tabViewBottomAccessory(isEnabled:)`; 26.0's accessory comes and goes only by rebuilding the tabs.
    static var usesTabAccessory: Bool {
        #if os(iOS)
            if #available(iOS 26.1, *) { return true }
        #endif
        return false
    }

    static var alignment: Alignment {
        #if os(tvOS)
            .topTrailing
        #else
            .top
        #endif
    }

    static var padding: EdgeInsets {
        #if os(tvOS)
            // inside the TV's safe area (60 points at the top, 80 at the sides): 16 more at the right puts the right
            // edge 96 points from the screen's, as Home's rows start 96 points from the left
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
        #else
            EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
        #endif
    }
}

/// The banner on the Apple TV, and on iPhone and iPad before iOS 26.1: Liquid Glass, the artwork, title, where and
/// when, a play button (iPhone/iPad) or the remote's Play/Pause hint (Apple TV); never focusable on the Apple TV. The
/// artwork and the button are circles as tall as the text, with the same gap all round, so they follow the capsule's
/// round ends (a square tile and a button shorter than the text sat off its curve).
struct GFContinueBannerView: View {
    let note: GFLastPlayedNote
    let now: Date
    var onPlay: () -> Void = {}
    @State private var textHeight: CGFloat = 0

    private static let gap: CGFloat = 8
    private static var smallestCircle: CGFloat {
        #if os(tvOS)
            64
        #else
            44
        #endif
    }

    private var circle: CGFloat {
        max(Self.smallestCircle, textHeight)
    }

    var body: some View {
        HStack(spacing: 12) {
            GFContinueArtwork(note: note, size: circle)
            GFContinueText(note: note, now: now)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            Spacer(minLength: 8)
            #if os(tvOS)
                Image(systemName: "playpause.fill").font(.system(size: circle * 0.36, weight: .semibold))
                    .frame(width: circle, height: circle).glassEffectCompat(.regular, in: Circle())
            #else
                Button(action: onPlay) {
                    Image(systemName: "play.fill").font(.title3).frame(width: circle, height: circle)
                }
                .buttonStyle(.plain)
                .glassEffectCompat(.regularInteractive, in: Circle())
                .accessibilityLabel(Text("Play"))
            #endif
        }
        .padding(Self.gap)
        .glassEffectCompat(.regular, in: Capsule())
        #if os(tvOS)
            .frame(width: 640)
            .focusable(false)
        #else
            .frame(maxWidth: 520) // an iPad's banner stays phone-sized
        #endif
    }
}

/// The title ("Continue BBC One" for a channel), where and when it played, and for a film or episode how far in.
private struct GFContinueText: View {
    let note: GFLastPlayedNote
    let now: Date
    /// The tab bar's accessory: smaller type; `inline` (beside a shrunk tab bar) the title alone.
    var accessory = false
    var inline = false
    var showsProgress = true

    var body: some View {
        VStack(alignment: .leading, spacing: accessory ? 1 : 2) {
            Text(note.kind == .channel ? "Continue \(note.title)" : note.title)
                .font(accessory ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
            if !inline {
                Text(GFContinueOffer.subtitle(note, now: now))
                    .font(accessory ? .caption : .subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if showsProgress, let progress = GFContinueArtwork.progress(note) {
                ProgressView(value: progress).tint(.primary).frame(maxWidth: 160)
            }
        }
    }
}

/// The artwork in a circle: a channel's logo whole inside it, a poster filling it.
private struct GFContinueArtwork: View {
    let note: GFLastPlayedNote
    let size: CGFloat

    /// How far into a film or episode, none for a channel.
    static func progress(_ note: GFLastPlayedNote) -> Double? {
        guard note.kind != .channel, note.duration > 0 else { return nil }
        return min(1, max(0, note.position / note.duration))
    }

    var body: some View {
        AsyncImage(url: note.artworkURL.flatMap(URL.init(string:))) { image in
            if note.kind == .channel {
                image.resizable().scaledToFit().padding(size * 0.18)
            } else {
                image.resizable().scaledToFill()
            }
        } placeholder: {
            Image(systemName: note.kind == .channel ? "dot.radiowaves.left.and.right" : "film")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

#if os(iOS)
    /// The banner in the tab bar's accessory place (iOS 26.1 on; Lume's `castMiniController` hands it the place while
    /// no cast plays). Laid out as Lume's Chromecast mini player is: the artwork, two lines, a play button with a ring
    /// for how far in a film is; beside a shrunk tab bar the title alone. Tap or Play plays, a swipe down dismisses.
    @available(iOS 26.1, *)
    struct GFContinueAccessory: View {
        @Environment(\.tabViewBottomAccessoryPlacement) private var placement
        /// The accessory's height, measured (iPhone: about 48 points).
        @State private var height: CGFloat = 48
        private var presence: GFContinueBannerPresence {
            .shared
        }

        var body: some View {
            if let note = presence.note {
                let inline = placement == .inline
                let artwork: CGFloat = inline ? 28 : 36
                let button: CGFloat = inline ? 32 : 40
                HStack(spacing: 10) {
                    GFContinueArtwork(note: note, size: artwork)
                    GFContinueText(note: note, now: presence.shownAt, accessory: true, inline: inline,
                                   showsProgress: false)
                    Spacer(minLength: 4)
                    Button { presence.play() } label: {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: button, height: button)
                            .overlay { ring(note, size: button) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Play"))
                }
                // the circles as far from the accessory's round ends as from its top and bottom: concentric with them
                .padding(.leading, max(4, (height - artwork) / 2))
                .padding(.trailing, max(4, (height - button) / 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .contentShape(Rectangle())
                .onTapGesture { presence.play() }
                .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded {
                    if $0.translation.height > 0 { presence.dismiss() }
                })
                // one element for VoiceOver: the title and where it played, activated to play
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { presence.play() }
                .accessibilityAction(named: Text("Dismiss")) { presence.dismiss() }
                // ten seconds on screen, then it goes (hidden behind the cast player or a pushed screen it waits)
                .task(id: note.updatedAt) {
                    try? await Task.sleep(for: .seconds(10))
                    if !Task.isCancelled, presence.note == note { presence.dismiss() }
                }
                #if GF_DEMO
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { GFDemo.logBanner($0) }
                #endif
            }
        }

        /// How far into a film or episode, round the play button.
        @ViewBuilder private func ring(_ note: GFLastPlayedNote, size: CGFloat) -> some View {
            if let progress = GFContinueArtwork.progress(note) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2)
                    Circle().trim(from: 0, to: progress)
                        .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)
            }
        }
    }
#endif

extension View {
    /// The continue banner in the tab bar's accessory place of a `TabView` with no Chromecast mini player (the demo's;
    /// the app's comes with Lume's `castMiniController`).
    @ViewBuilder func gfContinueAccessory() -> some View {
        #if os(iOS)
            if #available(iOS 26.1, *) {
                tabViewBottomAccessory(isEnabled: GFContinueBannerPresence.shared.isShowing) { GFContinueAccessory() }
            } else {
                self
            }
        #else
            self
        #endif
    }
}

/// What the continue banner offers while it shows: the tab bar's accessory draws it from here, and the Apple TV's
/// tab view, which opens Lume's playlist switcher on Play/Pause and sits nearer the focus than the banner's own
/// handler (Georgs, 1 Nov), leaves Play/Pause to the banner while `isShowing`.
@MainActor
@Observable
final class GFContinueBannerPresence {
    static let shared = GFContinueBannerPresence()
    private(set) var note: GFLastPlayedNote?
    private(set) var shownAt = Date()
    @ObservationIgnored private var onPlay: () -> Void = {}
    @ObservationIgnored private var onDismiss: () -> Void = {}

    var isShowing: Bool {
        note != nil
    }

    private init() {}

    func show(_ note: GFLastPlayedNote?, at shownAt: Date, onPlay: @escaping () -> Void,
              onDismiss: @escaping () -> Void) {
        self.note = note
        self.shownAt = shownAt
        self.onPlay = onPlay
        self.onDismiss = onDismiss
    }

    func play() {
        onPlay()
    }

    func dismiss() {
        onDismiss()
    }
}

/// At the app's root: refreshes when the app comes to the front, shows the banner for ten seconds (iPhone/iPad: above
/// the tab bar, tap or swipe down, before iOS 26.1 at the top, swipe up; Apple TV: top right, Play/Pause), and opens
/// the player. Never on a child profile: the note can be
/// a grown-up's channel.
private struct GFContinueBannerHost: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ProfileManager.self) private var profileManager: ProfileManager?
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
            .onChange(of: model?.offered, initial: true) { publish() }
    }

    /// Hands the offer to the tab bar's accessory (and the Apple TV's Play/Pause).
    private func publish() {
        #if GF_DEMO
            if GFDemo.mode == "banner" { return } // the demo shows its own (GFDemoRoot)
        #endif
        withAnimation(.smooth) {
            GFContinueBannerPresence.shared.show(model?.offered, at: shownAt, onPlay: play, onDismiss: dismiss)
        }
    }

    /// The banner over the app: the Apple TV's, and the iPhone's and iPad's before iOS 26.1.
    @ViewBuilder private var banner: some View {
        if !GFContinueBannerLayout.usesTabAccessory, let note = model?.offered {
            GFContinueBannerView(note: note, now: shownAt, onPlay: play)
                .padding(GFContinueBannerLayout.padding)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gfBannerGestures(onTap: play, onSwipeUp: dismiss)
                .task(id: note.updatedAt) {
                    try? await Task.sleep(for: .seconds(10))
                    if !Task.isCancelled, model?.offered == note { dismiss() }
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
        publish() // an offer still standing gets the new "minutes ago"
    }

    private func play() {
        let selectedID = UserDefaults.standard.string(forKey: PlaylistSelectionStore.key) ?? ""
        guard let media = model?.media(selectedID: selectedID) else {
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
    /// iPhone and iPad before iOS 26.1: tap to play, swipe up to dismiss (the Apple TV uses Play/Pause).
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
