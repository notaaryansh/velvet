// Renders the Velvet app icon (1024×1024 PNG) with CoreGraphics.
// Usage: swift Scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // macOS icon grid: 824pt squircle centered on a 1024pt transparent canvas.
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow behind the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.03, blue: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Velvet background: deep maroon-black vertical gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(red: 0.20, green: 0.08, blue: 0.12, alpha: 1),
                                 CGColor(red: 0.07, green: 0.02, blue: 0.04, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: size / 2, y: rect.maxY),
                           end: CGPoint(x: size / 2, y: rect.minY), options: [])

    // Faint radial sheen from the upper area, like light on fabric.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(red: 1, green: 0.45, blue: 0.5, alpha: 0.14),
                                    CGColor(red: 1, green: 0.45, blue: 0.5, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: size / 2, y: rect.maxY - 60),
                           startRadius: 0,
                           endCenter: CGPoint(x: size / 2, y: rect.maxY - 60),
                           endRadius: 620, options: [])

    // Waveform: five rounded bars in the accent red, symmetric like the wordmark.
    let heights: [CGFloat] = [0.32, 0.58, 0.84, 0.58, 0.32]
    let barWidth: CGFloat = 78
    let gap: CGFloat = 42
    let innerHeight: CGFloat = 560
    let totalWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
    var x = (size - totalWidth) / 2
    let centerY = size / 2

    let barGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [CGColor(red: 0.99, green: 0.33, blue: 0.33, alpha: 1),   // lighter top
                                          CGColor(red: 0.99, green: 0.24, blue: 0.27, alpha: 1),   // #FC3C44
                                          CGColor(red: 0.77, green: 0.19, blue: 0.23, alpha: 1)]   // #C4303A
                                    as CFArray,
                                 locations: [0, 0.5, 1])!

    // Soft red glow behind the bars.
    ctx.setShadow(offset: .zero, blur: 70,
                  color: CGColor(red: 0.99, green: 0.24, blue: 0.27, alpha: 0.45))

    for h in heights {
        let barHeight = innerHeight * h
        let barRect = CGRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
        let bar = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2,
                         cornerHeight: barWidth / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(bar)
        ctx.clip()
        ctx.drawLinearGradient(barGradient,
                               start: CGPoint(x: barRect.midX, y: barRect.maxY),
                               end: CGPoint(x: barRect.midX, y: barRect.minY), options: [])
        ctx.restoreGState()
        x += barWidth + gap
    }

    // Hairline top highlight so the tile reads as glossy velvet.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3),
                       cornerWidth: 182, cornerHeight: 182, transform: nil))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
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
