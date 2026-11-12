import Foundation

struct ImportedSimulation: Decodable {
  struct Result: Decodable {
    let failed: Bool
    let logs: [String]?
    let unitsConsumed: UInt64?
    enum CodingKeys: String, CodingKey { case err, logs, unitsConsumed }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      failed = !(try values.decodeNil(forKey: .err))
      logs = try values.decodeIfPresent([String].self, forKey: .logs)
      unitsConsumed = try values.decodeIfPresent(UInt64.self, forKey: .unitsConsumed)
    }
  }
  let result: Result
  let stateSource: String?
  let rpcSlotStart: UInt64
  let rpcSlotEnd: UInt64
}

struct RuntimeAccount: Decodable {
  let lamports: UInt64
  let owner: String
  let executable: Bool
  let space: UInt64?
  let data: [String]?
  var bytes: Data? {
    guard let data, data.count == 2, data[1] == "base64" else { return nil }
    return Data(base64Encoded: data[0])
  }
}
struct RuntimeAccountChange: Decodable {
  let type: String
  let before: RuntimeAccount?
  let after: RuntimeAccount?
  enum CodingKeys: String, CodingKey { case type, data }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    type = try values.decode(String.self, forKey: .type)
    if let pair = try? values.decode([RuntimeAccount].self, forKey: .data), pair.count == 2 {
      before = pair[0]
      after = pair[1]
    } else if let single = try? values.decode(RuntimeAccount.self, forKey: .data) {
      before = type == "delete" || type == "unchanged" ? single : nil
      after = type == "create" || type == "unchanged" ? single : nil
    } else {
      before = nil
      after = nil
    }
  }
}
struct RuntimeAccountState: Decodable {
  let type: String
  let accountChange: RuntimeAccountChange?
}
struct RuntimeInstructionProfile: Decodable {
  let computeUnitsConsumed: UInt64
  let logMessages: [String]?
  let errorMessage: String?
  let accountStates: [String: RuntimeAccountState]
}
struct RuntimeProfileEnvelope: Decodable {
  struct Profile: Decodable {
    let instructionProfiles: [RuntimeInstructionProfile]
    let transactionProfile: RuntimeInstructionProfile?
    let readonlyAccountStates: [String: RuntimeAccount]?
  }
  let value: Profile?
}
struct LocalSimulation: Decodable {
  let engine: String
  let source: String
  let wireDigest: String
  let reviewContextDigest: String
  let chain: String
  let offline: Bool
  let result: ImportedSimulation.Result
  let profile: RuntimeProfileEnvelope?
  let fixtureCount: Int
  let accountStates: StateDiffReport?
  var instructionProfiles: [RuntimeInstructionProfile] { profile?.value?.instructionProfiles ?? [] }
}
struct ReviewAccountChange: Identifiable {
  let id: String
  let kind: String
  let before: RuntimeAccount?
  let after: RuntimeAccount?
}
extension LocalSimulation {
  var changes: [ReviewAccountChange] {
    var result: [String: ReviewAccountChange] = [:]
    for instruction in instructionProfiles {
      for (address, state) in instruction.accountStates {
        guard let change = state.accountChange, change.type != "unchanged" else { continue }
        let earlier = result[address]
        result[address] = ReviewAccountChange(
          id: address, kind: earlier?.kind == "create" ? "create" : change.type,
          before: earlier == nil ? change.before : earlier?.before, after: change.after)
      }
    }
    return result.values.sorted { $0.id < $1.id }
  }
}

struct StateDiffReport: Decodable {
  let transaction: [StateAccountDiff]
  let instructions: [[StateAccountDiff]]
}
struct StateAccountDiff: Decodable, Identifiable {
  let id: String
  let kind: String
  let writable: Bool
  let changed: Bool
  let dataChanged: Bool
  let lamportsDelta: String
  let fields: [StateFieldDiff]
  let beforeState: String?
  let afterState: String?
}
struct StateFieldDiff: Decodable, Identifiable {
  var id: String { path }
  let path: String
  let before: String?
  let after: String?
  let changed: Bool
}
extension LocalSimulation {
  func statePair(address: String, scope: Int) -> (RuntimeAccount?, RuntimeAccount?) {
    guard let value = profile?.value else { return (nil, nil) }
    let state =
      scope < 0
      ? value.transactionProfile
      : value.instructionProfiles.indices.contains(scope) ? value.instructionProfiles[scope] : nil
    guard let account = state?.accountStates[address] else { return (nil, nil) }
    if account.type == "readonly", let readonly = value.readonlyAccountStates?[address] {
      return (readonly, readonly)
    }
    return (account.accountChange?.before, account.accountChange?.after)
  }
}
