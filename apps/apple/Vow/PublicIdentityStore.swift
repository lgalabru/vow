import Foundation

/// A versioned public-record archive. Private keys, PINs and authorization state never enter it.
/// Cloud backup is a separate, opt-in capability; this store works without an account or network.
struct PublicIdentityStore {
  var namespace = "public-identities-v1"
  struct Archive: Codable {
    let schema: Int
    let personalIdentities: String
    let organizationProfiles: String
    let workspaceCleared: Bool?
  }
  private var url: URL {
    get throws {
      let folder = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent("Vow", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      return folder.appendingPathComponent(namespace + ".json")
    }
  }
  func clearTemporaryExports() throws {
    let folder = FileManager.default.temporaryDirectory
    for file in try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    {
      if file.lastPathComponent.hasPrefix("Vow-") || file.lastPathComponent == "VowDesignReview" {
        try FileManager.default.removeItem(at: file)
      }
    }
  }
  func load() throws -> Archive? {
    let location = try url
    guard FileManager.default.fileExists(atPath: location.path) else { return nil }
    guard (try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_388_608 else {
      throw VowError(message: "The saved profile archive is too large. It has not been replaced.")
    }
    let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: location))
    guard archive.schema == 1 else {
      throw VowError(message: "This profile archive requires a newer Vow version.")
    }
    return archive
  }
  func save(
    personalIdentities: String, organizationProfiles: String, workspaceCleared: Bool = false
  ) throws {
    let archive = Archive(
      schema: 1, personalIdentities: personalIdentities, organizationProfiles: organizationProfiles,
      workspaceCleared: workspaceCleared)
    let data = try JSONEncoder().encode(archive)
    guard data.count <= 8_388_608 else {
      throw VowError(message: "Profile archive exceeds the storage limit.")
    }
    var location = try url
    #if os(iOS)
      try data.write(
        to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: location, options: .atomic)
    #endif
    // No automatic cloud/device backup until the owner explicitly chooses a backup policy.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try location.setResourceValues(values)
  }
}
