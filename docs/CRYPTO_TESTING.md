# Cryptography verification

Run `just crypto-test`, `just crypto-lint` and `just crypto-fmt`. The Cryptography
workflow runs these commands for changes to Rust crates and their dependency lock.

| Boundary | Automated checks |
|---|---|
| Native WebAuthn assertion | Valid ES256 proof; every single-bit mutation of the message, signature, authenticator data and raw client JSON; all 256 flag values; exact RP, HTTPS origin, type, challenge and cross-origin policy; malformed keys, signatures, encodings and size limits |
| Native registration | Bounded CBOR and COSE parsing; credential binding; truncated attestation objects; reserved flags; ES256 key validation |
| Enrollment | Both independent P-256 proofs; wrong keys and domain; bound nonce, credential, source, policy and RP; native, direct CTAP and legacy PIV records |
| Approval session | Both exact signatures; no missing or downgraded factor; wrong key/message/session; consumed failed attempts; cancellation, reprepare and changed consent invalidate old key proofs; one receipt per successful approval |
| Member address | Independent golden PDA vector; correct ExternalAccount mode and bump; off-curve result; rejection of malformed or noncanonical keys; distinction from the legacy execution PDA |
| Hardware-key policy | 150 enrolled-method/capability combinations; pinned methods; explicit unsupported result before PIV; failed/unavailable probes cannot downgrade; malformed reports rejected; unprepared PIV remains blocked |
| C ABI | Isolated sessions, invalidated handles and null-input errors |
| Transaction input | Canonical wire decoding, changed instructions, chain/genesis and project/quorum binding, blockhash freshness |

The parser rejects reserved registration flag bits. An explicitly requested FIDO
or WebAuthn method requires a public key; it cannot silently become device-only.

Native UI regression tests also exercise preauthorization, clearing and redrawing
consent, key removal and network reconnection during signing. These use simulator
fixtures. Physical-device checks remain necessary for Secure Enclave access
control, system PIN prompts, USB removal timing and offline domain association.
Unit tests do not establish factory attestation, deployed bridge bytecode identity,
on-chain account initialization or production Squads integration. The receipt
continues to state `prototype_only` and `local_approval_only`.

The separate Apple-to-Solana compatibility check is
`python3 scripts/check-p256.py -- --software-fixture`. It builds the pinned bridge
and verifies CryptoKit output against the actual program in the local VM. It also
checks bare signatures, missing presence, missing verification, wrong challenges
and altered messages. The pinned bridge accepts missing user verification; Vow's
local verifier rejects it. Enforcing that requirement against direct submission
still needs the production on-chain policy layer. This manual check requires the
Apple toolchain and `cargo build-sbf`; it is separate from portable CI.

The hardware-default UI checks cover a configured native domain with direct USB
selection, native enrollment/signing compatibility, failed FIDO probes without
fallback, PIN-free diagnostic export, and unprepared/default-management PIV setup
without PIN or management-key fields. Physical direct USB acceptance remains open.

Profile tests verify Ledger envelope binding against the PR-pinned desktop helper,
profile ownership/scope, P-256 dual-key preservation, malformed/expired enrollment,
immutable policy versions, duplicate member/address rejection, public import and
revocation, v4/v5 schema separation, quorum-policy roundtrips, wrong signing methods,
wrong keys, cancellation/reprepare replay and network/genesis binding. Mobile tests
cover APDU/path/chunk conventions, response status/type, every byte mutation of a
valid response, bounded BLE reassembly and invalid ordering/length/trailing frames.
`just ledger-test` exercises desktop envelope conformance without hardware. CI has
a macOS job for this PR-pinned adapter. Physical acceptance is a separate gate.
