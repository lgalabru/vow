#if os(macOS)
  import AppKit
  import Foundation

  @MainActor enum MacReviewSharing {
    // Keep the native service alive after the preparation view returns.
    private static var retainedAirDropService: NSSharingService?
    static func document(package: String, proposalIndex: UInt64) throws -> URL {
      guard package.utf8.count <= 8 * 1024 * 1024 else {
        throw VowError(message: "The review file exceeds 8 MB.")
      }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Vow-share-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("Proposal-\(proposalIndex).vow")
      try VowDocument.write(Data(package.utf8), to: url)
      return url
    }
    static func airDrop(_ url: URL) throws {
      guard let service = NSSharingService(named: .sendViaAirDrop) else {
        throw VowError(
          message:
            "AirDrop is unavailable on this Mac. Save the review file and share it from Finder.")
      }
      retainedAirDropService = service
      service.perform(withItems: [url])
    }
  }
#endif
