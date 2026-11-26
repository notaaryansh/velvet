// Renders the Velvet app icon (1024×1024 PNG) with CoreGraphics:
// a glossy vinyl record under deep red "velvet" lighting.
// Usage: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpaceCreateDeviceRGB()

func rgba(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: 824pt squircle centered on a 1024pt transparent canvas.
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow behind the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(rgba(0x0D0309))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Velvet backdrop: wine → near-black diagonal, with a crimson glow top-left.
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgba(0x571430), rgba(0x2B0916), rgba(0x0F0308)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgba(0xFC3C44, 0.30), rgba(0xFC3C44, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 780), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 780), endRadius: 560, options: [])

    let center = CGPoint(x: size / 2, y: size / 2 - 6)
    let discR: CGFloat = 318

    // Disc shadow on the backdrop.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 60, color: CGColor(gray: 0, alpha: 0.55))
    ctx.setFillColor(rgba(0x0B0B0D))
    ctx.fillEllipse(in: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
    ctx.restoreGState()

    // Vinyl base: off-center sheen so it reads as curved and lit from top-left.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
    ctx.clip()
    let vinyl = CGGradient(colorsSpace: space,
                           colors: [rgba(0x34343C), rgba(0x17171B), rgba(0x0A0A0C)] as CFArray,
                           locations: [0, 0.5, 1])!
    ctx.drawRadialGradient(vinyl,
                           startCenter: CGPoint(x: center.x - 150, y: center.y + 160), startRadius: 0,
                           endCenter: center, endRadius: discR * 1.2,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Grooves: fine concentric rings between label and rim.
    for r in stride(from: CGFloat(150), through: discR - 14, by: 7) {
        ctx.setStrokeColor(CGColor(gray: 1, alpha: r.truncatingRemainder(dividingBy: 21) == 1 ? 0.10 : 0.045))
        ctx.setLineWidth(1.6)
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    // Smooth specular sheen across the groove band: a diagonal gradient
    // clipped to the annulus so the light fades with no hard edges.
    ctx.saveGState()
    let annulus = CGMutablePath()
    annulus.addEllipse(in: CGRect(x: center.x - discR + 4, y: center.y - discR + 4,
                                  width: (discR - 4) * 2, height: (discR - 4) * 2))
    annulus.addEllipse(in: CGRect(x: center.x - 138, y: center.y - 138, width: 276, height: 276))
    ctx.addPath(annulus)
    ctx.clip(using: .evenOdd)
    let sheen = CGGradient(colorsSpace: space,
                           colors: [CGColor(gray: 1, alpha: 0.17), CGColor(gray: 1, alpha: 0.0),
                                    CGColor(gray: 1, alpha: 0.0), CGColor(gray: 1, alpha: 0.09)] as CFArray,
                           locations: [0, 0.42, 0.62, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: center.x - discR, y: center.y + discR),
                           end: CGPoint(x: center.x + discR, y: center.y - discR), options: [])
    ctx.restoreGState()

    // Crescent highlight along the lit edge of the disc.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26, color: CGColor(gray: 1, alpha: 0.5))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.30))
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    let crescent = CGMutablePath()
    crescent.addArc(center: center, radius: discR - 8,
                    startAngle: .pi * 0.58, endAngle: .pi * 0.98, clockwise: false)
    ctx.addPath(crescent)
    ctx.strokePath()
    ctx.restoreGState()

    // Rim lighting.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: center.x - discR + 2, y: center.y - discR + 2,
                                 width: (discR - 2) * 2, height: (discR - 2) * 2))
    ctx.restoreGState()

    // Label: velvet-red gradient with a soft glow, tiny spindle hole.
    let labelR: CGFloat = 128
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 56, color: rgba(0xFC3C44, 0.55))
    ctx.setFillColor(rgba(0xE03E47))
    ctx.fillEllipse(in: CGRect(x: center.x - labelR, y: center.y - labelR, width: labelR * 2, height: labelR * 2))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - labelR, y: center.y - labelR, width: labelR * 2, height: labelR * 2))
    ctx.clip()
    let label = CGGradient(colorsSpace: space,
                           colors: [rgba(0xFF7A6B), rgba(0xFC3C44), rgba(0xA62530)] as CFArray,
                           locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(label, start: CGPoint(x: center.x, y: center.y + labelR),
                           end: CGPoint(x: center.x, y: center.y - labelR), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: CGRect(x: center.x - labelR + 7, y: center.y - labelR + 7,
                                 width: (labelR - 7) * 2, height: (labelR - 7) * 2))
    ctx.setFillColor(rgba(0x12050A))
    ctx.fillEllipse(in: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26))

    // Wide diagonal glass sweep over the whole tile.
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.rotate(by: .pi / 6)
    let band = CGRect(x: -900, y: 170, width: 1800, height: 330)
    ctx.clip(to: band)
    let gloss = CGGradient(colorsSpace: space,
                           colors: [CGColor(gray: 1, alpha: 0.085), CGColor(gray: 1, alpha: 0.0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: band.maxY),
                           end: CGPoint(x: 0, y: band.minY), options: [])
    ctx.restoreGState()

    // Hairline top highlight on the squircle edge.
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3),
                       cornerWidth: 182, cornerHeight: 182, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.setLineWidth(6)
    ctx.strokePath()

    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("render failed\n", stderr); exit(1)
}
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
