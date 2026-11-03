import AppKit

// Renders the Safari extension's icons: colour app-style icons and monochrome toolbar icons.
let dir = CommandLine.arguments[1]

func png(_ px: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func arrow(_ s: CGFloat, color: NSColor, scale: CGFloat) {
    let config = NSImage.SymbolConfiguration(pointSize: s * scale, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let symbol = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let size = symbol.size
    symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
}

for px in [48, 96, 128, 256] {
    let data = png(px) { s in
        let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
        NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.42, blue: 0.36, alpha: 1),
                            NSColor(srgbRed: 0.9, green: 0.13, blue: 0.3, alpha: 1)])!.draw(in: shape, angle: -90)
        arrow(s, color: .white, scale: 0.42)
    }
    try! data.write(to: URL(fileURLWithPath: "\(dir)/icon-\(px).png"))
}

for px in [16, 19, 32, 38] {
    let data = png(px) { s in
        let ring = NSBezierPath(ovalIn: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8))
        ring.lineWidth = max(1, s * 0.09)
        NSColor.black.setStroke()
        ring.stroke()
        arrow(s, color: .black, scale: 0.42)
    }
    try! data.write(to: URL(fileURLWithPath: "\(dir)/toolbar-\(px).png"))
}
