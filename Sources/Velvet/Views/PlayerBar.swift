import SwiftUI

/// Bottom transport bar, Apple Music / Kaset style: compact art + titles on
/// the left, centered now-playing capsule with transport and inline scrubber,
/// PiP on the right. Vibrant backing, hairline top divider.
struct PlayerBar: View {
    @State private var player = PlayerService.shared
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            HStack(spacing: 14) {
                nowPlaying
                    .frame(width: 240, alignment: .leading)

                transport

                centerScrubber
                    .frame(maxWidth: 420)

                Spacer(minLength: 8)

                volumeControl

                Button {
                    PiPController.shared.toggle()
                } label: {
                    Image(systemName: "pip")
                        .font(.system(size: 15))
                        .foregroundStyle(PiPController.shared.isVisible ? Velvet.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help("Picture in Picture")
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
        }
        // Fully transparent: the velvet wave backdrop shows through; only a
        // hairline divider separates the bar from the content.
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Artwork(url: player.current?.art(120)) {
                Rectangle().fill(Velvet.artPlaceholder)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 14)).foregroundStyle(.tertiary))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.1)))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "Not Playing")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(player.current == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text(player.adPlaying
                     ? "Advertisement"
                     : (player.current?.artist ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(player.adPlaying ? Velvet.accent : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Button {
                player.setVolume(player.volume > 0 ? 0 : 1)
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Scrubber(progress: player.volume) { frac in
                player.setVolume(frac)
            } onCommit: { frac in
                player.setVolume(frac)
            }
            .frame(width: 70)
        }
    }

    private var volumeIcon: String {
        if player.volume <= 0 { return "speaker.slash.fill" }
        if player.volume < 0.4 { return "speaker.wave.1.fill" }
        if player.volume < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var transport: some View {
        HStack(spacing: 20) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)

            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(!player.hasNext)
        }
        .foregroundStyle(player.current == nil ? .tertiary : .primary)
    }

    private var centerScrubber: some View {
        TimelineView(.periodic(from: .now, by: player.isPlaying ? 0.3 : 3600)) { _ in
            let live = scrubbing ? scrubValue : player.liveProgress
            HStack(spacing: 8) {
                Text(timeString(live))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)

                Scrubber(progress: player.duration > 0 ? live / player.duration : 0) { frac in
                    scrubbing = true
                    scrubValue = frac * max(player.duration, 1)
                } onCommit: { frac in
                    scrubbing = false
                    player.seek(to: frac * max(player.duration, 1))
                }

                Text("-" + timeString(max(player.duration - live, 0)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .leading)
            }
        }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Thin Apple Music-style scrubber: a slim track that thickens on hover.
struct Scrubber: View {
    let progress: Double
    let onDrag: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                    .frame(height: hovering ? 5 : 3.5)
                Capsule().fill(Color.primary.opacity(0.55))
                    .frame(width: max(w * clamped, 2), height: hovering ? 5 : 3.5)
                if hovering {
                    Circle().fill(.white)
                        .frame(width: 11, height: 11)
                        .shadow(radius: 1, y: 0.5)
                        .offset(x: w * clamped - 5.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onDrag(min(max(v.location.x / w, 0), 1)) }
                    .onEnded { v in onCommit(min(max(v.location.x / w, 0), 1)) }
            )
        }
        .frame(height: 16)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
