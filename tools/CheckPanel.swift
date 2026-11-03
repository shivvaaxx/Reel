import AppKit
import CoreGraphics

// Finds Reel's menu bar panel on screen, captures it, and reports its size and the
// transparency of its corners (they must be clear for the rounded shape to be correct).
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let info = windows.first(where: {
    ($0[kCGWindowOwnerName as String] as? String) == "Reel" && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
}), let number = info[kCGWindowNumber as String] as? CGWindowID else {
    print("panel not on screen"); exit(1)
}
let bounds = info[kCGWindowBounds as String] as! [String: CGFloat]
print("panel window \(number): \(Int(bounds["Width"]!))x\(Int(bounds["Height"]!))")

let out = CommandLine.arguments.dropFirst().first ?? "/tmp/panel.png"
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(number)", out]   // -o: window only, no shadow
try capture.run()
capture.waitUntilExit()
guard let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: out))) else {
    print("capture failed"); exit(1)
}
let w = rep.pixelsWide, h = rep.pixelsHigh
func alpha(_ x: Int, _ y: Int) -> String {
    String(format: "%.2f", rep.colorAt(x: x, y: y)?.alphaComponent ?? -1)
}
print("corner alpha  TL \(alpha(1, 1))  TR \(alpha(w - 2, 1))  BL \(alpha(1, h - 2))  BR \(alpha(w - 2, h - 2))")
print("centre alpha  \(alpha(w / 2, h / 2))")
// Top band should contain the header text: look for bright pixels near the top.
var bright = 0
for y in 10..<min(70, h) { for x in stride(from: 20, to: w - 20, by: 3) {
    if let c = rep.colorAt(x: x, y: y), c.brightnessComponent > 0.85, c.alphaComponent > 0.9 { bright += 1 }
} }
print("bright pixels in header band: \(bright)")
print("image \(w)x\(h) px")
