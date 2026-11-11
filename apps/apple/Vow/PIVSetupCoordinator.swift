import Foundation

struct PIVSetupSecrets: Codable {
  let serial: UInt
  let managementKey: Data
  let recoveryCode: String
  let managementType: UInt8
}

/// Administrative writes are separate from inspection and signing. Persist recovery
/// state first, re-check connection at each boundary, and never overwrite a key.
@MainActor enum PIVSetupCoordinator {
  struct State {
    let factoryManagement: Bool
    let factoryRecovery: Bool
    let recoveryRetries: Int
    let supportsSecureSetup: Bool
  }
  struct Operations {
    var check: () throws -> Void
    var credential: () async throws -> String?
    var authenticate: (Data) async throws -> Void
    var rotateManagement: (PIVSetupSecrets) async throws -> Void
    var rotateRecovery: (String) async throws -> Void
    var generate: () async throws -> Void
  }
  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func run(
    state: State, authenticationKey: Data,
    saved: PIVSetupSecrets?, makeSecrets: () throws -> PIVSetupSecrets,
    persist: (PIVSetupSecrets) throws -> Void, operations: Operations
  ) async throws {
    try operations.check()
    let original = try await operations.credential()
    guard state.supportsSecureSetup else {
      throw Failure(
        message:
          "This key's firmware needs one-time smart-card preparation on a Mac. Its PIN and credentials have not been changed."
      )
    }
    if state.factoryRecovery && state.recoveryRetries <= 1 {
      throw Failure(
        message:
          "This key's recovery code needs administrator attention. Vow will not use its final retry."
      )
    }
    try operations.check()
    try await operations.authenticate(authenticationKey)
    let secrets: PIVSetupSecrets
    if let saved {
      secrets = saved
    } else {
      secrets = try makeSecrets()
      try persist(secrets)
    }
    if state.factoryManagement {
      try operations.check()
      try await operations.rotateManagement(secrets)
      try operations.check()
      try await operations.authenticate(secrets.managementKey)
    }
    if state.factoryRecovery {
      try operations.check()
      try await operations.rotateRecovery(secrets.recoveryCode)
    }
    try operations.check()
    let beforeGeneration = try await operations.credential()
    guard original == nil || beforeGeneration == original else {
      throw Failure(
        message: "The signing credential changed during setup. No replacement was generated.")
    }
    if beforeGeneration == nil {
      try operations.check()
      try await operations.generate()
    }
    try operations.check()
    guard let final = try await operations.credential(), original == nil || final == original else {
      throw Failure(
        message:
          "Key setup did not complete or the credential changed. Reconnect your key to check its state."
      )
    }
  }
}
