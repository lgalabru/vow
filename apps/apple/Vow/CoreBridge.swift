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
  var working = false
  var importedFileCount = 0
  var inspection: TransactionInspection?
  private var pendingImportedContent: String?

  init() {
    session = vow_session_create_v1()
    do {
      state = try call("snapshot")
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
    } catch { self.error = error.localizedDescription }
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
    do {
      let next: Snapshot = try call(action, fields)
      state = next
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
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
      if perform("import", ["data": text]) { importedFileCount += 1 }
    } else {
      do {
        inspection = try call("inspect_transaction_dump", ["data": text])
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
