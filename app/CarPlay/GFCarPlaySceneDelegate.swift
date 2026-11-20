#if os(iOS) && canImport(CarPlay)
    import CarPlay
    import UIKit

    /// Lume GF: Lume GF on CarPlay and Apple HomeView, which shows CarPlay video apps as they are
    /// (developer.apple.com/documentation/carplay/video). Three tabs built from CarPlay's own templates: Favourites,
    /// Recently Watched and the channel groups. Picking a channel plays it in Apple's video player (GFCarPlayPlayer).
    /// Connected by LumeAppDelegate for the CarPlay scene role; shows only with Apple's CarPlay video entitlement.
    final class GFCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
        private var interfaceController: CPInterfaceController?
        private var logoTasks: [Task<Void, Never>] = []

        /// Logos at the size CarPlay draws list images (about 44-60 pt at 3x).
        private static let logoPixels: CGFloat = 180

        func templateApplicationScene(
            _: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController
        ) {
            self.interfaceController = interfaceController
            let tabs = CPTabBarTemplate(templates: [favouritesTab(), recentTab(), groupsTab()])
            interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        }

        func templateApplicationScene(
            _: CPTemplateApplicationScene,
            didDisconnect _: CPInterfaceController
        ) {
            logoTasks.forEach { $0.cancel() }
            logoTasks = []
            interfaceController = nil
            GFCarPlayPlayer.shared.stop()
        }

        // MARK: - Tabs

        private func favouritesTab() -> CPListTemplate {
            let template = channelList(
                title: String(localized: "Favorites"),
                channels: GFCarPlayCatalog.favourites(limit: CPListTemplate.maximumItemCount),
                empty: String(localized: "No favourite channels yet. Add some in Live TV on your iPhone.")
            )
            template.tabImage = UIImage(systemName: "star.fill")
            return template
        }

        private func recentTab() -> CPListTemplate {
            let template = channelList(
                title: String(localized: "Recently Watched"),
                channels: GFCarPlayCatalog.recentlyWatched(limit: CPListTemplate.maximumItemCount),
                empty: String(localized: "Channels you watch show up here.")
            )
            template.tabImage = UIImage(systemName: "clock.arrow.circlepath")
            return template
        }

        private func groupsTab() -> CPListTemplate {
            let rows = GFCarPlayCatalog.groups(limit: CPListTemplate.maximumItemCount).map { group in
                let item = CPListItem(text: group.name, detailText: nil)
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, completion in
                    self?.openGroup(group)
                    completion()
                }
                return item
            }
            let template = CPListTemplate(title: String(localized: "Channels"), sections: [CPListSection(items: rows)])
            template.emptyViewSubtitleVariants = [String(localized: "No channel groups yet. Open Lume GF on your iPhone.")]
            template.tabImage = UIImage(systemName: "list.bullet")
            return template
        }

        private func openGroup(_ group: GFCarPlayCatalog.Group) {
            let template = channelList(
                title: group.name,
                channels: GFCarPlayCatalog.channels(inGroup: group.id, limit: CPListTemplate.maximumItemCount),
                empty: String(localized: "No channels in this group.")
            )
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }

        // MARK: - Channel lists

        /// A list of channels with the programme on now under each name. Each row asks the system for its video
        /// player (`.video`), then starts the channel in GFCarPlayPlayer.
        private func channelList(title: String, channels: [GFCarPlayCatalog.Channel], empty: String) -> CPListTemplate {
            let now = GFCarPlayCatalog.nowTitles(for: channels)
            let rows = channels.map { channel in
                let programme = channel.epgChannelID.flatMap { now[$0] }
                let item = CPListItem(text: channel.title, detailText: programme,
                                      image: UIImage(systemName: "tv"))
                item.playbackConfiguration = CPPlaybackConfiguration(
                    preferredPresentation: .video, playbackAction: .play,
                    elapsedTime: .zero, duration: .indefinite
                )
                item.handler = { [weak self] _, completion in
                    self?.play(channel, programme: programme)
                    completion()
                }
                loadLogo(channel.logoURL, into: item)
                return item
            }
            let template = CPListTemplate(title: title, sections: [CPListSection(items: rows)])
            template.emptyViewSubtitleVariants = [empty]
            return template
        }

        private func play(_ channel: GFCarPlayCatalog.Channel, programme: String?) {
            guard !GFCarPlayPlayer.shared.play(channel, programme: programme) else { return }
            let alert = CPAlertTemplate(
                titleVariants: [String(localized: "This channel can't play here. Watch it on your iPhone.")],
                actions: [CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                    self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
                }]
            )
            interfaceController?.presentTemplate(alert, animated: true, completion: nil)
        }

        private func loadLogo(_ url: URL?, into item: CPListItem) {
            guard let url else { return }
            if let cached = ImagePipeline.cachedImage(for: url, maxPixelSize: Self.logoPixels) {
                item.setImage(cached)
                return
            }
            logoTasks.append(Task { [weak item] in
                guard let image = try? await ImagePipeline.shared.image(for: url, maxPixelSize: Self.logoPixels),
                      !Task.isCancelled else { return }
                item?.setImage(image)
            })
        }
    }
#endif
