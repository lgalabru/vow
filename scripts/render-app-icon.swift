import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let configuration = NSImage.SymbolConfiguration(pointSize: 440, weight: .medium)
  .applying(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
guard
  let symbol = NSImage(systemSymbolName: "person.2.badge.key.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration)
else { fatalError("Missing app symbol") }
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 992, height: 992), xRadius: 220, yRadius: 220)
  .fill()
symbol.draw(in: NSRect(x: 190, y: 246, width: 644, height: 532))
image.unlockFocus()
func write(_ name: String, pixels: Int) throws {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)
  else { fatalError("Cannot create bitmap") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot render icon")
  }
  try png.write(to: destination.appendingPathComponent(name))
}
var entries: [[String: String]] = []
try write("AppIcon-iPad.png", pixels: 1024)
entries.append([
  "filename": "AppIcon-iPad.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
])
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let filename = "AppIcon-\(size)@\(scale)x.png"
    try write(filename, pixels: size * scale)
    entries.append([
      "filename": filename, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x",
    ])
  }
}
let content: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys]).write(
  to: destination.appendingPathComponent("Contents.json"))
