# P-256 bridge compatibility spike

Research code, not a wallet or a WebAuthn authenticator. Run from the repository
root on macOS with Swift/CryptoKit, Rust stable, and `cargo-build-sbf` installed.

```
just test
just test-hardware
```

The first run retrieves the bridge at the pinned revision and build dependencies.
The tests themselves use a local Solana VM and never broadcast a transaction.
`upstream-Cargo.lock` pins dependencies for the bridge build; the bridge-check
crate's `Cargo.lock` pins the host verifier. SBF v0 is explicit for compatibility
with the pinned legacy program and LiteSVM runtime.

Rust constructs the exact client JSON, RP hash, challenge and authenticator data,
normalizes ECDSA signatures to low-S, builds Solana instructions, and tests the
unmodified bridge. Swift only generates a key and signs supplied bytes with
CryptoKit. Its stdin/stdout interface is temporary test IPC, not the production FFI.

`just test-hardware` creates an ephemeral Secure Enclave P-256 key with private-key
access only. It deliberately does not test biometric enforcement or store a key
handle. No private keys are exported. It refuses a software fallback.

`just test-biometric` selects a separate access policy with `biometryCurrentSet`
and may display OS authorization prompts. This interactive diagnostic has not been
validated on iPad. One authentication context is used for the batch, so it does not
prove one prompt per approval. The product must use fresh authorization sessions.

## Results on 2026-11-09

Apple Silicon Mac, Swift 6.4.2, LiteSVM 0.6.1, bridge commit
`9d49672f837f0615f321927975375694fb032e56`. Both the explicit software fixture and
Secure Enclave crypto-only modes passed this six-case account-initialization test:

| Case | Expected bridge result |
|---|---|
| Signed WebAuthn-shaped payload | Accept |
| Bare challenge signature | Reject |
| Signed payload without user presence | Reject |
| Signed payload without user verification | Accept |
| Signed payload with wrong challenge | Reject |
| Wrapped payload with tampered signature | Reject |

The “no user verification” acceptance is a measured limitation. The bridge's UV
check is disabled. Even enabling it would not independently establish Touch ID
when the app constructs authenticator flags. This spike deliberately controls the
flags to expose that trust boundary. The public key is not attested as hardware
origin by this bridge test; hardware provenance needs separate evidence.

This demonstrates account registration with the actual bridge verifier and Solana
P-256 precompile. It does not demonstrate a Squads vote, full execution path,
production deployment equivalence, iPad behavior, fresh biometric approval,
handwriting/YubiKey enforcement, or operation across the slot-expiry window.

## Scope of the native shim

The standalone executable can sign arbitrary supplied messages to generate test
vectors. Do not expose it as the production app signing API. Production Rust core
must prepare a reviewed intent, bind it to a session, request one platform key
operation, then validate the returned signature and finalize that same session.
