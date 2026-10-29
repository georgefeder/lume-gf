import SwiftData
import SwiftUI

/// A guide programme search found, at one airing, with the channel that carries it (Georgs, 8 Oct: searching "Shark
/// Tank", when and where will it air?). One on now plays its channel; a later one opens the programme's card (Lume 2.4:
/// record it from there).
struct GFProgrammeRow: Identifiable {
    let hit: GFGuideSearchHit
    let stream: LiveStream
    var id: String {
        hit.listingID + "|" + stream.id
    }
}

/// A later programme's card, open over search.
struct GFProgrammeSelection: Identifiable {
    let id: String
    let stream: LiveStream
    let cell: EPGProgramCell

    init(_ row: GFProgrammeRow) {
        let hit = row.hit
        id = row.id
        stream = row.stream
        cell = EPGProgramCell(id: hit.listingID, title: hit.title, detail: hit.detail, start: hit.start, end: hit.end,
                              listingID: hit.listingID, isGap: false, width: 0)
    }
}

/// A programme found: its title (and episode), on now or when it airs, and the channel.
struct GFGuideSearchRow: View {
    let hit: GFGuideSearchHit
    let stream: LiveStream
    let now: Date

    private var logoSide: CGFloat {
        GFGuideGlass.isTV ? 66 : 44
    }

    var body: some View {
        HStack(spacing: 12) {
            EPGLogoTile(url: URL(string: stream.streamIcon ?? ""), side: logoSide, cornerRadius: logoSide * 0.26,
                        padding: logoSide * 0.11, glyphSize: logoSide * 0.39)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: hit.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = hit.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if hit.isLive(at: now) {
                        LiveBadge()
                        Text(verbatim: GFChannelNames.title(for: stream.name))
                    } else {
                        Text(verbatim: GFGuideSearch.whenLabel(start: hit.start, end: hit.end, now: now,
                                                               calendar: .current, locale: .current)
                            + " · " + GFChannelNames.title(for: stream.name))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
