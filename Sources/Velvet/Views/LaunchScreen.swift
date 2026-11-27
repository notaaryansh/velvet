import SwiftUI

/// Launch screen: dark backdrop with the app icon centered, its waves
/// gently animating while the app preloads. MainView crossfades it away
/// once everything is warm.
struct LaunchWaves: View {
    var body: some View {
        ZStack {
            Color(hex: 0x120A0E)

            // The icon tile, alive.
            animatedIcon
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 28, y: 10)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)   // swallow clicks while loading
    }

    private var animatedIcon: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                // Backdrop: the icon's warm near-black.
                let bg = Path(CGRect(origin: .zero, size: size))
                ctx.fill(bg, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x221219), Color(hex: 0x140A0F)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                func crest(_ f: CGFloat, base: CGFloat, a1: CGFloat, a2: CGFloat,
                           speed: Double, p1: Double, p2: Double) -> CGFloat {
                    base * size.height
                        + sin(f * .pi * 1.35 + CGFloat(t * speed + p1)) * a1
                        + sin(f * .pi * 3.1 + CGFloat(t * speed * 0.7 + p2)) * a2
                }

                // One opaque layer: crest down to the bottom, like the icon.
                func layer(base: CGFloat, a1: CGFloat, a2: CGFloat, speed: Double,
                           p1: Double, p2: Double, top: UInt32, bottom: UInt32,
                           hairline: Bool = false) {
                    let steps = 72
                    var p = Path()
                    var line = Path()
                    p.move(to: CGPoint(x: 0, y: size.height))
                    for i in 0...steps {
                        let f = CGFloat(i) / CGFloat(steps)
                        let pt = CGPoint(x: f * size.width,
                                         y: crest(f, base: base, a1: a1, a2: a2,
                                                  speed: speed, p1: p1, p2: p2))
                        p.addLine(to: pt)
                        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                    }
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .linearGradient(
                        Gradient(colors: [Color(hex: top), Color(hex: bottom)]),
                        startPoint: CGPoint(x: size.width / 2, y: base * size.height - a1 - a2),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)))
                    if hairline {
                        ctx.stroke(line, with: .color(Color(hex: 0xE3A7C0).opacity(0.85)),
                                   lineWidth: 1.5)
                    }
                }

                // Same stack as the icon, breathing slowly. Amplitudes are
                // scaled for the small tile.
                let a = size.height / 1024 * 4.2
                layer(base: 0.46, a1: 17 * a, a2: 6 * a, speed: 0.55, p1: 0.8, p2: 2.1,
                      top: 0xA84860, bottom: 0x8C1F3C, hairline: true)
                layer(base: 0.60, a1: 20 * a, a2: 7 * a, speed: 0.42, p1: 2.9, p2: 0.4,
                      top: 0x8C1F3C, bottom: 0x62102C)
                layer(base: 0.74, a1: 16 * a, a2: 6 * a, speed: 0.50, p1: 5.1, p2: 3.6,
                      top: 0x5A0A24, bottom: 0x3C0317)
                layer(base: 0.87, a1: 13 * a, a2: 5 * a, speed: 0.36, p1: 1.7, p2: 5.2,
                      top: 0x33020F, bottom: 0x24010B)
            }
        }
    }
}
