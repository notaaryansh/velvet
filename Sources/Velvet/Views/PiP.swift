import SwiftUI
import AppKit
import Observation

/// Floating always-on-top panel: just the artwork and mini controls.
@MainActor
@Observable
final class PiPController {
    static let shared = PiPController()

    var isVisible = false
    @ObservationIgnored private var panel: NSPanel?

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 264, height: 264),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: PiPView())

            // Bottom-right of the main screen by default.
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 290, y: f.minY + 26))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }
}

/// A transparent NSView that lets the user drag the panel by clicking and
/// dragging anywhere on it. `NSPanel.isMovableByWindowBackground` alone is
/// unreliable once the content view is an `NSHostingView` hosting SwiftUI
/// content, so we drive the drag explicitly via `NSWindow.performDrag`.
/// SwiftUI only routes an event here when no interactive subview (e.g. a
/// `Button`) claims it first, so the transport controls stay clickable.
private final class DraggableBackgroundView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableBackgroundView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PiPView: View {
    @State private var player = PlayerService.shared
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Artwork
            Group {
                if let track = player.current {
                    AsyncImage(url: track.art(544)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(Velvet.artPlaceholder)
                        }
                    }
                } else {
                    ZStack {
                        Rectangle().fill(Velvet.artPlaceholder)
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 264, height: 264)

            // Hover controls
            if hovering {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text(player.current?.title ?? "—")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(player.current?.artist ?? "")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    HStack(spacing: 20) {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill").font(.system(size: 13, weight: .bold))
                        }
                        Button { player.togglePlay() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 19, weight: .black))
                        }
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(.system(size: 13, weight: .bold))
                        }
                        Button { PiPController.shared.hide() } label: {
                            Image(systemName: "pip.exit").font(.system(size: 12, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Thin progress line at the very bottom
            GeometryReader { geo in
                Rectangle()
                    .fill(Velvet.accent)
                    .frame(width: player.duration > 0
                           ? geo.size.width * min(player.progress / player.duration, 1)
                           : 0,
                           height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
        .background(WindowDragArea())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .onHover { h in
            withAnimation(.snappy(duration: 0.2)) { hovering = h }
        }
    }
}
