# Proposed package contracts

Status: design sketch, 2026-11-09. Names below are logical fields, not a finalized
serialization or SDK. Produce golden vectors before implementing interoperable apps.

## Encoding and digests

Select a canonical binary encoding with explicit versioning and domain separation.
Reject duplicate keys, ambiguous numbers, unsupported critical fields, oversized
collections, trailing bytes and noncanonical encodings. Use integer base units for
amounts. Hash exact chain bytes, not a lossy JSON rendering or displayed labels.
Do not trust a package's declared digest without recomputing it.

Define an acyclic evidence structure. The unsigned approval core is hashed first;
device, YubiKey and provenance evidence refer to that core. The outer container
includes signatures without incorporating itself into its own signing digest.
Specifying an algorithm identifier does not permit arbitrary algorithm negotiation.

## Rust and Swift boundary

The production boundary is a generated, versioned C ABI, not the compatibility
spike's JSON subprocess interface. Keep its exports small and wrap them in Swift.
These are proposed contracts, not existing functions:

- Rust creates a bounded session from package bytes and a pinned project quorum policy.
  Swift receives a review model and opaque session ID, not permission to redefine
  the signed action or independently construct its semantics.
- After review, Rust prepares a signing request bound to that session: key ID,
  algorithm, exact message bytes, and authorization-policy identifier. Distinguish
  message-signing from digest-signing explicitly to avoid double hashing.
- Swift's asynchronous platform adapter returns public-key identity and signature
  bytes, or a typed cancellation/authorization failure. It never returns private
  keys or serializable enclave key handles to Rust.
- Rust verifies the signature, normalizes public signature encoding, and checks
  session/policy freshness before finalizing the evidence package. Reject responses
  for another session, key, algorithm or action. Platform-reported factor labels
  remain statements with the assurance limits in the threat model.
- Each Rust-owned output buffer has one matching Rust free operation. Input memory
  is borrowed only for the call. No Rust references, `Vec`, Swift objects or native
  exception objects cross the C boundary. Generated headers define fixed-width
  types and explicit byte lengths.
- Validate lengths, pointer/length combinations and handles at the boundary.
  Return stable error codes plus non-sensitive diagnostic text. Prevent Rust panics
  and Swift errors from unwinding across FFI; define invalidated-session behavior.
- Prefer a request/response state machine over callbacks into Swift while Rust
  holds a lock. Specify cancellation, duplicate completion and thread confinement.
  Run heavy work off the UI thread and invoke OS UI from the appropriate actor.
- Version the ABI independently from package schemas. Add cross-language vectors,
  lifecycle tests and sanitizer checks for every exported operation.

Core modules also support a headless Rust verifier. Platform adapters cannot
silently enable network retrieval or change policy when an input is unsupported.

### Implemented prototype ABI

`apps/apple/RustCore/vow.h` is the checked-in version-one header. Both native
targets link `vow-ffi` as a Rust static library through the `VowCore` Clang module.
Automated header generation and a packaged XCFramework remain future work.

| Export | Ownership and behavior |
|---|---|
| `vow_session_create_v1` | Returns an independent opaque numeric session. |
| `vow_session_destroy_v1` | Drops its in-memory state and pending approval. |
| `vow_dispatch_v1` | Borrows a valid input pointer and length for the call; returns owned UTF-8 JSON with `ok`, `data` or `error`. |
| `vow_profile_transaction_v1` | Bounded 68 KB native request; Mac-only SDK execution, owned JSON envelope, no session/key access. |
| `vow_string_free_v1` | Frees a dispatch result exactly once; null is permitted. |

Swift decodes renderable snapshots and owns presentation state. Rust stores the
ceremony, prototype proposal, enrolled public key, pending signing bytes and
receipt history. `prepare` binds the request and consent digest; `complete` checks
the session, request and returned signature against the registered key. Cancel or
state changes invalidate pending approval. App restart discards this prototype state.

