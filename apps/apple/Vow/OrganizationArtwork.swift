import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Local presentation metadata, separate from enrollment and signing policy.
enum OrganizationArtwork {
  static let key = "vow.organization-artwork.v1"
  static func read(_ catalog: String, id: String) -> Data? {
    guard let object = try? JSONDecoder().decode([String: String].self, from: Data(catalog.utf8)),
      let encoded = object[id]
    else { return nil }
    return Data(base64Encoded: encoded)
  }
  @MainActor static func save(_ data: Data, id: String) {
    let defaults = UserDefaults.standard
    var object =
      (try? JSONDecoder().decode(
        [String: String].self, from: Data((defaults.string(forKey: key) ?? "{}").utf8))) ?? [:]
    object[id] = data.base64EncodedString()
    if let encoded = try? JSONEncoder().encode(object),
      let text = String(data: encoded, encoding: .utf8)
    {
      defaults.set(text, forKey: key)
    }
  }
  static func load(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let count = values.fileSize, count > 0, count <= 4 * 1024 * 1024 else {
      throw VowError(message: "Choose an image smaller than 4 MB.")
    }
    let input = try Data(contentsOf: url, options: .mappedIfSafe)
    // Decode through ImageIO with a bounded thumbnail, never a full-size canvas.
    guard let source = CGImageSourceCreateWithData(input as CFData, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 256,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary),
      let output = CFDataCreateMutable(nil, 0),
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)
    else { throw VowError(message: "Choose a PNG, JPEG or HEIC image.") }
    CGImageDestinationAddImage(destination, cg, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw VowError(message: "The image could not be saved.")
    }
    return output as Data
  }
}

struct OrganizationMark: View {
  let data: Data?
  var size: CGFloat = 30
  var body: some View {
    Group {
      #if os(macOS)
        if let data, let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFit()
        } else {
          Image(systemName: "building.2").font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
      #else
        if let data, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFit()
        } else {
          Image(systemName: "building.2").font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
      #endif
    }
    .frame(width: size, height: size)
    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.22))
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
  }
}
