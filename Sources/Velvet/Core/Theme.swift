import SwiftUI
import AppKit

// MARK: - Palette (Apple Music / Kaset-style: neutral dark, one warm accent)

enum Velvet {
    static let accent   = Color(hex: 0xFC3C44)   // Apple Music red
    static let accentDim = Color(hex: 0xC4303A)
    static let text     = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let rowHover  = Color.primary.opacity(0.06)
    static let artPlaceholder = Color(nsColor: .quaternaryLabelColor)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Native vibrancy backing

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