Prototype file formats start with `vow.prototype.`. Current versions are
`vow.prototype.ceremony.v4`, `vow.prototype.proposal.v4` and
`vow.prototype.approval.v4`. Earlier versions are rejected without migration.
These formats have no on-chain execution path.

- Organization: `organization_id`, display name and `members`. Enrollment is
  represented by each member’s `ready` flag only in this rehearsal.
- Quorum: `id`, `name`, sorted distinct `member_ids` and `threshold`. IDs must
  reference enrolled members of this organization; threshold is between one and
  the selected-member count. Quorums are immutable and scoped to an organization.
- Project: `id`, `name`, `quorum_id`, `chain` (`devnet` or `mainnet`), referencing an existing organization quorum.
- Proposal: binds `organization_id`, `project_id`, `quorum_id` and `quorum_digest`.
  Imports must match the active project’s exact policy.
- Prepared approval: signs those identities and policy digest, the full quorum,
  request digest and consent digest. Receipts preserve the project and quorum.

The quorum digest covers a domain tag, organization ID and complete quorum.
The enrollment fingerprint covers a separate domain, organization ID and roster,
excluding projects and quorums. New project creation cannot reset enrollment.

Workspace commands are `create_organization`, `select_organization`,
`create_project` and `select_project`. Selection uses `id`. Organization creation
uses `name` and starts with no members, quorums or projects. A new project requires
`name`, explicit `chain` (`devnet` or `mainnet`), and exactly one of:

```json
{"quorum_id":"an-existing-organization-quorum-id"}
```

```json
{"quorum":{"name":"Treasury signers","member_ids":[1,2,3],"threshold":2}}
```

The second form creates a named quorum and project atomically. Invalid creation
leaves state unchanged. Neither form changes enrollment or existing quorums.
Snapshots return available organizations/projects, all organization quorums,
active `quorum` and `quorum_digest`, and project-filtered receipts. Context changes
cancel pending authorization, including switching away and back.

`explanation_input` accepts the current request `digest`, returning `summary`,
`instructions` and a bounded `prompt`. Only validated transfer facts enter the
prompt. Free-form request titles, notes and recipient names are excluded; model
output never enters `prepare` or `complete`.

## Organization enrollment manifest

- Protocol version, organization ID and enrollment epoch.
- Stable member identities, device public keys and key types.
- Identity-evidence references, enrollment nonces and witness signatures.
- Enrollment, device replacement and revocation authorities and recovery rules.

The first trust anchor comes from in-person digest comparison, not a key supplied
alongside an otherwise untrusted manifest. Production imports must authenticate
these credentials and cannot treat the prototype’s `ready` flag as evidence.

## Project quorum manifest

- Organization, project and reusable quorum identities.
- Quorum policy digest, distinct enrolled-member references and approval threshold.
- Chain, network, multisig and vault identities and program versions.
- Factor requirements, format-pack trust roots and allowed programs and limits.
- Policy epoch, previous manifest digest, recovery and upgrade rules.
- Authorized configuration signatures and referenced enrollment credentials.

A quorum may be referenced by multiple projects, but vault/action/replay domains
remain project-specific. Changing policy requires an explicit authorized transition.

## Proposal package

- Protocol version, organization, project, quorum and policy references, intended member or audience.
- Unique request ID, chain identity, multisig and vault, proposal address/index.
- Exact bytes to sign, or adapter action bytes and an explicit signing-mode tag.
- Inner executable action bytes and their digest, including every instruction.
- Required format-pack identifiers and digests.
- Context entries with account address, data digest, source, checkpoint and proof
  or stated trust basis. Labels and human descriptions are explicitly untrusted.
- Validity/replay mode: durable nonce binding, persistent proposal sequencing,
  or a fully specified execution-side expiry rule. Do not interchange these modes.
- Optional authenticated proposer identity, which does not make the action safe.

