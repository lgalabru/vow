# ADR 0001: share portable logic in Rust through a narrow C ABI

Status: accepted, 2026-11-09

## Context

Vow has Mac and iPad applications and needs an independent headless verifier.
Duplicating transaction interpretation or signing-payload construction across
platforms would create opportunities for the display and signature to disagree.
The owner requested that as much logic as possible live in Rust with an appropriate
FFI. Apple hardware and UI APIs still require a native adapter.

## Decision

Rust owns portable logic and security state. Swift owns presentation and Apple
platform operations. Use `vow-core` for the platform-independent implementation and
`vow-ffi` for a narrow versioned C ABI with generated headers and a Swift wrapper.
Produce an XCFramework for device, simulator and Mac targets.

Private keys and Secure Enclave key representations stay on the platform side.
Rust prepares the reviewed signing intent, Swift performs the requested hardware
operation, and Rust validates the result before finalization. Buffer ownership,
errors, cancellation and session lifecycle are explicit contracts.

The research spike uses subprocess IPC for test-vector generation. This is a test
harness and does not implement the production ABI.

## Consequences

Both apps share parsing, policy, ceremony and evidence behavior with the headless
verifier. Swift cannot silently substitute its own interpretation of an action.
We must maintain cross-language lifecycle tests, generated headers and multi-target
builds. This boundary does not protect against a compromised app or OS falsifying
what the person sees.

## References

[Implementation boundaries](../DESIGN.md#7-proposed-implementation-boundaries),
[FFI contracts](../CONTRACTS.md#rust-and-swift-boundary),
[compatibility spike](../../spikes/p256/README.md).
