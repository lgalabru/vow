#if os(macOS)
  import Foundation
  import Observation

  @MainActor @Observable final class MultisigObserver {
    static let catalogKey = "vow.observed-multisigs.v1"
    private static let catalogBytesMax = 32_768
    private static let watchCountMax = 32
    private(set) var watches: [WatchedMultisig] = []
    var selectedID: String? {
      didSet {
        if !isUITesting {
          UserDefaults.standard.set(selectedID, forKey: "vow.observed-multisig-selection.v1")
        }
      }
    }
    private(set) var working = false
    private(set) var error: String?
    private(set) var snapshot: ObservedMultisigSnapshot?
    enum Page { case latest, older, newer }
    var paginated: Bool { current.map { $0.pageStart < $0.multisig.transactionIndex } ?? false }
    private var loadedID: String?
    private var generation: UInt64 = 0
    private var catalogReadable = true
    private let isUITesting: Bool = {
      #if DEBUG
        return ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--ui-test-") }
      #else
        return false
      #endif
    }()
    var selected: WatchedMultisig? { watches.first { $0.id == selectedID } }
    var current: ObservedMultisigSnapshot? { loadedID == selectedID ? snapshot : nil }
    init() {
      #if DEBUG
        if isUITesting {
          if ProcessInfo.processInfo.arguments.contains("--ui-test-observed-multisig") {
            let watch = WatchedMultisig(
              address: "11111111111111111111111111111111", network: .devnet,
              name: "Operations Treasury")
            watches = [watch]
            selectedID = watch.id
          }
          return
        }
      #endif
      do {
        if let data = UserDefaults.standard.data(forKey: Self.catalogKey) {
          guard data.count <= Self.catalogBytesMax else {
            throw VowError(message: "Saved multisig watchlist exceeds its size limit.")
          }
          let decoded = try JSONDecoder().decode([WatchedMultisig].self, from: data)
          guard decoded.count <= Self.watchCountMax, Set(decoded.map(\.id)).count == decoded.count,
            decoded.allSatisfy({
              !$0.address.isEmpty && $0.address.count <= 44 && $0.name.count <= 60
            })
          else { throw VowError(message: "Saved multisig watchlist is invalid.") }
          watches = decoded
        }
        selectedID = UserDefaults.standard.string(forKey: "vow.observed-multisig-selection.v1")
        if !watches.contains(where: { $0.id == selectedID }) { selectedID = watches.first?.id }
      } catch {
        catalogReadable = false
        self.error = "Could not load watched multisigs: \(error.localizedDescription)"
      }
    }
    private func save(_ watches: [WatchedMultisig]) throws {
      guard catalogReadable, watches.count <= Self.watchCountMax else {
        throw VowError(
          message: "Cannot update this watchlist. Vow supports up to 32 watched multisigs.")
      }
      let data = try JSONEncoder().encode(watches)
      guard data.count <= Self.catalogBytesMax else {
        throw VowError(message: "The watchlist exceeds its storage limit.")
      }
      if !isUITesting { UserDefaults.standard.set(data, forKey: Self.catalogKey) }
      self.watches = watches
    }
    func renameSelected(_ name: String) {
      guard let selectedID else { return }
      let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, name.count <= 60 else {
        error = "Use a name of 1–60 characters."
        return
      }
      do {
        try save(
          watches.map { item in
            var item = item
            if item.id == selectedID { item.name = name }
            return item
          })
      } catch { self.error = error.localizedDescription }
    }
    func removeSelected() {
      guard let selectedID else { return }
      do {
        try save(watches.filter { $0.id != selectedID })
        error = nil
        self.selectedID = watches.first?.id
      } catch { self.error = error.localizedDescription }
    }
    func add(input: String, name: String, network: ObservedNetwork) async -> Bool {
      guard !working else { return false }
      generation &+= 1
      let operation = generation
      working = true
      error = nil
      defer { if operation == generation { working = false } }
      do {
        let (address, network) = try MultisigWatchInput.parse(input, network: network)
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count <= 60 else {
          throw VowError(message: "Use a name of up to 60 characters.")
        }
        struct Resolution: Decodable { let multisig: ObservedMultisig }
        let response: Resolution = try await query(
          operation: "resolve", address: address, network: network)
        try Task.checkCancellation()
        guard operation == generation else { return false }
        let watch = WatchedMultisig(
          address: response.multisig.address, network: network,
          name: label.isEmpty
            ? String(response.multisig.address.prefix(6)) + "…"
              + String(response.multisig.address.suffix(6)) : label)
        if !watches.contains(where: { $0.id == watch.id }) { try save(watches + [watch]) }
        selectedID = watch.id
        return true
      } catch is CancellationError { return false } catch {
        if operation == generation { self.error = error.localizedDescription }
        return false
      }
    }
    func refresh(page: Page = .latest) async {
      guard let watch = selected else { return }
      generation &+= 1
      let operation = generation
      let existing = current
      working = true
      error = nil
      defer { if generation == operation { working = false } }
      do {
        var fields: [String: Any] = [:]
        switch page {
        case .latest: break
        case .older:
          guard let cursor = existing?.nextBefore else { return }
          fields["before"] = cursor
        case .newer:
          guard let existing else { return }
          let next = existing.pageStart.addingReportingOverflow(existing.pageSize)
          if !next.overflow, next.partialValue < existing.multisig.transactionIndex {
            fields["before"] = next.partialValue + 1
          }
        }
        let response: ObservedMultisigSnapshot = try await query(
          operation: "fetch", address: watch.address, network: watch.network, fields: fields)
        try Task.checkCancellation()
        guard generation == operation, selectedID == watch.id else { return }
        snapshot = response
        loadedID = watch.id
      } catch is CancellationError {} catch {
        if generation == operation { self.error = error.localizedDescription }
      }
    }
    func prepare(_ proposal: ObservedProposal, member: String) async throws -> String {
      guard let watch = selected, !working else {
        throw VowError(message: "Wait for the multisig refresh to finish.")
      }
      let id = watch.id
      generation &+= 1
      let operation = generation
      working = true
      defer { if operation == generation { working = false } }
      struct Prepared: Decodable { let package: String }
      let response: Prepared = try await query(
        operation: "prepare_approval", address: watch.address, network: watch.network,
        fields: ["index": proposal.proposal.index, "member": member])
      try Task.checkCancellation()
      guard operation == generation, selectedID == id else { throw CancellationError() }
      return response.package
    }
    private func query<T: Decodable>(
      operation: String, address: String, network: ObservedNetwork, fields: [String: Any] = [:]
    ) async throws -> T {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-observed-multisig") {
          guard operation == "fetch",
            let url = Bundle.main.url(forResource: "ObservedMultisigFixture", withExtension: "json")
          else {
            throw VowError(message: "This UI fixture is read-only.")
          }
          let decoder = JSONDecoder()
          decoder.keyDecodingStrategy = .convertFromSnakeCase
          return try decoder.decode(T.self, from: Data(contentsOf: url))
        }
      #endif
      var input = fields
      input["mode"] = "multisig_watch"
      input["operation"] = operation
      input["address"] = address
      input["chain"] = network.rawValue
      let response = try await NativeProfiler.profile(JSONSerialization.data(withJSONObject: input))
      try Task.checkCancellation()
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let decoded = try decoder.decode(WatchEnvelope<T>.self, from: response)
      guard decoded.ok, let data = decoded.data else {
        throw VowError(message: decoded.error ?? "Could not retrieve this multisig.")
      }
      return data
    }
  }
  private struct WatchEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
  }
#endif
