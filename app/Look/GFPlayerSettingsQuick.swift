import SwiftUI

// Lume GF: the player options changed most, one step away (Georgs, 10 Nov 2026: "the player settings right now ... you
// need to go through like 3-4 menus"). The same settings as Lume's own pages, so nothing is reset or moved in storage:
// - the player's gear: a menu of them while watching (GFPlayerSettingsItems; iPhone/iPad GFPlayerSettingsButton, the
//   Apple TV overlay draws its own circle around the same items)
// - Settings › Player: KSPlayer's live buffer and decoding first (GFKSPlayerQuickSection, GFKSPlayerQuickTVRows)
// - Settings › Live TV: what the player does with live channels (GFLiveTVWatchingSection, GFLiveTVWatchingTVRows)

/// Where Lume GF keeps its own settings' places.
enum GFSettingsPlace {
    /// Apple TV: the Settings section last opened, where Settings opens again.
    static let lastCategoryKey = "gf.settings.lastCategory"
}

/// The gear's menu: buffer and decoding for the next channel, the rest at once.
struct GFPlayerSettingsItems: View {
    @AppStorage(PlayerSettings.KSPlayer.liveBufferKey) private var liveBuffer = PlayerSettings.KSPlayer.liveBufferDefault
    @AppStorage(PlayerSettings.KSPlayer.hardwareDecodeKey)
    private var hardwareDecode = PlayerSettings.KSPlayer.hardwareDecodeDefault
    @AppStorage(PlayerSettings.Playback.liveQualitySwitchKey)
    private var qualitySwitch = PlayerSettings.Playback.liveQualitySwitchDefault
    @AppStorage(PlayerSettings.StreamInfo.enabledKey) private var streamInfoOn = PlayerSettings.StreamInfo.enabledDefault
    @AppStorage(PlayerSettings.StreamInfo.detailLevelKey)
    private var streamInfoLevel = PlayerSettings.StreamInfo.detailLevelDefault.rawValue
    #if os(tvOS)
        @AppStorage(GFEnhancePlan.settingKey) private var enhance = false
        @AppStorage(PlayerSettings.liveSurfModeKey) private var surfMode = LiveSurfMode.default.rawValue
    #endif
    /// iPhone/iPad: the whole Player page, for what the menu leaves out.
    var onAllSettings: (() -> Void)?

