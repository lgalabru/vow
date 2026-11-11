import Foundation
import Observation
import VowCore

struct Member: Decodable, Identifiable {
  let id: UInt64
  let name: String
  let role: String
  let ready: Bool
  var initials: String {
    name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
  }
}
struct Proposal: Decodable {
  let id: String
  let organization: String
  let quorumId: String
  let quorumDigest: String
  let title: String
  let amount: UInt64
  let asset: String
  let recipientName: String
  let recipient: String
  let network: String
  let note: String
  let transactionIntent: TransactionIntent?
  let demoExpiresAtUnixMs: UInt64?
  var statusCountdown: StatusCountdown? {
    if let context = transactionIntent?.blockhashContext { return .blockhash(context) }
    return demoExpiresAtUnixMs.map(StatusCountdown.demo) ?? .unavailable
  }
  var missingRequiredEvidence: Bool {
    transactionIntent.map { $0.requireSecurityKey || $0.requireAppAttest } ?? false
  }
  var displayAmount: String {
    (Double(amount) / (asset == "SOL" ? 1_000_000_000 : 1_000_000)).formatted(
      .number.precision(.fractionLength(asset == "SOL" ? 0...9 : 2...6)))
  }
}
struct Receipt: Decodable, Identifiable {
  let organizationName: String
  let projectName: String
  let projectId: String
  let quorumId: String
  let quorumName: String
  let quorumDigest: String
  let id: String
  let title: String
  let digest: String
  let keySource: String
  let package: String
}
struct Snapshot: Decodable {
  let organization: String
  let organizationId: String
  let organizations: [OrganizationSummary]
  let projects: [ProjectSummary]
  let projectId: String
  let chain: ChainContext?
  let projectName: String
  let members: [Member]
  let quorums: [QuorumSummary]
  let personalIdentities: [PersonalSigningIdentity]
  let personalIdentitiesExport: String
  let profiles: [SigningProfile]
  let profileCatalogExport: String
  let quorum: QuorumSummary?
  let quorumDigest: String?
  let confirmed: Bool
  let readyCount: Int
  let ceremonyDigest: String
  let ceremonyExport: String
  let decodedTransaction: DecodedTransfer?
  let proposal: Proposal?
  let proposalExport: String?
  let proposalDigest: String?
  let receipts: [Receipt]
  let declined: Bool
  let keySource: String
  var awaitingApproval: Bool {
    proposal != nil && !declined && !receipts.contains { $0.digest == proposalDigest }
  }
}
struct SigningRequest: Decodable {
  let session: UInt64
  let messageHex: String
}
private struct Envelope<T: Decodable>: Decodable {
  let ok: Bool
  let data: T?
  let error: String?
}
struct VowError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// The presentation layer never constructs canonical proposal or approval bytes.
@MainActor @Observable final class VowModel {
  private let session: UInt64
  var state: Snapshot?
  var error: String?
  private(set) var storageFailure: String?
  private var workspaceWasCleared = false
  private var lastArchivedIdentities: String?
  private var lastArchivedRegistrations: String?
  var working = false
  var importedFileCount = 0
  private(set) var lastImportedKind: String?
  var inspection: TransactionInspection?
  var selectedSigningProfileID: String?
  private(set) var workspaceResetGeneration: UInt64 = 0
  private var pendingImportedContent: String?