Show proposal meaning before authorization. Require canonical correspondence
between the inner action reviewed and the actual outer approval/execution path.

## Approval core and evidence

- Domain and version, request ID, organization, project, quorum, chain, multisig, policy epoch and digest.
- Proposal identity, exact chain message or action digest, and reviewed-context digest.
- Member/key identity and required format-pack digest set.
- Factor-policy identifier and decision: approve or reject.
- Replay nonce/sequence and validity rules appropriate to the signing route.
- Optional consent artifact digest and explicit evidence requirements.

Attach typed device approval, optional chain-compatible Ed25519 signature,
YubiKey evidence, ceremony certificate reference and optional App Attest evidence.
Define precise signed preimages for each. A bare boolean such as `face_id=true`
or `handwriting_match=true` is an application statement, not independent evidence.

Raw handwriting and passport data are excluded by default. A hash alone does not
prove the consent was freshly captured or matched. Keep private artifacts encrypted
locally if policy requires retention. Export only deliberate disclosures.

## Format pack

Pack version and digest; chain and program IDs; supported program versions and
instruction discriminators; bounded field layouts; account-role rules; permitted
semantic-handler identifiers; display templates; issuer signatures; supersession
and rollback policy. Include deterministic test vectors. Team policy determines
which publisher keys and versions are accepted. No pack may override native safety
checks, silently fetch dependencies, or introduce executable plugins.

## Verification result

Report separately: chain signature validity, member identity binding, policy and
epoch validity, action interpretation, required factor evidence, app provenance,
context freshness, quorum, and execution status. Distinguish unavailable evidence
from verified evidence. Unknown mandatory evidence rejects the approval.

Counters used by evidence verifiers need shared persistence and out-of-order
delivery rules. The chain's proposal/nonce consumption remains authoritative for
execution replay prevention; an App Attest counter is not a replacement for it.


## Implemented transaction review contracts, 2026-11-09

`vow.prototype.transaction.v1` is an 8 MB maximum JSON `.vow` file with
`purpose: rehearsal_only`, a v4 proposal, independently recomputed action digest
and an exact execution-plan description. `execution_ready` is false. Optional
`transaction_intent` context contains exact transaction hex, native origin, wallet
chain, required-factor flags, reproduction and IDLs. Required unsupported factors
block approval in Rust and Swift. A plan entry is not an executable instruction.

`vow.prototype.reproduction.v1` pins Surfpool SDK 1.7.0 and runtime fingerprint
`litesvm-0.18.1-agave-4.3.2`. It includes wire hash, target chain, synthetic source,
context slot, pre-state account fixtures, explicit absent addresses, disabled
signature/blockhash-check flags, profile and expected result. Independent replay
compares compute units, logs and result balances. Executable downloads are rejected.
Caps: 1232 transaction bytes, 128 snapshot accounts, 32 output addresses, 8 MB
encoded account data, 2 MB profile. There is no RPC fallback in `vow-replay`.

`inspect_transaction_dump` accepts serialized full transactions, including unsigned
signature placeholders. Native import converts binary to hex. Text may be hex,
base64, RPC `[base64,"base64"]`, JSON `transaction_hex` / `transaction_base64`, or
`transaction: [base64,"base64"]`. Instruction-only dumps and bare messages are
unsupported. The inspector never signs. Unresolved lookup addresses and unknown
instructions remain explicit. A network absent from raw bytes is not inferred.

`vow.prototype.inspection.v1` wraps the same bytes with optional companion context;
it is also exportable as `.vow`. It does not contain an enrolled policy or approval.
Optional `blockhash_context` fields are `blockhash`, `chain`, `genesis_hash`,
`observed_at_unix_ms`, `context_slot`, `observed_block_height`,
`last_valid_block_height`, `estimated_expires_at_unix_ms`. The estimate is observation
plus `min(remaining heights × 400 ms, 60 seconds)`; validate hash, chain, genesis and
arithmetic. Observation is a coordinator claim, not authenticated chain evidence or
the precise blockhash creation time. Missing context yields no timer. A matching
hash can still expire earlier than the estimate; offline clock changes are another
reason this cannot establish on-chain validity.

