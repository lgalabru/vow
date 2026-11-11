/// Selects a PIN source without spending a hardware attempt.
/// Factory PIN use is explicit product policy; it is not a secret factor.
enum PIVPINPolicy {
  enum Decision: Equatable {
    case verify(String)
    case requestPIN
    case invalidPIN
    case blocked
  }

  static func decide(
    supplied: String, isFactory: Bool, retries: Int, factoryAttemptRejected: Bool
  ) -> Decision {
    guard retries > 1 else { return .blocked }
    if supplied.isEmpty {
      guard isFactory, !factoryAttemptRejected else { return .requestPIN }
      return .verify("123456")
    }
    guard (6...8).contains(supplied.utf8.count), !supplied.utf8.contains(0xff) else {
      return .invalidPIN
    }
    return .verify(supplied)
  }
}
