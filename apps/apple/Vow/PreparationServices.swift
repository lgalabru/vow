import Foundation
import VowCore

struct ReplayOutput: Decodable {
  let engine: String
  let computeUnits: UInt64
  let logs: [String]
  let balances: [String: UInt64]
}
struct ReproductionHeader: Decodable {
  let engine: String
  let runtimeFingerprint: String
  let targetChain: String
  let source: String
  let contextSlot: UInt64
  let expected: ReplayOutput
}
struct IdlAttachment: Codable, Identifiable {
  var id: String { program }
  let program: String
  let metadataAddress: String
  let owner: String
  let accountDataBase64: String
  let chain: String
  let genesisHash: String
  let contextSlot: UInt64
  let idlJson: String
  let idlSha256: String
}
struct MetadataLocation: Decodable {
  let program: String
  let metadataAddress: String
  let owner: String
  let chain: ChainContext
}
enum NativeProfiler {
  nonisolated static func profile(_ input: Data) async throws -> Data {
    try await NativeProfilingQueue.shared.profile(input)
  }
}
/// Native profiling is blocking. Serialize forks and skip cancelled queued work;
/// cancellation of a running FFI call discards its result rather than spawning more forks.
private actor NativeProfilingQueue {
  static let shared = NativeProfilingQueue()
  private var tail: Task<Data, Error>?
  func profile(_ input: Data) async throws -> Data {
    try Task.checkCancellation()
    let previous = tail
    let job = Task.detached(priority: .userInitiated) {
      if let previous { _ = try? await previous.value }
      try Task.checkCancellation()
      let result = input.withUnsafeBytes { raw in
        vow_profile_transaction_v1(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
      }
      guard let result else { throw VowError(message: "The profiler could not start.") }
      defer { vow_string_free_v1(result) }
      return Data(String(cString: result).utf8)
    }
    tail = job
    return try await withTaskCancellationHandler {
      try await job.value
    } onCancel: {
      job.cancel()
    }
  }
}
#if os(macOS)
  @MainActor enum MetadataResolver {
    static func recentBlockhash(model: VowModel) async throws -> [String: Any] {
      guard let chain = model.state?.chain, let endpoint = URL(string: chain.rpcUrl) else {
        throw VowError(message: "Select a project network.")
      }
      let project = model.state?.projectId
      guard
        try await rpc(endpoint, method: "getGenesisHash", params: []) as? String
          == chain.genesisHash
      else {
        throw VowError(message: "RPC network mismatch.")
      }
      guard
        let result = try await rpc(
          endpoint, method: "getLatestBlockhash", params: [["commitment": "confirmed"]])
          as? [String: Any],
        let value = result["value"] as? [String: Any],
        let blockhash = value["blockhash"] as? String,
        let last = value["lastValidBlockHeight"] as? UInt64,
        let slot = (result["context"] as? [String: Any])?["slot"] as? UInt64,
        let height = try await rpc(
          endpoint, method: "getBlockHeight",
          params: [["commitment": "confirmed", "minContextSlot": slot]]) as? UInt64,
        last > height, last - height <= 300,
        model.state?.projectId == project, model.state?.chain?.genesisHash == chain.genesisHash
      else {
        throw VowError(message: "Could not establish a recent blockhash lifetime. Try again.")
      }
      let now = UInt64(Date().timeIntervalSince1970 * 1000)
      return [
        "blockhash": blockhash, "chain": chain.id, "genesis_hash": chain.genesisHash,
        "observed_at_unix_ms": now, "context_slot": slot, "observed_block_height": height,
        "last_valid_block_height": last,
        "estimated_expires_at_unix_ms": now + min((last - height) * 400, 60_000),
      ]
    }
    static func fetch(model: VowModel, program: String) async throws -> IdlAttachment {
      let location: MetadataLocation = try model.call("metadata_locator", ["program": program])
      let context = "\(model.state?.organizationId ?? "")/\(model.state?.projectId ?? "")"
      guard let endpoint = URL(string: location.chain.rpcUrl), endpoint.scheme == "https" else {
        throw VowError(message: "This project has no supported RPC endpoint.")
      }
      let genesis = try await rpc(endpoint, method: "getGenesisHash", params: []) as? String
      guard genesis == location.chain.genesisHash else {
        throw VowError(message: "RPC network mismatch. IDL retrieval stopped.")
      }
      guard
        let result = try await rpc(
          endpoint, method: "getAccountInfo",
          params: [location.metadataAddress, ["encoding": "base64", "commitment": "finalized"]])
          as? [String: Any],
        let value = result["value"] as? [String: Any], let owner = value["owner"] as? String,
        let data = value["data"] as? [String], data.count == 2, data[1] == "base64",
        let slot = (result["context"] as? [String: Any])?["slot"] as? NSNumber
      else {
        throw VowError(message: "No canonical on-chain IDL was found on \(location.chain.name).")
      }
      guard context == "\(model.state?.organizationId ?? "")/\(model.state?.projectId ?? "")",
        model.state?.chain?.genesisHash == location.chain.genesisHash
      else {
        throw VowError(message: "The project changed during IDL retrieval.")
      }
      return try model.call(
        "decode_metadata_idl",
        [
          "program": program, "metadata_address": location.metadataAddress,
          "owner": owner, "account_data_base64": data[0],
          "genesis_hash": location.chain.genesisHash, "context_slot": slot,
        ])
    }
    static func rpc(_ endpoint: URL, method: String, params: [Any]) async throws -> Any {
      var request = URLRequest(url: endpoint)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
      ])
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 15
      configuration.timeoutIntervalForResource = 20
      configuration.httpShouldSetCookies = false
      let session = URLSession(configuration: configuration)
      defer { session.invalidateAndCancel() }
      let (stream, response) = try await session.bytes(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw VowError(message: "The RPC endpoint could not complete this read.")
      }
      var bytes = Data()
      for try await byte in stream {
        if bytes.count >= 3 * 1024 * 1024 {
          throw VowError(message: "The metadata response exceeds the download limit.")
        }
        bytes.append(byte)
      }
      guard let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
        envelope["error"] == nil,
        let result = envelope["result"]
      else { throw VowError(message: "The RPC returned an error for this read.") }
      return result
    }
  }
#endif
