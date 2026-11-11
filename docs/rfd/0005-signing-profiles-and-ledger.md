# RFD 0005: User-owned signing profiles and Ledger support

State: adopted (ADR 0009)
Authors: Vow team · Started: 2026-11-10

## Problem

A member can want different signing identities and approval requirements for
different quorums. A Ledger account and the current iPad/security-key identity
have different public keys, signature schemes and verification capabilities.
The current registry has member IDs in a quorum and one local device identity.
It cannot express which identity a member must use for a particular quorum.

## Sketch

### Model

A user owns several named profiles. Each profile binds a signing identity to a
versioned authorization policy. An organization separately registers a profile
against an enrolled member. The physical identity ceremony is per member; adding
a profile requires an authorized key-binding proof, not another passport scan.
A local profile alone does not establish organization membership.

A quorum seat references one organization member and one exact profile version.
A project continues to select an immutable reusable quorum. The same profile may
serve in several quorums. Different members can use different profile kinds in one
quorum, subject to the quorum's accepted methods and enforcement capabilities.

Example:

| Member | Profile | Quorum |
|---|---|---|
| Ludo | Ledger treasury account | Treasury |
| Ludo | iPad and security key | Operations |
| Alice | Ledger account | Treasury |
| Bob | iPad and security key | Treasury |

Treasury can require two of its three distinct members. Two profiles belonging to
Ludo cannot occupy two independently counted seats in the same quorum. The same
on-chain signer address must not occupy two seats under different member names.

Proposed records:

- `SignerProfile`: opaque ID, owner reference, display name, immutable version,
  signing method, algorithm, public key, chain address or bridge configuration,
  authorization policy and capability declarations. Private key references remain
  local to the platform adapter and never enter public records.
- `OrganizationProfileRegistration`: organization/member reference, exact profile
  reference and digest, proof of key possession, authorized member binding,
  activation/revocation state and per-cluster registration state.
- `QuorumSeat`: member ID, profile ID/version/digest and resolved signer address.
  The quorum digest commits to the ordered canonical seats and threshold.

A display-name edit may change local presentation without changing identity or
policy. Changing a key, derivation path, factors or method creates a new profile
version. Existing quorums keep their previous binding. Replacing a seat requires
a new quorum revision and the multisig's authorized membership update, not a local
profile switch. Never claim an on-chain update from an app-only edit.

### Initial profile kinds

**Ledger:** an Ed25519 Solana account, explicit derivation path and device-confirmed
address. Approval requires a matching signature over the exact Solana transaction
message and confirmation on the Ledger. Vow never asks for the Ledger PIN or seed.
This is a normal Ed25519 signer address; it does not use the P-256 bridge.

**iPad and security key:** the current P-256 Secure Enclave identity, pinned external
key and handwritten-consent requirement, followed by device biometrics. It retains
the explicit bridge execution scheme and pending activation status. Handwriting is
recorded consent, not an independently verified biometric factor. Existing local
factor proofs do not become on-chain policy enforcement by adding a profile label.

Keep the kinds extensible through typed capabilities. Do not infer compatibility
from a friendly name such as `three-factor` or `hardware wallet`. A Ledger signature
does not by itself attest firmware, the device PIN policy, Vow's version or the
content shown on its screen.

### UX

`Profiles` lists named identities with method, address, readiness and the quorums
using each. Add Profile offers Ledger or iPad and security key. A member's physical
enrollment is reused; the new key association still needs proof and authorization.

When composing a quorum, select a member, then one of that member's registered
compatible profiles. Show method and shortened address in the seat row. Existing
quorums show their pinned selection. A signing request names the required profile;
Vow can select that exact local profile automatically. A missing or incompatible
profile blocks signing and offers connection or import guidance, not substitution.

Ledger enrollment shows `Unlock your Ledger`, `Open Solana` and `Verify address on
Ledger`. Default to the account path used by the selected wallet convention, with
an account picker and full derivation path in details. Never silently reinterpret
an existing account path. USB device paths and Bluetooth identifiers are connection
hints; the pinned public key authenticates the signer.

Use one review/export shell with method-specific authorization:

- Ledger: review request, confirm on Ledger, export signed transaction.
- iPad: review request, consent and external-key verification, device biometrics,
  export the typed approval evidence.

A Ledger profile does not automatically acquire the iPad profile's requirements.
A quorum that requires those extra proofs must reject a Ledger-only profile or
require a separately implemented compatible policy.

### Rust and FFI

Rust owns profile validation, immutable digests, registry/quorum compatibility,
exact signed bytes, chain/genesis binding, expiry and returned-signature checks.
Swift owns native UI, Secure Enclave and any iPad transport. The Ledger HID backend
belongs in a macOS-only adapter, not the shared iOS-linked FFI target.

Use explicit operations and proof types, not an unqualified `sign(bytes)` API:
`solana_transaction`, `ledger_offchain_enrollment` and `p256_local_approval` have
different verification rules and cannot satisfy one another's requirements.

Import `.vow` requests with profile ID/version/digest, quorum seat and expected
signer identity. Plain transaction dumps remain accepted, but require explicit
resolution to a compatible authorized profile and quorum. Never mutate transaction
bytes to add profile metadata after collecting a signature. Context not carried in
the Solana message is separate evidence; it has no on-chain enforcement merely
because it appears in the bundle. New public profile/quorum shapes need a new
schema version. Legacy imports bind only to their explicitly registered legacy
profile; ambiguous imports must not guess a default.

### Reusing solana-keychain

Source inspected: `/Users/ludo/Coding/solana-keychain`, clean revision
`ed68ba3232c99fa3ed3b57344e0b6e496aa08777`.

