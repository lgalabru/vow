# ADR 0007: Display the ExternalAccount bridge member address

Status: accepted (2026-11-10)

## Context

Admins need an address for a P-256 device key. The pinned external-signature bridge
supports two execution schemes with different signer addresses. Its legacy
ExecutionAccount mode uses a separate execution PDA. ExternalAccount mode uses the
passkey account itself as the signer.

## Decision

Display the ExternalAccount address, derived from `passkey` and SHA-256 of the
canonical compressed P-256 device key under the pinned bridge program. Label it
registration pending. Keep the derivation in Rust and verify it against an
independent SDK vector. Do not describe it as an active wallet or claim that the
prototype can submit a real multisig vote.

## Consequences

The same key and program ID produce the same address across clusters. Registration
must explicitly select ExternalAccount mode. An admin using legacy ExecutionAccount
mode needs its different execution PDA. Deployed bytecode compatibility and account
initialization remain production gates.

## References

- [Current flow](../DESIGN.md#native-proof-preparation-and-member-address-2026-11-10)
- [Pinned bridge PDA implementation](https://github.com/0xRigel-squads/external-signature-program/blob/9d49672f837f0615f321927975375694fb032e56/sdks/rust-sdk/src/pda.rs)
- [Execution schemes](https://github.com/0xRigel-squads/external-signature-program/blob/9d49672f837f0615f321927975375694fb032e56/src/state/externally_signed_account/execution_account.rs)