Mac retrieval of a metadata IDL is opt-in. Artifacts bind canonical metadata PDA,
owner, complete raw account bytes, program address, chain/genesis, source context
slot and JSON content SHA-256. Inline UTF-8 JSON only, max 1 MB after decompression;
none/gzip/zlib accepted. URL/external payloads are rejected. An IDL alone never
installs an approval-capable decoder or authenticates account state.

Rust hashes sorted canonical JSON so dependency feature unification cannot change
signed object key order. ABI inputs are capped at 20 MB to accommodate escaped file
contents, and outputs use `vow_string_free_v1` exactly once.

Sample v4 proposals may include `demo_expires_at_unix_ms`, generated five minutes
after sample creation and bound into the proposal digest. It drives the clearly
labelled Demo status-bar timer and makes no chain-validity or authorization claim.
Real transaction files do not populate this field; their timer uses the separately
validated blockhash observation context. Missing expiry context is shown explicitly.

`check_consent` receives the reviewed `digest` and exact `ink` hex. It validates the
active request, quorum, required factors, local lifetime and ink bounds, returning
`proposal_digest` and `consent_digest`. It does not create a key, signing session or
approval, and does not mutate state. `prepare` repeats the same checks at explicit
authorization. Handwriting identity matching is not implemented by this preflight.

## Offline device enrollment, version 1

`prepare_device_enrollment` accepts two distinct compressed P-256 public keys and
`key_source`. Rust generates a 32-byte nonce and canonical JSON bytes with domain
`vow.device-enrollment.v1`, purpose `offline_device_enrollment_only`, PIV slot `82`,
PIN policy `always` and touch policy `always`. Swift signs these exact bytes with
the YubiKey and then the protected device key. `verify_device_enrollment` requires
both raw 64-byte ECDSA signatures and rejects noncanonical or unsupported payloads.

The public `Vow-device-enrollment.json` record contains the message, both signatures
and the SHA-256 fingerprint of the compressed device public key. It explicitly
states `on_chain_registration: not_registered` and
`hardware_attestation: not_verified`. Key source, PIV policy and origin are local
adapter observations, not remotely attested facts. No private-key representation,
PIN, management key or YubiKey serial is exported.

For local prototype approvals, `register_key.local_security_key` pins the enrolled
YubiKey public key for the Rust session. It cannot subsequently be changed or
removed. Canonical approval bytes include that public key. Completion requires its
signature over the same exact bytes and exports `local_security_key_proof` beside
the device signature. Missing, substituted and wrong-message proofs fail. This
local proof does not implement the separate production attestation guard or satisfy
imported requests requiring unsupported chain-verifiable evidence.

## Offline FIDO enrollment, version 2

`prepare_device_enrollment` accepts `security_key_kind: fido2` and the opaque
hexadecimal `credential_id` in addition to the two public keys and source. It
returns canonical `vow.device-enrollment.v2` bytes with RP ID `vow.invalid`, policy
`user_verification_required` and `user_presence_required`, and an empty legacy slot
field. The nonce remains random. Version 1 PIV canonical bytes remain unchanged.

The device signs the canonical message directly. The security key signs raw CTAP
assertion bytes: authenticator data concatenated with SHA-256 of the message.
`verify_device_enrollment.security_key_authenticator_data` is required for v2.
Rust accepts exactly 37 bytes with the pinned RP hash and flags `0x05`: UP and UV,
no backup eligibility/state, no attested data or extensions. It verifies the
security-key P-256 signature and then the device signature. The public export
retains authenticator data alongside both proofs. Factory hardware origin and
on-chain registration remain explicitly unverified.

