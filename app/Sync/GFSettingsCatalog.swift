/// Where each Lume setting syncs (spec section 3). `.tv` stands for "this kind of device" (`GFSettingsSync` maps it
/// to `tv` or `ios`). A Lume setting missing here stays on the device; `ci/settings-tripwire.sh` stops the tests when
/// a Lume release adds one.
enum GFSettingsCatalog {
    static let keys: [String: GFSettingsGroup] = {
        var map: [String: GFSettingsGroup] = [:]
        for key in everywhere { map[key] = .all }
        for key in perKind { map[key] = .tv }
        for key in deviceOnly { map[key] = .device }
        return map
    }()

    static func group(for key: String) -> GFSettingsGroup? {
        keys[key]
    }

    static let everywhere: [String] = [
        PlayerSettings.Language.preferredAudioLanguagesKey, PlayerSettings.Playback.autoPlayNextKey,
        PlayerSettings.Playback.showNextEpisodeButtonKey, PlayerSettings.Playback.showSkipIntroButtonKey,
        SortStorageKey.liveCategories, SortStorageKey.liveContent, SortStorageKey.movieCategories,
        SortStorageKey.movieContent, SortStorageKey.seriesCategories, SortStorageKey.seriesContent,
        SyncFrequency.storageKey, SyncFrequency.epgStorageKey, GuideSettings.followServerKey, GFChannelNames.settingKey,
        SportsSyncService.tabEnabledKey, SportsSyncService.hideScoresKey, RecommendationSettings.enabledKey,
        RecommendationSettings.manualRecalculationKey, SearchSettings.searchAllPlaylistsKey
    ]

    static let perKind: [String] = [
        AppAppearance.storageKey, HomeLayoutSettings.sectionOrderKey, HomeLayoutSettings.disabledSectionsKey,
        LiveTVLayoutMode.storageKey, PlayerSettings.engineKey, PlayerSettings.enginePriorityKey,
        PlayerSettings.externalPlayerKey, PlayerSettings.externalPlayerScopeKey, PlayerSettings.liveSurfModeKey,
        PlayerSettings.tvRemoteSwipesKey, PlayerSettings.deinterlaceKey, PlayerSettings.StreamInfo.enabledKey,
        PlayerSettings.StreamInfo.detailLevelKey,
        PlayerSettings.KSPlayer.accurateSeekKey, PlayerSettings.KSPlayer.adaptiveKey,
        PlayerSettings.KSPlayer.asyncDecompressionKey, PlayerSettings.KSPlayer.autoDeinterlaceKey,
        PlayerSettings.KSPlayer.autoPipKey, PlayerSettings.KSPlayer.autoRotateKey,
        PlayerSettings.KSPlayer.autoSelectSubtitleKey, PlayerSettings.KSPlayer.codecLowDelayKey,
        PlayerSettings.KSPlayer.hardwareDecodeKey, PlayerSettings.KSPlayer.liveBufferKey,
        PlayerSettings.KSPlayer.loopPlayKey, PlayerSettings.KSPlayer.maxBufferKey, PlayerSettings.KSPlayer.noBufferKey,
        PlayerSettings.KSPlayer.primaryEngineKey, PlayerSettings.KSPlayer.secondOpenKey,
        PlayerSettings.KSPlayer.systemProxyKey, PlayerSettings.KSPlayer.vodBufferKey,
        PlayerSettings.Lume.analyzeDurationKey, PlayerSettings.Lume.audioQueueDepthKey,
        PlayerSettings.Lume.deinterlaceModeKey, PlayerSettings.Lume.deinterlaceRateKey,
        PlayerSettings.Lume.hardwareDecodeKey, PlayerSettings.Lume.httpReconnectKey, PlayerSettings.Lume.ioTimeoutKey,
        PlayerSettings.Lume.liveBufferKey, PlayerSettings.Lume.probeSizeKey, PlayerSettings.Lume.stallThresholdKey,
        PlayerSettings.Lume.videoQueueDepthKey, PlayerSettings.Lume.vodBufferKey,
        PlayerSettings.VLC.clockJitterKey, PlayerSettings.VLC.clockSynchroKey, PlayerSettings.VLC.decodeThreadsKey,
        PlayerSettings.VLC.deinterlaceModeKey, PlayerSettings.VLC.dropLateFramesKey,
        PlayerSettings.VLC.hardwareDecodeKey, PlayerSettings.VLC.httpReconnectKey, PlayerSettings.VLC.liveBufferKey,
        PlayerSettings.VLC.skipFramesKey, PlayerSettings.VLC.vodBufferKey
    ]

    static let deviceOnly: [String] = [
        DownloadManager.autoDeleteKey, DownloadManager.maxConcurrentKey, PlaylistSelectionStore.key,
        ProfileSettings.askOnStartupKey, DebugLogSettings.enabledKey, "tv.quickSwitch.hintShown.v1"
    ]
}
