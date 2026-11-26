import SwiftUI

// MARK: - Track list (Apple Music style)

struct TrackList: View {
    let tracks: [Track]
    let title: String
    var subtitle: String?
    let emptyIcon: String
    let emptyTitle: String
    let emptyText: String
    var error: String?
    var onReload: (() -> Void)?

    var body: some View {
        if let error {
            StateMessage(icon: "exclamationmark.triangle",
                         title: "Something went wrong",
                         text: error,
                         action: onReload.map { ("Try Again", $0) })
        } else if tracks.isEmpty {
            StateMessage(icon: emptyIcon, title: emptyTitle, text: emptyText, action: nil)
        } else {
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Large page header
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 26, weight: .bold))
                            if let subtitle {
                                Text(subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            PlayerService.shared.play(tracks: tracks, at: 0)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 10))
                                Text("Play").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Velvet.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Velvet.accent.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, tracks.isEmpty ? 0 : 4)
                    .padding(.bottom, 10)

                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                        TrackRow(track: track, number: i + 1) {
                            PlayerService.shared.play(tracks: tracks, at: i)
                        }
                        .onAppear {
                            // Keep the artwork window warm ~25 rows ahead in
                            // both directions so fast scrolling never catches
                            // an unloaded thumbnail.
                            let ahead = tracks[i..<min(i + 25, tracks.count)]
                            let behind = tracks[max(0, i - 25)..<i]
                            ArtworkCache.shared.prefetch((ahead + behind).map { $0.art(96) })
                        }
                        if i < tracks.count - 1 {
                            Divider()
                                .padding(.leading, 84)
                                .opacity(0.4)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

struct StateMessage: View {
    let icon: String
    let title: String
    let text: String
    let action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Track row

struct TrackRow: View {
    let track: Track
    let number: Int
    let onPlay: () -> Void

    @State private var hovering = false
    @State private var player = PlayerService.shared
    @State private var likes = LikesStore.shared

    private var isCurrent: Bool { player.current?.id == track.id }
    private var isLiked: Bool { likes.isLiked(track.id) }

    var body: some View {
        HStack(spacing: 12) {
            // Index / equalizer
            ZStack {
                if isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Velvet.accent)
                } else if hovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, design: .default))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 22)

            // Artwork
            Artwork(url: track.art(96)) {
                Rectangle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 14)).foregroundStyle(.tertiary))
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.08)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCurrent ? Velvet.accent : .primary)
                        .lineLimit(1)
                    if let plays = track.plays {
                        Text(plays)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                Text(track.artist)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Like: appears on hover, stays visible once liked.
            if hovering || isLiked {
                Button {
                    Task { await likes.toggle(track) }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(isLiked ? AnyShapeStyle(Velvet.accent) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(isLiked ? "Remove from Liked Songs" : "Add to Liked Songs")
            }

            Text(track.durationText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .background(hovering ? Velvet.rowHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture(perform: onPlay)
    }
}