`register_key` accepts `local_security_key_kind: fido2` and
`local_credential_id`; a public key is mandatory for this method. Canonical
approval bytes bind all three fields. Completion requires the FIDO authenticator
data and signature over the exact prepared message hash. A session cannot remove
or downgrade the pinned factor or change its credential identifier. Missing UV,
wrong RP, wrong message, unsupported flags and raw-signature substitution fail.

The discoverable credential uses a fixed opaque user handle, SHA-256 of
`vow.offline.security-key.v1`. Lookup is independent of a device/vendor ID. This
means one Vow credential per physical key, not a person or account identity. It
does not reconstruct the separate Secure Enclave key. The prototype's reserved
RP namespace is not a browser WebAuthn origin or an Apple associated-domain claim.


## Native external-key WebAuthn enrollment, version 3

`native_security_key_configuration` reports the compile-time RP and whether it is
configured. No imported request can select an RP. `native_registration_challenge`
accepts `device_public_key` and returns a random challenge and per-registration
user handle. `parse_native_registration` accepts `challenge_hex`, `credential_id`,
`client_data_json_hex` and `attestation_object_hex`. All are hexadecimal byte
strings. It validates the registration origin, type, challenge, RP hash, UV/UP,
credential identifier and ES256 COSE public key. It does not certify factory origin.

`prepare_device_enrollment` accepts `security_key_kind: webauthn` and
`credential_id`, emitting `vow.device-enrollment.v3` with the pinned `rp_id`.
The device signs canonical bytes directly. The native assertion challenge is
SHA-256 of those bytes. The external key signs authenticator data concatenated
with SHA-256 of the exact returned client JSON. `verify_device_enrollment` requires
`security_key_authenticator_data` and `security_key_client_data_json`, both hex,
alongside both signatures. Client type must be `webauthn.get`, origin must be the
pinned HTTPS RP, cross-origin must be false, and decoded challenge must match.
Assertion authenticator data is exactly 37 bytes with flags `0x05`.

`verify_native_assertion` checks this proof before the enclave operation.
`register_key` pins kind `webauthn`, public key and credential ID. Prepared approval
bytes bind `local_security_key_rp_id` as well. Completion requires both raw native
proof fields and verifies them again. Public exports retain the client JSON and
authenticator data. Legacy v1 PIV and v2 direct CTAP records remain accepted; no
session may replace or downgrade its enrolled factor. A changed build RP cannot
silently migrate a v3 enrollment.

## Offline member-address derivation

`derive_member_address` accepts `public_key`, a lowercase hex encoding of a valid
33-byte compressed P-256 public key. It returns `vow.member-address.v1` with
`address`, `bump`, `bridge_program`, `device_public_key`,
`signer_execution_scheme: external_account`, `registration_status: not_checked`
and `network_binding: same_program_id_same_address_across_clusters`.

The address is the pinned bridge PDA for seeds `passkey` and SHA-256 of the
compressed device public key. It is distinct from the legacy execution-account
PDA. This pure operation does not contact an RPC, initialize an account, establish
cluster deployment compatibility or certify the key's hardware origin.

Each prepared approval also binds a fresh 32-byte random `nonce` in its canonical
signed message. The in-memory revision counter alone is not a replay boundary
across app restarts. Failed completion consumes the pending attempt; prepare a new
attempt and obtain both signatures again.

## Hardware-key selection policy

`hardware_key_policy` accepts `direct_fido` and `piv` capability states:
`supported`, `unsupported`, `incompatible`, `failed` or `unavailable`.
`piv_ready` and `native_configured` are required booleans. Optional
`enrolled_method` is `fido2`, `piv` or `webauthn`. Unknown fields and contradictory
PIV reports are rejected. The iPad sets `piv_ready` only after checking an existing
hardware-generated P-256 credential, always-PIN and always-touch policies, a
nonfactory PUK/management metadata. A factory PIN is permitted under the explicit
automatic-PIN policy in `DESIGN.md`; it is not an independent knowledge factor.

