import AppKit

// Renders Reel's icon into an .iconset folder: a red squircle with a bold download arrow.
let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's macOS icon grid: 824pt body inside a 1024pt canvas.
    let body = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.36, alpha: 1),
        NSColor(srgbRed: 0.90, green: 0.13, blue: 0.30, alpha: 1),
    ])!
    gradient.draw(in: shape, angle: -90)

    // Soft top highlight for depth.
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.40, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2 - s * 0.01,
                               width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in sizes {
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