  init() {
    session = vow_session_create_v1()
    do {
      state = try call("snapshot")
      if shouldPersist {
        #if os(iOS)
          if try IdentityKeychain.hasResetIntent() {
            try IdentityKeychain.eraseAll()
            try identityStore.clearTemporaryExports()
            if let bundle = Bundle.main.bundleIdentifier {
              UserDefaults.standard.removePersistentDomain(forName: bundle)
            }
            try identityStore.save(
              personalIdentities: "[]", organizationProfiles: "[]", workspaceCleared: true)
            try IdentityKeychain.finishReset()
          }
        #endif
        if let archive = try identityStore.load() {
          workspaceWasCleared = archive.workspaceCleared == true
          if workspaceWasCleared { state = try call("reset_all") }
          let identities = try JSONSerialization.jsonObject(
            with: Data(archive.personalIdentities.utf8))
          let profiles = try JSONSerialization.jsonObject(
            with: Data(archive.organizationProfiles.utf8))
          state = try call("restore_profile_catalog", ["profiles": profiles])
          state = try call("restore_personal_identities", ["identities": identities])
        } else if !isUITesting,
          let saved = UserDefaults.standard.string(forKey: "vow.public-profile-catalog.v1"),
          let data = saved.data(using: .utf8), data.count <= 4_194_304
        {
          let profiles = try JSONSerialization.jsonObject(with: data)
          state = try call("restore_profile_catalog", ["profiles": profiles])
          if let state {
            try persist(state)
            UserDefaults.standard.removeObject(forKey: "vow.public-profile-catalog.v1")
          }
        } else if !isUITesting && !ProcessInfo.processInfo.arguments.contains("--show-sample") {
          state = try call("reset_all")
          workspaceWasCleared = true
          if let state { try persist(state) }
        }
      }
      #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-import-fixture"),
          let url = Bundle.main.url(forResource: "CapturedTransfer", withExtension: "vow")
        {
          importFile(url, deferUntilOffline: true)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-import-channel"),
          let url = Bundle.main.url(forResource: "ChannelOpen", withExtension: "bin")
        {
          importFile(url, deferUntilOffline: true)
        }
      #endif
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-sample") {
          state = try call("sample")
        }
      #endif
    } catch {
      self.error = error.localizedDescription
      storageFailure = error.localizedDescription
    }
  }
  deinit { vow_session_destroy_v1(session) }