The `vow.hardware-key-policy.v1` response contains nullable `method`, `state`,
`reason` and `writes_permitted: false`. States are `selected`, `setup_required`,
`unsupported`, `blocked` or `pinned`. An enrolled method is never replaced.
A probe failure cannot fall back. This pure policy authorizes no credential writes
and does not authenticate hardware. Capability observations remain untrusted inputs.

The native `vow.hardware-key-diagnostic.v1` export includes firmware, transport,
probe state, nullable error detail, observed available method, setup requirement,
current enrolled method and policy decision. It contains no PIN or private key.
A failed probe reports `Check incomplete`; it does not assert lack of support.

## Signing profiles, version 1

- `create_ipad_profile`: `name`, enrolled `member_id`, and the public `enrollment`
  proof object. Both keys are verified and the policy/address derived from it.
- `begin_ledger_profile`: `name`, `member_id`, device-confirmed `address` and
  `derivation_path`. Returns a canonical Vow enrollment `message` for the Ledger
  envelope. A fresh nonce and five-minute pending challenge bind owner and identity.
- `finish_ledger_profile`: `signature_hex`. Consumes the pending enrollment even
  on failure; verifies the exact Ed25519 envelope and stores a local profile.
- `cancel_profile_enrollment` clears the pending challenge.
- `revoke_profile`: `id`. Blocks local profiled-quorum approvals; no chain update.
- `import_signing_profile`: `profile`. Validates scope/proof and refuses conflicting
  IDs or resurrection of a locally revoked record.
- `restore_profile_catalog`: public `profiles` array for startup persistence. This
  public prototype store is not an authorization or anti-rollback mechanism.

Snapshots include `profiles`, with immutable `digest` and local-registration status,
and a JSON-string `profile_catalog_export`. A shareable record uses
`vow.prototype.signing-profile.v1` with a `profile` field and is accepted by `import`.
A profiled quorum creation supplies `profiles: [{member_id, profile_id}]` instead
of `member_ids`; Rust resolves exact versions/digests/addresses. Existing legacy
quorums are not implicitly upgraded. Profile-enabled ceremony/proposal/approval
records use version 5. A ceremony v4 with profiles or seats is rejected.

`prepare_ledger_approval` takes a quorum-bound `profile_id` and returns `session`,
`message`, and `message_hex`. `complete_ledger_approval` takes `session` and
`signature_hex`. The proof is an off-chain rehearsal, not a transaction signature.
It must verify against the exact Ledger envelope, current request and unexpired
pending profile. Completion is one-shot. `complete` rejects Ledger pending state;
`complete_ledger_approval` rejects P-256 pending state.

`vow_ledger_v1` is bounded to 8 KB and runs outside the workspace mutex. On macOS it
accepts explicit `connect`, `sign_enrollment` and `sign_approval` operations with a
hardened Solana derivation path. Signing requires the expected account and exact
operation domain before any hardware access. The result uses the ordinary owned
JSON/free convention. It has no transaction-broadcast operation.

Mobile helpers `ledger_mobile_commands`, `ledger_mobile_response`, `ledger_ble_frames`
and `ledger_ble_decode` construct and validate bounded public-key/off-chain APDUs,
response status/type, frame sequence/length and final signature. They expose no
key-generation, PIN, recovery, management or arbitrary APDU operation. Desktop HID
dependencies are absent from the iOS FFI graph.

## Personal identities and local archive

`PersonalIdentity` v1: `id`, `version`, `name`, `kind`, `address`, `public_key`,
`derivation_path`, `proof`. It deliberately has no organization/member fields.
`begin_personal_ledger` takes name/address/path and returns canonical `message`.
`finish_personal_ledger` consumes the pending five-minute challenge and requires a
verified Ledger off-chain signature. The domain is `vow.identity.enrollment.v1`,
separate from organization profile enrollment and request approval. `create_personal_ipad`
requires an existing verified dual-key `enrollment` record. Cancellation consumes a
pending challenge. `restore_personal_identities` validates the entire bounded array
and unique IDs before replacement; `import_personal_identity` merges one verified
record and rejects a changed cryptographic identity under an existing ID.

