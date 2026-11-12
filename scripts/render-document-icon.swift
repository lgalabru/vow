import AppKit
import Foundation
import UniformTypeIdentifiers

guard [3, 4].contains(CommandLine.arguments.count),
  let glyph = NSImage(contentsOfFile: CommandLine.arguments[1]),
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
  let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Supply the transparent V glyph and output PNG paths.") }
// Use Apple's generic document page, including its fold and shadow. The app
// icon stays independent; only the document's center receives the V mark.
let page = NSImage(
  contentsOfFile:
    "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns")!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
  if CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "badge" {
    // Crop the app-icon padding before fitting the iPad document badge.
    // Keep the original high-resolution mark and its existing colors.
    let cg = glyph.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let source = NSBitmapImageRep(cgImage: cg)
    precondition(source.bitsPerSample == 8 && source.hasAlpha && !source.isPlanar)
    let bytes = source.bitmapData!
    let samples = source.samplesPerPixel
    let alpha = source.bitmapFormat.contains(.alphaFirst) ? 0 : samples - 1
    var left = source.pixelsWide
    var right = -1
    var top = source.pixelsHigh
    var bottom = -1
    for y in 0..<source.pixelsHigh {
      for x in 0..<source.pixelsWide where bytes[y * source.bytesPerRow + x * samples + alpha] > 2 {
        left = min(left, x)
        right = max(right, x)
        top = min(top, y)
        bottom = max(bottom, y)
      }
    }
    precondition(right >= left && bottom >= top)
    let crop = cg.cropping(
      to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))!
    let mark = NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
    let scale = 944.0 / Double(max(crop.width, crop.height))
    let width = Double(crop.width) * scale
    let height = Double(crop.height) * scale
    mark.draw(
      in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
  } else {
    page.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    glyph.draw(in: NSRect(x: 232, y: 190, width: 560, height: 560))
  }
}
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Document icon rendering failed.")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
