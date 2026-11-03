// Renders Reel's app icon: a pink-to-indigo gradient tile with a white download
// arrow that has a play button cut into it. Drawn natively from the Figma design
// ("Reels — macOS App Icon"), fitted to Apple's macOS icon grid (an 824 pt
// continuous-corner body on a 1024 pt canvas).
//
// Usage: swift tools/MakeIcon.swift <out.iconset> [preview.png]

import AppKit
import SwiftUI

// The Figma frame is 512 units with the tile at 32...480 (448 units).
// Everything below is in those design units and mapped onto the grid.
let designTile = CGRect(x: 32, y: 32, width: 448, height: 448)
let gridBody: CGFloat = 824.0 / 1024.0     // body size as a fraction of the canvas

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func hex(_ v: UInt32) -> CGColor {
    rgba(CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

/// The arrow-with-play-button symbol, in design units (y down).
func symbolPath() -> CGPath {
    let p = CGMutablePath()
    // Arrow outline
    p.move(to: CGPoint(x: 220, y: 128))
    p.addLine(to: CGPoint(x: 292, y: 128))
    p.addCurve(to: CGPoint(x: 316, y: 152), control1: CGPoint(x: 305.255, y: 128), control2: CGPoint(x: 316, y: 138.745))
    p.addLine(to: CGPoint(x: 316, y: 252))
    p.addLine(to: CGPoint(x: 354, y: 252))
    p.addCurve(to: CGPoint(x: 365.314, y: 279.314), control1: CGPoint(x: 368.255, y: 252), control2: CGPoint(x: 375.394, y: 269.235))
    p.addLine(to: CGPoint(x: 271.556, y: 373.071))
    p.addCurve(to: CGPoint(x: 240.444, y: 373.071), control1: CGPoint(x: 262.965, y: 381.663), control2: CGPoint(x: 249.035, y: 381.663))
    p.addLine(to: CGPoint(x: 146.686, y: 279.314))
    p.addCurve(to: CGPoint(x: 158, y: 252), control1: CGPoint(x: 136.606, y: 269.235), control2: CGPoint(x: 143.745, y: 252))
    p.addLine(to: CGPoint(x: 196, y: 252))
    p.addLine(to: CGPoint(x: 196, y: 152))
    p.addCurve(to: CGPoint(x: 220, y: 128), control1: CGPoint(x: 196, y: 138.745), control2: CGPoint(x: 206.745, y: 128))
    p.closeSubpath()
    // Play button (cut out with the even-odd rule)
    p.move(to: CGPoint(x: 240, y: 166))
    p.addCurve(to: CGPoint(x: 232.5, y: 170.33), control1: CGPoint(x: 236.667, y: 164.075), control2: CGPoint(x: 232.5, y: 166.481))
    p.addLine(to: CGPoint(x: 232.5, y: 222.67))
    p.addCurve(to: CGPoint(x: 240, y: 227), control1: CGPoint(x: 232.5, y: 226.519), control2: CGPoint(x: 236.667, y: 228.925))
    p.addLine(to: CGPoint(x: 285.33, y: 200.83))
    p.addCurve(to: CGPoint(x: 285.33, y: 192.17), control1: CGPoint(x: 288.663, y: 198.906), control2: CGPoint(x: 288.663, y: 194.094))
    p.addLine(to: CGPoint(x: 240, y: 166))
    p.closeSubpath()
    return p
}

/// Apple-style continuous-corner tile (radius ratio matches the design's 100/448).
func tilePath(_ rect: CGRect) -> CGPath {
    RoundedRectangle(cornerRadius: rect.width * (100.0 / 448.0), style: .continuous).path(in: rect).cgPath
}

/// Inner shadow inside `path`: offset/blur in design units (y down).
func innerShadow(_ ctx: CGContext, _ path: CGPath, dy: CGFloat, blur: CGFloat, color: CGColor, unit: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let ring = CGMutablePath()
    ring.addRect(path.boundingBox.insetBy(dx: -200, dy: -200))
    ring.addPath(path)
    // Shadow offsets live in device space (y up) and ignore the CTM.
    ctx.setShadow(offset: CGSize(width: 0, height: -dy * unit), blur: blur * 2 * unit, color: color)
    ctx.setFillColor(rgba(0, 0, 0, 1))
    ctx.addPath(ring); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    // Map design units onto the grid, with y pointing down like Figma.
    let unit = size * gridBody / designTile.width                 // pixels per design unit
    let origin = (size - designTile.width * unit) / 2 - designTile.minX * unit
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: origin, y: origin)
    ctx.scaleBy(x: unit, y: unit)

    let tile = tilePath(designTile)

    // 1. Soft drop shadow (spread −5, y +12, blur 10).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * unit), blur: 20 * unit, color: rgba(0.16, 0.06, 0.32, 0.22))
    ctx.setFillColor(rgba(0.16, 0.06, 0.32, 1))
    ctx.addPath(tilePath(designTile.insetBy(dx: 5, dy: 5))); ctx.fillPath()
    ctx.restoreGState()

    // 2. Gradient body.
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex(0xFC7989), hex(0xD449D7), hex(0x8044ED), hex(0x4731B9)] as CFArray,
                              locations: [0, 0.38, 0.72, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 62.0183, y: 93.8558), end: CGPoint(x: 403.135, y: 389.49),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // 3. Light catching the top edge, and depth along the bottom.
    innerShadow(ctx, tile, dy: 2, blur: 1.5, color: rgba(1, 1, 1, 0.32), unit: unit)
    innerShadow(ctx, tile, dy: -5, blur: 6, color: rgba(0.16, 0.03, 0.40, 0.22), unit: unit)

    // 4. Hairline rim.
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    ctx.addPath(tile)
    ctx.setStrokeColor(rgba(1, 1, 1, 0.24))
    ctx.setLineWidth(2)   // centred on the edge, so 1 unit shows inside the clip
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Symbol with its shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * unit), blur: 10 * unit, color: rgba(0.24, 0.04, 0.45, 0.22))
    ctx.setFillColor(rgba(1, 1, 1, 1))
    ctx.addPath(symbolPath()); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: swift tools/MakeIcon.swift <out.iconset> [preview.png]")
    exit(1)
}
let iconset = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try writePNG(render(pixels: points * scale), to: iconset.appendingPathComponent(name))
    }
}
if args.count >= 3 {
    try writePNG(render(pixels: 1024), to: URL(fileURLWithPath: args[2]))
}
print("Wrote \(iconset.path)")
