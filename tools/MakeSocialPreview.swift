// Renders the GitHub social preview (1280×640): the app icon, the name and a tagline.
// Usage: swift tools/MakeSocialPreview.swift docs/icon.png docs/social-preview.png

import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]) else {
    print("Usage: swift tools/MakeSocialPreview.swift <icon.png> <out.png>")
    exit(1)
}

let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// The app's matte charcoal canvas; the cream icon stands out on it.
color(0x1C1A17).setFill()
NSRect(origin: .zero, size: size).fill()

// Icon.
icon.draw(in: NSRect(x: 110, y: 120, width: 400, height: 400))

// Name and tagline.
let title = NSAttributedString(string: "Reel", attributes: [
    .font: NSFont.systemFont(ofSize: 132, weight: .bold),
    .foregroundColor: color(0xF5F0E6),
    .kern: -2,
])
title.draw(at: NSPoint(x: 560, y: 330))

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 6
let tagline = NSAttributedString(
    string: "A clean, native Mac app for downloading videos and photos from YouTube, Instagram, TikTok and a thousand other sites.",
    attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .regular),
        .foregroundColor: color(0xF5F0E6, 0.72),
        .paragraphStyle: paragraph,
    ])
tagline.draw(in: NSRect(x: 564, y: 150, width: 640, height: 170))

let footer = NSAttributedString(string: "Free and open source  ·  macOS 26", attributes: [
    .font: NSFont.systemFont(ofSize: 24, weight: .medium),
    .foregroundColor: color(0xF5F0E6, 0.5),
])
footer.draw(at: NSPoint(x: 564, y: 104))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