  func call<T: Decodable>(_ action: String, _ fields: [String: Any] = [:]) throws -> T {
    var request = fields
    request["action"] = action
    let bytes = try JSONSerialization.data(withJSONObject: request)
    let result = bytes.withUnsafeBytes { raw in
      vow_dispatch_v1(session, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
    }
    guard let result else { throw VowError(message: "Vow couldn't open this session.") }
    defer { vow_string_free_v1(result) }
    let data = Data(String(cString: result).utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let envelope = try decoder.decode(Envelope<T>.self, from: data)
    guard envelope.ok, let value = envelope.data else {
      throw VowError(message: envelope.error ?? "The request couldn't be completed.")
    }
    return value
  }
  @discardableResult func perform(_ action: String, _ fields: [String: Any] = [:]) -> Bool {
    guard storageFailure == nil else { return false }
    do {
      let next: Snapshot = try call(action, fields)
      if state?.proposalDigest != next.proposalDigest { selectedSigningProfileID = nil }
      state = next
      if shouldPersist { try persist(next) }
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  #if os(iOS)
    func resetEverything(device: DeviceKey) {
      do {
        let _: Snapshot = try call("cancel")
        // Keychain intent makes interruption recoverable without trusting public metadata.
        try IdentityKeychain.beginReset()
        try identityStore.save(
          personalIdentities: "[]", organizationProfiles: "[]", workspaceCleared: true)
        try IdentityKeychain.eraseAll()
        device.clearCachedIdentity()
        try identityStore.clearTemporaryExports()
        if let bundle = Bundle.main.bundleIdentifier {
          UserDefaults.standard.removePersistentDomain(forName: bundle)
        }
        let next: Snapshot = try call("reset_all")
        try identityStore.save(
          personalIdentities: "[]", organizationProfiles: "[]", workspaceCleared: true)
        try IdentityKeychain.finishReset()
        workspaceWasCleared = true
        lastArchivedIdentities = nil
        lastArchivedRegistrations = nil
        state = next
        inspection = nil
        pendingImportedContent = nil
        selectedSigningProfileID = nil
        lastImportedKind = nil
        importedFileCount = 0
        error = nil
        storageFailure = nil
        workspaceResetGeneration &+= 1
      } catch {
        self.error = error.localizedDescription
        // Block signing after an incomplete reset; startup retries the durable reset intent.
        storageFailure =
          "Reset could not finish. Unlock this iPad and reopen Vow. " + error.localizedDescription
      }
    }
  #endif
  private var isUITesting: Bool {
    ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-test-") }
  }
  private var identityStore: PublicIdentityStore {
    #if DEBUG && targetEnvironment(simulator)
      if let value = ProcessInfo.processInfo.arguments.first(where: {
        $0.hasPrefix("--ui-test-identity=")
      }) {
        return PublicIdentityStore(
          namespace: "test-"
            + String(value.dropFirst("--ui-test-identity=".count)).filter {
              $0.isLetter || $0.isNumber || $0 == "-"
            })
      }
    #endif
    return PublicIdentityStore()
  }
  private var shouldPersist: Bool {
    !isUITesting
      || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-test-identity=") }
  }
  private func persist(_ snapshot: Snapshot) throws {
    guard
      snapshot.personalIdentitiesExport != lastArchivedIdentities
        || snapshot.profileCatalogExport != lastArchivedRegistrations
    else { return }
    try identityStore.save(
      personalIdentities: snapshot.personalIdentitiesExport,
      organizationProfiles: snapshot.profileCatalogExport, workspaceCleared: workspaceWasCleared)
    lastArchivedIdentities = snapshot.personalIdentitiesExport
    lastArchivedRegistrations = snapshot.profileCatalogExport
  }
  var hasSigningProfiles: Bool {
    !(state?.personalIdentities.isEmpty ?? true) || !(state?.profiles.isEmpty ?? true)
  }
  func personalIdentityPackage(_ id: String) -> String? {
    guard let text = state?.personalIdentitiesExport,
      let records = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]],
      let record = records.first(where: { $0["id"] as? String == id }),
      let data = try? JSONSerialization.data(
        withJSONObject: ["format": "vow.personal-identity.v1", "identity": record],
        options: [.sortedKeys, .prettyPrinted])
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
  func importFile(_ url: URL, deferUntilOffline: Bool = false) {
    guard url.isFileURL else {
      error = "Choose a local Vow file."
      return
    }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 8 * 1024 * 1024 else {
        throw VowError(message: "Choose a Vow file smaller than 8 MB.")
      }
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let bytes = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
      guard bytes.count <= 8 * 1024 * 1024 else {
        throw VowError(message: "This file couldn't be read as a Vow package.")
      }
      pendingImportedContent =
        String(data: bytes, encoding: .utf8).flatMap {
          $0.unicodeScalars.contains(where: { $0.value < 9 || ($0.value > 13 && $0.value < 32) })
            ? nil : $0
        } ?? bytes.map { String(format: "%02x", $0) }.joined()
      if !deferUntilOffline { importPendingFile() }
    } catch { self.error = error.localizedDescription }
  }
  func importPendingFile() {
    guard let text = pendingImportedContent else { return }
    pendingImportedContent = nil
    let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    if let format = object?["format"] as? String, format.hasPrefix("vow."),
      format != "vow.prototype.inspection.v1"
    {
      if perform("import", ["data": text]) {
        lastImportedKind =
          ["vow.prototype.signing-profile.v1", "vow.personal-identity.v1"].contains(format)
          ? "profile" : "request"
        importedFileCount += 1
      }
    } else {
      do {
        inspection = try call("inspect_transaction_dump", ["data": text])
        selectedSigningProfileID = nil
        error = nil
      } catch { self.error = error.localizedDescription }
    }
  }

}

extension Data {
  var hexString: String { map { String(format: "%02x", $0) }.joined() }
  init(hex: String) throws {
    guard hex.count.isMultiple(of: 2), hex.count <= 2_000_000 else {
      throw VowError(message: "Invalid signing data.")
    }
    self.init()
    var index = hex.startIndex
    while index < hex.endIndex {
      let end = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<end], radix: 16) else {
        throw VowError(message: "Invalid signing data.")
      }
      append(byte)
      index = end
    }
  }
}

struct HardwareKeyDecision: Codable {
  let format: String
  let method: String?
  let state: String
  let reason: String
  let writesPermitted: Bool
}