    var body: some View {
        Section("From the Next Channel") {
            Picker(selection: $liveBuffer) {
                ForEach(KSBufferPreset.values, id: \.self) { Text(KSBufferPreset.label($0)).tag($0) }
            } label: {
                Label("Live Buffer", systemImage: "timer")
            }
            .pickerStyle(.menu)
            Toggle(isOn: $hardwareDecode) { Label("Hardware Decoding", systemImage: "cpu") }
            #if os(tvOS)
                Toggle(isOn: $enhance) { Label("Enhance SD & 720p", systemImage: "wand.and.stars") }
            #endif
        }
        Section {
            Picker(selection: streamInfo) {
                #if !os(tvOS)
                    Text("Off").tag("")
                #endif
                ForEach(StreamInfoDetailLevel.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                Label("Stream Information", systemImage: "info.circle")
            }
            .pickerStyle(.menu)
            Toggle(isOn: $qualitySwitch) { Label("Show Quality Switch", systemImage: "sparkles.tv") }
            #if os(tvOS)
                Picker(selection: $surfMode) {
                    ForEach(LiveSurfMode.allCases) { Text($0.displayName).tag($0.rawValue) }
                } label: {
                    Label("Channel Surfing", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
            #endif
        }
        if let onAllSettings {
            Section {
                Button(action: onAllSettings) { Label("All Player Settings…", systemImage: "gearshape.2") }
            }
        }
    }

    /// iPhone/iPad: Off and the two levels in one choice (Lume's page has a switch and a picker); Apple TV has no
    /// switch, only the level.
    private var streamInfo: Binding<String> {
        Binding(
            get: {
                #if os(tvOS)
                    streamInfoLevel
                #else
                    streamInfoOn ? streamInfoLevel : ""
                #endif
            },
            set: { value in
                if value.isEmpty {
                    streamInfoOn = false
                } else {
                    streamInfoOn = true
                    streamInfoLevel = value
                }
            }
        )
    }
}

#if os(tvOS)

    /// Settings › Player, first: KSPlayer's options changed most. "All KSPlayer Options" follows in the pane itself.
    struct GFKSPlayerQuickTVRows: View {
        @AppStorage(PlayerSettings.KSPlayer.liveBufferKey) private var liveBuffer = PlayerSettings.KSPlayer.liveBufferDefault
        @AppStorage(PlayerSettings.KSPlayer.hardwareDecodeKey)
        private var hardwareDecode = PlayerSettings.KSPlayer.hardwareDecodeDefault
        @AppStorage(GFEnhancePlan.settingKey) private var enhance = false

        var body: some View {
            TVSettingsSectionLabel("KSPlayer")
            TVOptionCycleRow(title: "Live Buffer", valueLabel: KSBufferPreset.label(liveBuffer)) {
                liveBuffer = PlayerOptionCycle.next(liveBuffer, in: KSBufferPreset.values)
            }
            TVOptionToggleRow(title: "Hardware Decoding", isOn: $hardwareDecode)
            TVOptionToggleRow(title: "Enhance SD & 720p", isOn: $enhance)
        }
    }

    /// Settings › Live TV: how the player changes channels and offers other qualities.
    struct GFLiveTVWatchingTVRows: View {
        @AppStorage(PlayerSettings.liveSurfModeKey) private var surfMode = LiveSurfMode.default.rawValue
        @AppStorage(PlayerSettings.Playback.liveQualitySwitchKey)
        private var qualitySwitch = PlayerSettings.Playback.liveQualitySwitchDefault

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("While Watching")
                TVOptionCycleRow(title: "Channel Surfing", valueLabel: LiveSurfMode.resolve(surfMode).displayName) {
                    let modes = LiveSurfMode.allCases
                    let index = modes.firstIndex(of: LiveSurfMode.resolve(surfMode)) ?? 0
                    surfMode = modes[(index + 1) % modes.count].rawValue
                }
                footer("Up and down move to the next and previous channel, like a TV remote. List Order moves the way the channel list reads on screen instead — up goes to the row above.")
                TVOptionToggleRow(title: "Show Quality Switch", isOn: $qualitySwitch)
                footer("While watching a live channel, switch to the same channel in another quality, such as HD, FHD or 4K, when your playlist lists it more than once.")
            }
        }

        private func footer(_ text: LocalizedStringKey) -> some View {
            Text(text)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                .padding(.top, 6)
        }
    }

#else

    /// The gear in the player's glass pill (beside Sources, Quality and Record).
    struct GFPlayerSettingsButton: View {
        var onResetHideTimer: () -> Void
        @State private var showsAll = false

        var body: some View {
            Menu {
                GFPlayerSettingsItems(onAllSettings: { showsAll = true })
                    .holdsPlayerControls()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Player Settings")
            .help("Player Settings")
            .sheet(isPresented: $showsAll, onDismiss: onResetHideTimer) {
                NavigationStack {
                    PlayerSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsAll = false }
                            }
                        }
                }
            }
        }
    }

    /// Settings › Player, first: KSPlayer's options changed most.
    struct GFKSPlayerQuickSection: View {
        @AppStorage(PlayerSettings.KSPlayer.liveBufferKey) private var liveBuffer = PlayerSettings.KSPlayer.liveBufferDefault
        @AppStorage(PlayerSettings.KSPlayer.hardwareDecodeKey)
        private var hardwareDecode = PlayerSettings.KSPlayer.hardwareDecodeDefault

        var body: some View {
            Section {
                Picker("Live Buffer", selection: $liveBuffer) {
                    ForEach(KSBufferPreset.values, id: \.self) { Text(KSBufferPreset.label($0)).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("Hardware Decoding", isOn: $hardwareDecode)
                NavigationLink("All KSPlayer Options") { KSEngineSettingsScreen() }
            } header: {
                Text("KSPlayer")
            } footer: {
                Text("Applied the next time a channel or film starts. The gear in the player has these too.")
            }
        }
    }

    /// Settings › Live TV: what the player offers on a live channel.
    struct GFLiveTVWatchingSection: View {
        @AppStorage(PlayerSettings.Playback.liveQualitySwitchKey)
        private var qualitySwitch = PlayerSettings.Playback.liveQualitySwitchDefault

        var body: some View {
            Section {
                Toggle("Show Quality Switch", isOn: $qualitySwitch)
            } header: {
                Text("While Watching")
            } footer: {
                Text("While watching a live channel, switch to the same channel in another quality, such as HD, FHD or 4K, when your playlist lists it more than once.")
            }
        }
    }

#endif
