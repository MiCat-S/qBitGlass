import SwiftUI

struct TorrentRow: View {
    let torrent: Torrent

    var body: some View {
        let t = torrent
        VStack(alignment: .leading, spacing: 6) {
            Text(t.name)
                .font(.body.weight(.medium))
                .lineLimit(2)

            ProgressView(value: min(max(t.progress, 0), 1))
                .tint(t.state.color)

            HStack(spacing: 6) {
                Label(t.state.label, systemImage: t.state.symbol)
                    .labelStyle(TightLabelStyle())
                    .foregroundStyle(t.state.color)
                Text(Fmt.percent(t.progress))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 4)
                Text(t.progress >= 1 ? Fmt.bytes(t.size) : "\(Fmt.bytes(max(t.size - t.amountLeft, 0))) / \(Fmt.bytes(t.size))")
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)

            HStack(spacing: 10) {
                if t.dlspeed > 0 {
                    Label(Fmt.speed(t.dlspeed), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                }
                if t.upspeed > 0 {
                    Label(Fmt.speed(t.upspeed), systemImage: "arrow.up")
                        .foregroundStyle(.green)
                }
                if t.state.isDownloading, !t.state.isStopped, t.eta < 8_640_000 {
                    Label(Fmt.eta(t.eta), systemImage: "clock")
                }
                Label(Fmt.ratio(t.ratio), systemImage: "arrow.2.squarepath")
                Label("\(t.numSeeds)/\(t.numLeechs)", systemImage: "person.2")
                Spacer(minLength: 0)
            }
            .labelStyle(TightLabelStyle())
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)

            if !t.category.isEmpty || !t.tags.isEmpty || t.forceStart {
                HStack(spacing: 5) {
                    if t.forceStart {
                        Badge(text: "強制", symbol: "bolt.fill", color: Theme.accent)
                    }
                    if !t.category.isEmpty {
                        Badge(text: t.category, symbol: "folder.fill", color: .purple)
                    }
                    ForEach(t.tags.prefix(4), id: \.self) { tag in
                        Badge(text: tag, symbol: "tag.fill", color: .teal)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct Badge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(TightLabelStyle())
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}