The Rust `ledger` feature uses `solana-remote-wallet` and `hidapi`, a serialized
hardware actor, exclusive operation claims, caller deadlines and local signature
verification. Integrate it first on macOS with Ledger-only backend features and a
compatible Solana SDK feature. Pin a release or source revision; do not ship a
mutable sibling-directory dependency or enable remote providers unnecessarily.

Set address confirmation true during enrollment. Read-only discovery must not
auto-open the Solana app. Launching an app can be enabled only after an explicit
connection/setup action. Preserve user rejection as a terminal result. A caller
timeout does not interrupt the underlying HID read or free the device; reject late
results and keep subsequent operations busy until the actor releases its claim.

The backend defaults to `m/44'/501'/0'`, the Ledger Live convention in the inspected
source. The four-component `m/44'/501'/0'/0'` is a different account, not another
encoding of the same identity. Pin and display the selected path and public key.

`sign_transaction` signs the serialized Solana message and verifies the signature
before attaching it. Off-chain `sign_message` instead signs a Ledger-specific
envelope. The inspected V0 header is 85 bytes for one signer, with an all-zero
application domain, and payload limits. An enrollment challenge must therefore
include explicit Vow domain separation, a fresh nonce and the profile/organization
binding in the signed payload; verification reconstructs the exact envelope.
Do not pass the existing long prototype JSON through this API and assume raw-byte
signing. Verify support on the actual released Solana app version before enabling
an off-chain enrollment proof. Lack of support must not silently enable blind
signing or substitute a different proof.

Real Squads approval transactions are the first production transaction target.
The current canonical JSON approval is a rehearsal artifact, not a Ledger-ready
Squads vote. Ledger clear-signing support for the actual approval instructions must
be tested. Do not enable blind signing by default or claim that iPad decoding is
Ledger clear signing.

### iPad transport boundary

The existing Rust HID backend is not an iPad transport. Ledger's current native
mobile SDK is a candidate for a Swift/native bridge. Its documentation explicitly
lists iOS Bluetooth support and labels the SDK alpha; treat it as a spike, not a
production transport commitment. Its older Swift BLE repository
is archived and should not become a new production dependency. Validate model,
firmware, SDK license/support, Bluetooth permissions and real Solana signing.

BLE peripheral communication is separate from internet access, but an all-radios-off
profile would disallow it. Keep those policies explicit and test the existing
network gate with the chosen transport. Do not promise generic iPad USB-HID access
because the port is USB-C. Scope the first integration to macOS USB; assess iPad
support separately and show unsupported combinations honestly.

## Open questions

- Must the first Ledger profile sign on the iPad, or is Mac USB acceptable initially?
- Is BLE acceptable for an offline Ledger profile, or must every radio stay off?
- Which actual Ledger model and released Solana app version should we validate?
- Which enrollment proof is supported on those versions, and who authorizes adding
  a second signing identity to an existing organization's member?
- Which on-chain policy binds distinct people and their allowed profiles? Squads
  counts signer keys; Vow's local one-seat-per-person validation alone cannot enforce
  that rule against a malicious membership update.

## Acceptance plan

1. Implement Rust profile/registration/seat types and versioned schemas. Test
   wrong owner, foreign organization, inactive profile, duplicate member/address,
   revoked or stale versions, changed policy and incompatible methods atomically.
2. Migrate the current local identity into one explicit legacy profile without key
   rotation. Keep existing public exports readable and reject ambiguous imports.
3. Build native Profiles and quorum seat pickers, with method/address summaries.
4. Add a macOS Ledger adapter using pinned solana-keychain. Test address confirmation,
   wrong path/key/message, corruption, partial signatures, rejection, unplugging,
   timeout/late results and exclusive-operation handling. Keep signing separate
   from broadcasting and preserve chain/genesis checks.
5. Construct and verify a real cluster-specific Squads approval transaction. Keep
   off-chain enrollment proofs separate from transaction signatures. Test both
   positive verification and cross-kind substitution rejection.
6. Verify supported device/app versions and on-device display on physical hardware.
   Evaluate the iPad native transport as a separate spike before promising support.

## Risks

Profile labels can conceal a weaker policy unless quorum bindings include the
actual keys and requirements. Several keys held by one person can falsely inflate
a threshold unless both membership configuration and enforcement account for it.
Ledger's trusted display is valuable but has instruction-specific limitations.
A host-side timeout is not device cancellation. A UI-only registry does not repair
the unfinished production bridge and evidence enforcement boundary.

## What we learned

2026-11-10: The local Ledger backend already has exact-message signature checks,
partial transaction handling, mocked actor tests and an upstream envelope
conformance test. Its transport and off-chain signing semantics prevent a direct
substitution for the current iPad P-256 approval function. The profile model is a
prerequisite for supporting both methods without conflating their guarantees.

References: [Ledger native mobile SDK](https://developers.ledger.com/docs/device-interaction/dmk-kmp),
[mobile Solana signer](https://developers.ledger.com/docs/device-interaction/dmk-kmp/how_to/solana_signer).

2026-11-10 implementation: [ADR 0009](../adr/0009-bind-signing-profiles-to-quorum-seats.md)
adopts immutable profile bindings. The apps now implement the catalog, quorum
pickers, profile sharing/import and separate authorization flows. macOS uses PR
358; iPad uses native BLE with Rust framing/APDUs. Target devices are Nano X, Nano
Gen5 and the owner's Flex. Off-chain approvals remain rehearsal evidence. Physical
acceptance and real Squads transaction/enforcement work remain open.
