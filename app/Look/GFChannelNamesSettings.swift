import SwiftUI

private let gfChannelNamesFooter: LocalizedStringKey =
    "“BBC One FHD” shows as “BBC One” with a small FHD badge, and live events get a LIVE badge. Search still finds the full names."

/// iPhone/iPad (Form): Settings → TV Guide → Channel Names.
struct GFChannelNamesSection: View {
    @AppStorage(GFChannelNames.settingKey) private var enabled = true

    var body: some View {
        Section {
            Toggle("Clean Channel Names", isOn: $enabled)
        } header: {
            Text("Channel Names")
        } footer: {
            Text(gfChannelNamesFooter)
        }
    }
}

#if os(tvOS)
    /// Apple TV: Settings → TV Guide → Channel Names, one row that switches on and off.
    struct GFChannelNamesTVSection: View {
        @AppStorage(GFChannelNames.settingKey) private var enabled = true

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVSettingsSectionLabel("Channel Names")

                Button {
                    enabled.toggle()
                } label: {
                    HStack(spacing: 16) {
                        Text("Clean Channel Names")
                        Spacer(minLength: 0)
                        Text(enabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(TVSettingsRowButtonStyle())

                Text(gfChannelNamesFooter)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            }
        }
    }
#endif
