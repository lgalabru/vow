import Foundation
// Run using scripts/test-piv-pin-policy.sh. These test the production policy,
// independently of UI fixtures and without a connected security key.
var checks = 0
func expect(_ actual: PIVPINPolicy.Decision, _ expected: PIVPINPolicy.Decision) {
  precondition(actual == expected, "Unexpected PIN selection policy")
  checks += 1
}
for retries in -1...5 {
  for isFactory in [false, true] {
    for rejected in [false, true] {
      expect(
        PIVPINPolicy.decide(supplied: "", isFactory: isFactory, retries: retries,
          factoryAttemptRejected: rejected),
        retries <= 1 ? .blocked : isFactory && !rejected ? .verify("123456") : .requestPIN)
      expect(
        PIVPINPolicy.decide(supplied: "654321", isFactory: isFactory, retries: retries,
          factoryAttemptRejected: rejected),
        retries <= 1 ? .blocked : .verify("654321"))
    }
  }
}
for invalid in ["1", "12345", "123456789", "🔐🔐🔐"] {
  expect(PIVPINPolicy.decide(supplied: invalid, isFactory: true, retries: 3,
    factoryAttemptRejected: false), .invalidPIN)
}
print("Passed \(checks) PIN policy checks")


struct InjectedSetupFailure: Error {}
@MainActor final class SetupFixture {
  var factoryManagement = true
  var factoryRecovery = true
  var credential: String? = nil
  var saved: PIVSetupSecrets?
  var events: [String] = []
  var failAt: String?
  var failStore = false
  var incompatible = false
  var generations = 0
  var deletesCredential = false
  func event(_ name: String) throws {
    events.append(name)
    if failAt == name { failAt = nil; throw InjectedSetupFailure() }
  }
  func run(supported: Bool = true, recoveryRetries: Int = 3) async throws {
    let candidate = PIVSetupSecrets(serial: 42, managementKey: Data(repeating: 7, count: 32),
      recoveryCode: "86753090", managementType: 12)
    try await PIVSetupCoordinator.run(
      state: .init(factoryManagement: factoryManagement, factoryRecovery: factoryRecovery,
        recoveryRetries: recoveryRetries, supportsSecureSetup: supported),
      authenticationKey: saved?.managementKey ?? Data(repeating: 1, count: 24),
      saved: saved, makeSecrets: { candidate }, persist: { value in
        try self.event("persist")
        if self.failStore { throw InjectedSetupFailure() }
        self.saved = value
      }, operations: .init(
        check: { try self.event("connection") },
        credential: {
          try self.event("read")
          if self.incompatible { throw InjectedSetupFailure() }
          if self.deletesCredential && self.events.contains("persist") { return nil }
          return self.credential
        }, authenticate: { _ in try self.event("authenticate") },
        rotateManagement: { _ in
          precondition(self.saved != nil)
          try self.event("before-management")
          self.factoryManagement = false
          try self.event("after-management")
        }, rotateRecovery: { _ in
          precondition(self.saved != nil)
          try self.event("before-recovery")
          self.factoryRecovery = false
          try self.event("after-recovery")
        }, generate: {
          precondition(self.saved != nil && self.credential == nil)
          try self.event("before-generation")
          self.generations += 1
          self.credential = "hardware-public-key"
          try self.event("after-generation")
        }))
  }
}
@MainActor func runSetupChecks() async throws {
  // Every mutation boundary, including an acknowledgement lost after a write,
  // must resume with the original recovery record and at most one key generation.
  for boundary in ["before-management", "after-management", "before-recovery",
    "after-recovery", "before-generation", "after-generation", "persist", "authenticate"] {
    let fixture = SetupFixture()
    fixture.failAt = boundary
    do { try await fixture.run(); preconditionFailure("Expected interrupted setup") }
    catch is InjectedSetupFailure {}
    let originalSecrets = fixture.saved?.managementKey
    try await fixture.run()
    precondition(fixture.generations == 1 && fixture.credential == "hardware-public-key")
    if let originalSecrets { precondition(fixture.saved?.managementKey == originalSecrets) }
    checks += 1
  }
  let existing = SetupFixture()
  existing.credential = "existing-public-key"
  try await existing.run()
  precondition(existing.credential == "existing-public-key" && existing.generations == 0)
  checks += 1
  let failedStore = SetupFixture()
  failedStore.failStore = true
  do { try await failedStore.run(); preconditionFailure("Expected storage failure") }
  catch is InjectedSetupFailure {}
  precondition(failedStore.factoryManagement && failedStore.factoryRecovery && failedStore.generations == 0)
  checks += 1
  let incompatible = SetupFixture()
  incompatible.incompatible = true
  do { try await incompatible.run(); preconditionFailure("Expected incompatible slot failure") }
  catch is InjectedSetupFailure {}
  precondition(!incompatible.events.contains("authenticate") && incompatible.saved == nil)
  checks += 1
  for supported in [false, true] {
    let blocked = SetupFixture()
    do { try await blocked.run(supported: supported, recoveryRetries: 1); preconditionFailure("Expected blocked setup") }
    catch is PIVSetupCoordinator.Failure {}
    precondition(!blocked.events.contains("authenticate") && blocked.saved == nil)
    checks += 1
  }
  let removed = SetupFixture()
  removed.credential = "original"
  removed.deletesCredential = true
  do { try await removed.run(); preconditionFailure("Expected changed credential failure") }
  catch is PIVSetupCoordinator.Failure {}
  precondition(removed.generations == 0)
  checks += 1
}
try await runSetupChecks()
print("Passed \(checks) combined PIN and setup policy checks")