Share wrapper: `{ "format": "vow.personal-identity.v1", "identity": { ... } }`.
Snapshots include `personal_identities` and `personal_identities_export`, independent
of the selected organization. `register_personal_identity` takes an identity ID and
an already-enrolled member ID in the active organization, creating an organization
profile v2. It embeds the identity proof and pins its key and policy; ceremony v5
and quorum-seat validation still apply. This local registration is not organization
authorization or on-chain activation. Legacy profile v1 remains supported.

Apple archive schema 1 stores two Rust-owned JSON strings, `personalIdentities` and
`organizationProfiles`, bounded to 8 MiB. It never serializes a Swift presentation
projection as a cryptographic record. It contains no private keys, PINs or active
authorization state. Missing, unsupported and corrupt archives are distinct outcomes.

## Full local reset

`reset_all` returns an empty session: no organizations, projects, members, quorums,
personal identities, registrations, requests, receipts, public signing keys, external-key
bindings or pending operations. It does not reload the sample workspace. The existing
`reset` action remains the Mac sample-session reset, which preserves profile catalogs.

The Apple full-reset coordinator records explicit reset intent in nonsynchronizing
Keychain storage, clears app data and exports, deletes the device identity record,
clears cached key objects, calls `reset_all` and completes the reset marker. Startup
finishes a pending authorized reset before loading identities. The public archive's
optional `workspaceCleared` flag only controls workspace initialization; it has no
key-deletion authority. Keychain deletion failures fail closed without silently
creating a replacement. User confirmation precedes this operation.

## Generic clipboard review and nearby transport

`vow_profile_transaction_v1` also accepts:

```json
{"mode":"clipboard","chain":"solana:devnet","data":"<serialized transaction as hex, base64 or JSON>"}
```

The native request limit is 68 KB; clipboard text is limited to 64 KB. The
selected chain must be `solana:devnet` or `solana:mainnet`; RPC endpoints come
from the fixed chain configuration. Explicit conflicting chain/genesis metadata
is rejected. Existing signatures and transaction bytes are preserved.

The result has `filename`, `package`, `wire_digest`, `network_explicit`, `chain`,
`instruction_count`, `simulation` and `execution_ready: false`. `package` uses
`vow.prototype.inspection.v1`, with optional `simulation` evidence:

- `format: vow.simulation.v1`, chain/genesis and exact transaction SHA-256.
- `rpc_slot_start`, `rpc_slot_end`, `observed_at_unix_ms` and non-atomic state source.
- `fork_slot`, `clock_unix_ms` and `clock_source`, either RPC block time or Mac clock.
- `signature_checks: false`, `blockhash_checks: false` and the runtime `result`.
- `snapshot`, including program/lookup accounts, and optional instruction-depth
  `profile`. `profile_context: followup_local_execution` distinguishes that later
  execution from the first simulation and its pre-state.

Evidence is capped at 6 MB and 1,024 snapshot accounts; the entire file is capped
at 8 MB. The importer checks byte/network binding and fixture schema. Evidence is
untrusted review context, not independent replay verification or approval authority.
No blockhash observation is invented for bare transaction bytes.

Nearby discovery uses Bonjour `_vow-review._tcp`. The application protocol uses
one-byte packet kinds: commitment, hello, transcript signature and sealed message.
A hello contains protocol version 1, role, 32-byte Ed25519 public identity,
32-byte X25519 ephemeral public key and 32-byte random nonce. A domain-separated
SHA-256 commitment precedes reveal. The signed transcript fixes Mac/iPad ordering.
An X25519/HKDF-SHA256 key encrypts messages with ChaCha20-Poly1305. Confirmation,
file payload, file-digest receipt and receipt acknowledgement all use that key.
Counters are strictly increasing per direction and per session. First pairing
requires matching codes and confirmation at both endpoints; later connections
must prove the stored public key. Names never authorize delivery.

