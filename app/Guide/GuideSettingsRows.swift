import SwiftUI

/// iPhone/iPad (Form): the switch above Lume's refresh menu.
struct GuideFollowServerToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Every Hour, with the Server")
                Text("Checks right after the guide server's hourly update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if os(tvOS)
    /// Apple TV: the first row of the refresh choices, checked like Lume's own rows.
    struct GuideFollowServerTVRow: View {
        @Binding var isOn: Bool

        var body: some View {
            Button {
                isOn = true
            } label: {
                HStack(spacing: 16) {
                    Text("Every Hour, with the Server")
                    Spacer(minLength: 0)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .semibold))
                    }
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle())
        }
    }
#endif

/// The guide's last update, under the refresh settings.
struct GuideStatusLine: View {
    @State private var status = GuideStatus.shared

    var body: some View {
        Text(status.line)
            .task { status.reload() }
    }
}
