#if os(iOS)
    import Foundation
    import SwiftData

    /// Lume GF: what the CarPlay and HomeView screens list (GFCarPlaySceneDelegate). The same channels Live TV shows: the
    /// selected playlist (or Combined), no hidden channels or groups, and a child profile kept out of restricted groups.
    /// Read from the catalog store outside SwiftUI, so it rebuilds the scope and the restriction the browse screens get
    /// from their environment.
    @MainActor
    enum GFCarPlayCatalog {
        /// Set at launch (LumeApp.init), before any scene can connect.
        static var catalogContainer: ModelContainer?
        static var cloudContainer: ModelContainer?

        /// One row: what the list shows and what playing it needs. Built on the main actor from a fetch and never
        /// holds the model object, so a sync that replaces the channel underneath can't leave a list on a deleted row.
        struct Channel {
            let id: String
            let title: String
            let logoURL: URL?
            let epgChannelID: String?
            /// What Apple's player opens; nil when the channel can't play there (the row then says so up front).
            let hlsURL: URL?
        }

        struct Group {
            let id: String
            let name: String
        }

        static func favourites(limit: Int) -> [Channel] {
            channels(.favorites, limit: limit)
        }

        static func recentlyWatched(limit: Int) -> [Channel] {
            channels(.recentlyWatched, limit: limit)
        }

        static func channels(inGroup id: String, limit: Int) -> [Channel] {
            channels(.category(id), limit: limit)
        }

        static func groups(limit: Int) -> [Group] {
            guard let context else { return [] }
            let live = (try? context.fetch(FetchDescriptor<Category>(
                predicate: #Predicate { $0.typeRaw == "live" && $0.isHidden == false }
            ))) ?? []
            let visible = LiveChannelQuery.visibleCategories(live, catalogScope: scope(in: context),
                                                             restriction: restriction(in: context))
            let order = CategorySortOption(rawValue: UserDefaults.standard.string(forKey: SortStorageKey.liveCategories)
                ?? "") ?? .playlist
            return order.sort(visible).prefix(limit).map { Group(id: $0.id, name: $0.name) }
        }

        /// The programme on now per channel, keyed by the channel's guide id.
        static func nowTitles(for channels: [Channel]) -> [String: String] {
            guard let context else { return [:] }
            let ids = channels.compactMap(\.epgChannelID)
            guard !ids.isEmpty else { return [:] }
            let now = Date()
            var descriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { ids.contains($0.channelId) && $0.start <= now && $0.end > now }
            )
            descriptor.propertiesToFetch = [\.channelId, \.title]
            let listings = (try? context.fetch(descriptor)) ?? []
            return Dictionary(listings.map { ($0.channelId, $0.title) }, uniquingKeysWith: { first, _ in first })
        }

        /// The address Apple's player opens: the channel through Dispatcharr's own HLS output. An Xtream playlist's
        /// `.m3u8` makes Dispatcharr segment the stream it already fetches (its stream_xc picks the output from the
        /// extension), so the car is one more viewer of the same provider line, not a second fetch. AVPlayer can't
        /// open the `.ts` the app's own player uses. An m3u playlist gets the same swap only on an Xtream-style
        /// `/live/.../<id>.ts` address; a Stalker channel (no fixed address) or any other shape: none.
        private static func hlsURL(for stream: LiveStream, playlist: Playlist) -> URL? {
            switch playlist.sourceType {
            case .stalker:
                return nil
            case .xtream:
                return XtreamClient().buildLiveStreamURL(for: stream, playlist: playlist, format: .m3u8)
            default:
                guard let url = LiveStreamURLResolver.playbackURL(for: stream, playlist: playlist),
                      !LiveStreamURLResolver.needsTapTimeResolution(url) else { return nil }
                switch url.pathExtension.lowercased() {
                case "m3u8": return url
                case "ts" where url.path.contains("/live/"):
                    return url.deletingPathExtension().appendingPathExtension("m3u8")
                default: return nil
                }
            }
        }

        /// Stamps the channel as watched, so it leads Recently Watched here and in the app (synced like the app's own).
        static func markWatched(channelID id: String) {
            guard let context, let stream = stream(id: id, in: context) else { return }
            stream.lastWatchedDate = Date()
            try? context.save()
        }

        // MARK: - Private

        private static var context: ModelContext? {
            catalogContainer.map(ModelContext.init)
        }

        private static func stream(id: String, in context: ModelContext) -> LiveStream? {
            var descriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try? context.fetch(descriptor).first
        }

        private static func channels(_ listScope: LiveChannelScope, limit: Int) -> [Channel] {
            guard let context else { return [] }
            let sort = ContentSortOption(rawValue: UserDefaults.standard.string(forKey: SortStorageKey.liveContent)
                ?? "") ?? .playlist
            var descriptor = LiveChannelQuery.descriptor(for: listScope, sort: sort)
            // a group is one playlist's and a child's restriction removes the whole group, so its first `limit` rows
            // are the ones shown (a big group would otherwise load every channel on each tap)
            if case .category = listScope { descriptor.fetchLimit = limit }
            let streams = (try? context.fetch(descriptor)) ?? []
            let visible = LiveChannelQuery.scoped(streams, scope: listScope, catalogScope: scope(in: context),
                                                  restriction: restriction(in: context))
            let playlists = Dictionary(((try? context.fetch(FetchDescriptor<Playlist>())) ?? []).map { ($0.id, $0) },
                                       uniquingKeysWith: { first, _ in first })
            return visible.prefix(limit).map { stream in
                let playlist = PlaylistOwner.declaredOwner(of: stream.id).flatMap { playlists[$0] }
                return Channel(id: stream.id, title: GFChannelNames.title(for: stream.name),
                               logoURL: stream.streamIcon.flatMap(URL.init(string:)), epgChannelID: stream.epgChannelId,
                               hlsURL: playlist.flatMap { hlsURL(for: stream, playlist: $0) })
            }
        }

        /// The playlist selection Live TV browses (PlaylistSwitcher), resolved as the app does.
        private static func scope(in context: ModelContext) -> CatalogScope {
            let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
            return playlists.scope(for: UserDefaults.standard.string(forKey: PlaylistSelectionStore.key),
                                   isPremium: PremiumManager.shared.isPremium)
        }

        /// Hidden groups for everyone, restricted ones too for a child profile (ContentRestrictionProvider's rule).
        private static func restriction(in context: ModelContext) -> ContentRestriction {
            let hidden = (try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.isHidden }))) ?? []
            let restricted = (try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.isRestricted })))
                ?? []
            return ContentRestriction(isActive: activeProfileIsChild,
                                      restrictedCategoryIDs: Set(restricted.map(\.id)),
                                      hiddenCategoryIDs: Set(hidden.map(\.id)))
        }

        /// As the app: no active profile, or one not stored, is not a child's; a store that can't be read counts as a
        /// child's, so the car shows less rather than a locked group.
        private static var activeProfileIsChild: Bool {
            guard let id = ActiveProfileStore.current else { return false }
            guard let cloudContainer else { return true }
            var descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let profiles = try? ModelContext(cloudContainer).fetch(descriptor) else { return true }
            return profiles.first?.isChild ?? false
        }
    }
#endif