## Native Apple document package, version 1

Status: implemented prototype, 2026-11-11.

A `.vow` document is a regular file containing a flattened native `FileWrapper`,
declared as `org.vow.transaction` conforming to `public.data`. Its frame is the
8-byte magic `56 4f 57 44 4f 43 00 01`, a 32-bit little-endian body length, then
Foundation's `serializedRepresentation` of the directory wrapper. Require exact
length and supported version before decoding. The decoded root must be a directory.
This gives Files, AirDrop and file providers a real byte size instead of an
unknown directory-package size. Finder and Files present it as one document.
Mac uses a complete document-page icon; iPad uses the V badge on the OS page.

- `Manifest.json`: `format: vow.document.v1` and a `files` map containing each
  member's exact byte `size` and lowercase SHA-256 `sha256`.
- `Request.json`: the exact existing Rust JSON payload, preserved byte for byte.
- `Transaction.bin`: optional exact transaction bytes extracted from that payload.
- `Simulation.json`: optional simulation metadata and profile, excluding snapshot.
- `Accounts.json`: optional simulation snapshot.

The supporting files are derived copies. Import verifies their manifest hashes and
agreement with `Request.json`, then passes only the original payload to Rust.
Checksums provide integrity checking, not signer authentication or execution authority.
No package changes a signing digest, signing gate, or offline requirement.

Reject unknown members, symbolic links, nested directories, missing members, stale
attachments and unsupported versions. Ignore only bounded regular `.DS_Store` and
AppleDouble metadata files for known members, at most 64 KiB each. Bound the manifest to 16 KiB, the original
payload to 8 MiB, and both the encoded document and materialized package to 16 MiB. Legacy directory
packages remain readable, but new exports are flattened files. Existing flat
JSON `.vow` files and simple transaction dumps remain readable. Nearby transfer
still authenticates and encrypts the bounded original payload and reconstructs the
native package at the receiver; it does not unpack an untrusted archive.


## Shared snapshot execution

`vow_profile_transaction_v1` accepts bounded UTF-8 JSON up to 9 MiB. The
`mode: "offline"` request carries `chain` and the original `package` string.
Rust validates the package, wire digest, selected chain and genesis, fixture
encoding, and recorded clock before creating the SDK fork. No remote endpoint
is accepted in this mode. The runtime limits wire bytes to 1,232, account entries
to 1,024 and total encoded fixture data to 6 MiB. The SDK binds only to loopback
and starts with `offline(true)` and no funded application payer.

The result carries `engine`, `source: "local_snapshot_execution"`, `wire_digest`,
`offline: true`, the simulation `result`, a separately obtained instruction
`profile`, `account_states`, `review_context_digest`, and `fixture_count`. The context
digest binds the complete normalized review package, including fixtures and clock;
the wire digest alone does not distinguish two snapshots of the same transaction.
Clients discard results when either context or selected chain changes.
Profile account changes come from the follow-up
local execution. Signature and blockhash checks are disabled, original wire bytes
are preserved, and `execution_ready` remains false. Managed sysvars come from
SDK clock reconstruction; they are not overwritten through account cheatcodes.
The legacy rehearsal validator also uses this runtime but retains its narrower
executable-loading policy and compares balances, compute usage and runtime logs.
Old runtime display labels are accepted only for legacy evidence compatibility.

`account_states` contains whole-transaction and per-instruction transitions. Each
account has exact string-valued field diffs, normalized before/after JSON, change
kind, data-change status and a decimal-string lamport delta. Parsed fields come
from the same local execution profile with `jsonParsed` encoding; metadata must
match its base64 counterpart. Unsupported account data retains its length/hash
and the original profile bytes for a complete paginated hex diff. Large integers
are preserved without conversion through floating point.
