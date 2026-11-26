// Velvet icon — layered matte wine waves ("Gala Velvet Ribbon" palette).
// Flat paper-cut layers, tonal oxblood→wine ramp, one dusty-rose hairline,
// subtle film grain. No glows, no coral, no purple.
// Usage: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpaceCreateDeviceRGB()

func rgba(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func grad(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle); ctx.setFillColor(rgba(0x1A141C)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()

    // Backdrop: warm near-black, barely graded.
    ctx.drawLinearGradient(grad([rgba(0x221219), rgba(0x140A0F)], [0, 1]),
                           start: CGPoint(x: size/2, y: rect.maxY),
                           end: CGPoint(x: size/2, y: rect.minY), options: [])

    // Organic wave crest: base + two harmonics so it doesn't read as a sine.
    func crestY(_ t: CGFloat, base: CGFloat, a1: CGFloat, p1: CGFloat,
                a2: CGFloat, p2: CGFloat) -> CGFloat {
        base + a1 * sin(t * .pi * 1.35 + p1) + a2 * sin(t * .pi * 3.1 + p2)
    }

    // One matte layer: fill from its crest down to the tile bottom.
    func layer(base: CGFloat, a1: CGFloat, p1: CGFloat, a2: CGFloat, p2: CGFloat,
               top: UInt32, bottom: UInt32) -> [CGPoint] {
        let steps = 90
        var crest: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + rect.width * t
            crest.append(CGPoint(x: x, y: crestY(t, base: base, a1: a1, p1: p1, a2: a2, p2: p2)))
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY - 5))
        for pt in crest { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 5))
        p.closeSubpath()
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        ctx.drawLinearGradient(grad([rgba(top), rgba(bottom)], [0, 1]),
                               start: CGPoint(x: size/2, y: base + a1 + a2),
                               end: CGPoint(x: size/2, y: rect.minY), options: [])
        ctx.restoreGState()
        return crest
    }

    // Back → front: lit wine at the top crest, sinking into oxblood shadow.
    let crest1 = layer(base: 640, a1: 72, p1: 0.8, a2: 26, p2: 2.1, top: 0xA84860, bottom: 0x8C1F3C)
    _ = layer(base: 492, a1: 86, p1: 2.9, a2: 30, p2: 0.4, top: 0x8C1F3C, bottom: 0x62102C)
    _ = layer(base: 352, a1: 64, p1: 5.1, a2: 24, p2: 3.6, top: 0x5A0A24, bottom: 0x3C0317)
    _ = layer(base: 236, a1: 52, p1: 1.7, a2: 20, p2: 5.2, top: 0x33020F, bottom: 0x24010B)

    // Dusty-rose hairline tracing the first (lit) crest.
    ctx.setStrokeColor(rgba(0xE3A7C0, 0.85))
    ctx.setLineWidth(5)
    ctx.setLineJoin(.round)
    let hair = CGMutablePath()
    hair.move(to: crest1[0])
    for pt in crest1.dropFirst() { hair.addLine(to: pt) }
    ctx.addPath(hair)
    ctx.strokePath()

    // Subtle film grain so the flats don't look computer-smooth.
    srand48(7)
    for _ in 0..<9000 {
        let x = rect.minX + CGFloat(drand48()) * rect.width
        let y = rect.minY + CGFloat(drand48()) * rect.height
        let bright = drand48() > 0.5
        ctx.setFillColor(CGColor(gray: bright ? 1 : 0, alpha: 0.025))
        ctx.fill(CGRect(x: x, y: y, width: 2.2, height: 2.2))
    }

    // Hairline edge light.
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3),
                       cornerWidth: 182, cornerHeight: 182, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.06)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
