# Vow design

Status: proposed production design, 2026-11-09. Native local prototypes implement a
subset: sample enrollment, organizations, reusable quorums and projects, file export/import, full-screen iPad
approval, optional local explanations, P-256 signing and Rust verification. Passport reading, pairing, durable storage and chain submission are
not implemented. See [README.md](../README.md) to run the current applications.
Open choices are tracked in [RFD 0001](rfd/0001-signing-and-enforcement.md).

The connected Mac has a capture-only WKWebView wallet provider and native
Review → Replay → Checks → Export preparation flow. Rust verifies the bounded
unsigned SOL-transfer profile. The Mac embeds Surfpool; the iPad links only the
offline LiteSVM replay layer. Reproduction fixtures are synthetic and are not chain
proofs. File formats and limits are in [CONTRACTS.md](CONTRACTS.md).

Plain transaction dumps are a separate supported input. An installed wire inspector
shows every instruction and its accounts. Payment Channels open/distribute layouts
are decoded from pinned program source. This inspector has no signing authority:
missing account state, unresolved lookups, unknown instructions or missing guard
verification cannot become an approval. Native file sharing offers raw bytes and
an optional `.vow` companion envelope.

Each project pins Devnet or Mainnet and its genesis hash. All actions and approval
preimages bind that identity. Explicit Mac RPC reads use that project's fixed endpoint
and verify genesis first. Transactions without chain metadata are labelled as
using the selected project's assumed context. No automatic iPad retrieval exists.

Optional blockhash context records observation time, context slot, observed block
height and last valid height, bound to the exact wire blockhash and chain. The
countdown is a conservative estimate, not chain validity. A stored Squads action
outlives its capture transaction's recent blockhash and requires a freshly constructed
outer execution transaction. See [RFD 0003](rfd/0003-guard-and-reproduction.md).

## 1. Use case U: review and approve an action

A member receives a proposal on their dedicated iPad. The device explains what
the team will authorize, obtains handwritten consent and required factors, and
exports an approval. A coordinator gathers enough approvals and submits the
action. The coordinator never receives members' private signing keys.

The thing being reviewed is the action or message, not a signature. Vow must
distinguish an inner vault action from an outer transaction that records a vote.
Showing only “approve proposal 42” is insufficient if proposal 42 moves funds.

1. **Import.** Accept a bounded Vow package through Files, removable media, QR,
   or an explicitly enabled AirDrop workflow. Treat every imported byte as hostile.
   Transport authenticity is not proposal authenticity.
2. **Validate.** Check package version, organization, project, quorum, member, chain, multisig address,
   policy epoch, proposal identity, exact message digest, and replay identifiers.
   Recompute them locally. Require the installed decoder and necessary context.
3. **Inspect.** Explain destinations, assets and raw amounts, decimals provenance,
   fees and caps, writable accounts, authority changes, approvals/delegations,
   program upgrades, nonce use, and unexpected signers. Show every instruction.
   Highlight differences from pinned policy and earlier approvals.
4. **Authorize.** Capture an explicit handwritten confirmation of the displayed
   action. If policy requires it, obtain a registered YubiKey signature over the
   same approval digest. Invoke the OS-protected signing key with fresh biometric
   authorization. The iPad mini uses Touch ID; compatible other iPads use Face ID.
5. **Sign.** Revalidate the immutable reviewed bytes and policy immediately before
   key use. Changing the proposal, context, decoder, or policy clears authorization.
6. **Export.** Show “Approval ready”, then offer the system share sheet and a
   file export fallback. Include cryptographic approval and configured evidence.
   Keep the result for retry without producing a new approval automatically.
7. **Verify and execute.** The collector checks evidence, signer uniqueness and
   threshold. The chain adapter, if selected, independently enforces required
   signatures, policy epoch, action binding, and replay protection. Return an
   execution receipt separately; exporting an approval does not mean execution.

User-facing statuses are “Needs a format update”, “Missing verification context”,
“Ready to review”, “Approval ready”, and “Executed”. No raw-sign-anything escape
hatch is proposed for the first release. Technical details are available below
the action summary, including full addresses and the message digest.

## 2. Offline interpretation and trust

The native parser understands the chain's wire message. Program-specific decoders
explain instruction semantics. An IDL gives field structure but does not establish
what a program actually does. Program identity, allowed operation semantics, and
upgrade policy must also be trusted.

Install signed, versioned format packs during setup or a deliberate maintenance
session. Use bounded declarative schemas and reviewed built-in semantic handlers.
Do not execute downloaded native code or arbitrary decoder scripts. Unknown or
unsupported instructions block signing, including unknown accounts or versions
needed to interpret a known instruction. Labels from the proposer are untrusted.

Solana address lookup tables, token metadata, multisig proposal accounts, program
versions, and nonce accounts may require external context. A file containing RPC
JSON is not a proof of chain state. Initially support a deliberately small action
set and pin addresses and asset metadata in the team policy. Reject unresolved
lookup tables. Expand only with an explicit trusted snapshot or verified-state
scheme and freshness policy. Simulation is advisory and may become stale.

Offline devices cannot independently know the current chain head, membership,
revocations, or program code. Expose the last accepted policy epoch and checkpoint.
Have execution check current conditions, nonce consumption, and state preconditions.
Bind recipient and limits in actual instructions where possible. A locally stored
timestamp is not a trusted freshness oracle.

## 3. Signing routes to evaluate

| Route | Compatibility | Security boundary |
|---|---|---|
| A: software Ed25519, hardware-protected storage | Candidate for standard multisig member approvals | Ed25519 secret enters app memory during use. Hardware protection of storage does not make Ed25519 signing occur inside Secure Enclave. |
| B: Secure Enclave P-256 approvals | Needs a compatible wallet or on-chain adapter | Nonexportable P-256 key signs a domain-separated action authorization. A relayer pays for and submits the outer transaction. |
| C: external hardware Ed25519 signer | Depends on device and iPad transport | Secret stays on external hardware; iPad supplies review and additional approval evidence. Independent trusted display must be evaluated. |

Preferred direction for hardware-backed custody is B, contingent on feasibility
and integration review. Existing multisig support may favor A or C. Do not claim
that a P-256 precompile automatically makes a standard multisig accept P-256 members.
A PDA adapter might bridge some systems, but signer checks, CPI support, proposal
binding, and replay behavior require source inspection and an end-to-end proof.
Follow-up source inspection found an existing P-256 WebAuthn External Signature
Program that provides this kind of PDA signer bridge. Evaluate it first; details
and its short slot-hash validity window are in [RESEARCH.md](RESEARCH.md).

For A, a normal transaction signature covers exact chain message bytes. It cannot
also cover an arbitrary Vow envelope. Use a distinct, domain-separated evidence
signature linked to that message and signature. For B, sign the Vow action digest;
the adapter verifies it before executing the bound action or recording approval.

Ordinary recent-blockhash transactions have a short validity window. An offline
workflow needs a tested durable-nonce path, or approvals over a persistent proposal
and action digest with an online executor assembling the outer transaction. That
executor must not gain discretion to replace the approved action. Updating a
blockhash after raw transaction signing invalidates its signature.

## 4. Organization enrollment and project setup

An organization owns members, their enrollment records, reusable quorums and
projects. Enrollment and approval policy are separate lifecycles, as recorded in
[ADR 0002](adr/0002-organization-enrollment-and-project-quorums.md).

- **Organization member:** a person with a stable organization-scoped identity.
- **Enrollment:** the physical ceremony that binds the member to their device key
  and identity evidence. Each member completes it once for normal use across that
  organization’s projects. Creating a project or quorum never repeats enrollment.
- **Quorum:** an organization-owned, named set of enrolled members and an approval
  threshold, such as two approvals from Alice, Bob and Carol. It can serve several
  projects. The organization does not have a single global approval threshold.
- **Project:** an organizational unit with exactly one selected quorum. On creation,
  choose an existing quorum or select enrolled members and a threshold to create
  a new one. Other organization members are not implicitly project signers.

For example, Treasury and Grants can reuse the same two-of-three quorum.
Research can use a separate two-of-two quorum drawn from already enrolled members.
No member attends another ceremony for any of these project creations.

### Physical enrollment

1. Install and activate the reviewed apps and provision decoder assets before
   disconnecting the iPads. Agree organization enrollment and recovery rules.
2. Each member generates their own device keys and an enrollment nonce. Export
   public keys and proof of possession only. Compare fingerprints on the member’s
   own device. The organizer never assigns or receives a private signing key.
3. Read and verify passport evidence with pinned trust anchors, using Active
   Authentication where supported. Check the person against the passport in person.
4. Bind the identity check to the member, organization, enrollment nonce and device
   key. Witnesses independently confirm the binding. This credential is independent
   of any particular project or approval threshold.
5. Capture handwriting references if required and register optional YubiKey public
   keys with fresh proof of possession. Keep private artifacts on the member’s iPad.
6. Compare and confirm the enrollment transcript on independent devices. Preserve
   public evidence and recovery instructions. Adding another member enrolls only
   that member and does not reset existing enrollments.

### Project and quorum setup

1. Name the project and choose a reusable quorum or compose a new one from enrolled
   members. Select its required approval threshold explicitly.
2. Pin the quorum’s identity, member set, threshold and policy digest to the project.
   Confirm project-specific vault, chain, factor policy, limits and recovery rules.
   Enrollment evidence is referenced rather than recaptured.
3. Provision the project configuration to the relevant offline iPads. Independently
   verify the multisig authorities and run an approval rehearsal before real use.
4. Bind every proposal and approval to the organization, project and exact quorum
   policy digest. Count distinct authorized quorum members, not arbitrary organization
   members. Reusing a quorum does not share proposal identities or replay state.

Prototype quorums are immutable. A new signer set or threshold creates a new
quorum, leaving existing projects unchanged. Reassignment of an existing project,
revocation, device replacement and quorum-policy updates require a separately
specified authorized transition and replay invalidation protocol before production.
They are not reasons to repeat enrollment during routine project creation.

Passport integration is optional identity evidence, not a transaction signing
factor. Reuse Passport's reader and native PKI crates behind a narrow interface;
validate export completeness and host-driven challenge support before reuse.
Passport's current development ZK credentials are unsuitable for production trust.
An offline Vow iPad must not depend on Passport's online registry sync. A future ZK
integration must bind the proof to the Vow key and ceremony and address trusted
roots, freshness, revocation, and production proving keys.

## 5. Factors, evidence, and enforcement

Handwriting starts as explicit consent capture. Matching is experimental until
measured against skilled imitations, natural variation, and accessibility needs.
App code can enforce the matching step, but Secure Enclave cannot run that matcher.
Do not derive cryptographic keys from handwriting or export raw strokes by default.

Keychain/Secure Enclave access controls must enforce biometric use at key access,
not just an earlier successful UI prompt. Decide whether passcode fallback is
permitted and test lockout, re-enrollment, app backgrounding, and prompt reuse.
Biometric authorization does not attest the human-readable transaction display.

A YubiKey must sign a fresh, action-bound challenge, not merely be detected as
plugged in. Compare PIV and FIDO2 transport/API paths on physical iPads. For FIDO2,
verify RP binding, user-presence/verification flags, and challenge construction.
No TOTP server is required for the proposed offline signing factor.

Evidence may include device consent signature, YubiKey signature, ceremony binding,
format-pack and policy digests, and App Attest material. Self-reported build strings
are labels, not proof of the running build. App Store signatures and Mac notarization
support installation provenance; they do not sign individual Vow approvals.

Current App Attest validation documents version-related fields. Evaluate an online
enrollment followed by offline assertions bound to the approval digest. Verify the
certificate chain, app identity, environment, available version fields, challenge,
and counters; test this without network access. This is not yet a proven offline
feature. Reinstallation and updates require explicit lifecycle tests and policy.
The App Attest key is distinct from the member's signing key. Bind that public key
and the ceremony challenge into enrollment evidence, and the exact approval digest
into each assertion. An app-instance attestation alone does not attest every key
the app names or prove that its review screen accurately described the action.

Evidence required by policy must be checked at an unavoidable enforcement point.
A collector-only check is audit evidence if another submission route can bypass it.
Full Apple certificate validation need not run on-chain; if a separate verifier
certifies device keys, document its trust and avoid making one verifier a fund-moving
authority. All evidence must bind to the same member, policy and action.

## 6. Network and availability modes

**Strict offline:** no Internet during signing; prefer QR or removable media with
radios disabled. Provisioning, OS updates and revocation imports are explicit
maintenance events. Physical media and QR remain parser attack surfaces.

**Local transfer:** AirDrop is opt-in and requires radios. It is not a physical air
gap. Test internet continuation settings and peer-to-peer behavior. Do not assume
a VPN governs every local wireless transfer.

**Managed restricted:** optionally use MDM and deny-by-default egress, with a tested
Always On VPN configuration and explicit exceptions. This is a connected mode.
Validate DNS, IPv6, captive portals, tunnel failure, restart and profile removal on
the selected OS. Apple management capabilities vary by OS and enrollment method.
MDM is an administrative trust boundary with wipe and availability consequences.

No signing operation should require a live Vow server, registry, VPN, MDM endpoint,
or Apple attestation request. A mode that cannot meet this must say so before setup.
Allow safe export and quorum-based recovery without the original organizer Mac.

## 7. Proposed implementation boundaries

Native SwiftUI applications for Mac and iPad share a Rust implementation of all
portable application and security logic. This is the owner's architecture
direction, confirmed 2026-11-09. Swift is a platform adapter and presentation layer.

Rust owns package encoding, input validation, chain and instruction parsing,
decoder packs, policy, immutable review models, ceremony state, signature preimages,
public signature verification, normalization, evidence assembly, and collector logic.
Handwriting feature extraction and matching also belong in Rust if pursued.

Swift owns SwiftUI, Secure Enclave and Keychain handles, OS authorization contexts,
Pencil event capture, platform NFC/USB access where required, App Attest calls,
Files/share-sheet access, and Apple network/management integration. It converts
platform events to typed Rust inputs and renders Rust's review model. Private keys
and opaque Secure Enclave key representations stay on the platform side.

Use a narrow versioned C ABI with generated headers and an ergonomic Swift wrapper.
Keep `vow-core` independent of Swift and `vow-ffi` limited to ABI translation. Build
static libraries into an XCFramework for device, simulator and Mac targets.
Specify ownership, errors, session lifetime and concurrency before adding exports;
the proposed rules are in [CONTRACTS.md](CONTRACTS.md#rust-and-swift-boundary).

Signing uses a two-phase protocol. Rust prepares an immutable reviewed intent and
returns an opaque session and platform signing request. Swift obtains authorization
and signs exactly those bytes. Rust verifies the result against the enrolled public
key and finalizes only that session. An OS prompt or arbitrary byte-signing shim
cannot independently prove that the app's UI displayed the right intent.

Keep collector/broadcast code outside the offline signing core. Proposed modules:
`ceremony`, `packages`, `policy`, `solana-review`, `format-packs`, `key-provider`,
`evidence`, `transport`, and `collector`. The parser produces one immutable review
model used for both display and signing. A diagnostic verifier should be usable
without either GUI or the original Mac.

## Prototype workspace and approval UI

Rust owns organization members, enrollment status, named immutable quorums and
projects. Each project references a quorum; several projects can reference the
same quorum. New project creation atomically validates either an existing quorum
ID or a new member subset and threshold. Only distinct enrolled organization
members may compose a quorum. Random IDs identify organizations, projects and
quorums. Switching context cancels pending authorization while preserving its
request queue and history.

The prototype’s enrollment flag is rehearsal state, not a verified passport or
member-to-key credential. Device signing identities now persist in device-only
Keychain storage; workspace state and receipts remain session-only. Production
workspace persistence, authorized enrollment imports, signer-key membership validation,
revocation and on-chain threshold enforcement remain unfinished. The enrollment
fingerprint excludes projects and quorums, so project creation does not change it.
Workspace exports carry the roster, quorum library and project references for
local rehearsal import; they do not authenticate an enrollment.

The iPad approval uses a full-screen Review → Authorize → Export flow.
The authorization step uses a fixed two-column layout: request, destination and
quorum details on the left; the signature canvas and verification status on the
right in landscape. Portrait stacks the full-width request summary above the
signature panel. Neither panel scrolls on iPad mini. Footer actions
and the connection controls remain outside the canvas. In the approval assistant,
the compact timeline occupies the navigation title slot. The pill, countdown,
Back and Continue/Authorize/Share actions share one bottom row with matching side
insets. The connection popover is anchored to the pill button itself. UI labels use
direct enrollment, review and authorization terminology across both apps.
The review captures the request digest, requires a nonempty drawing, then signs
Rust-prepared bytes. Back navigation allows revision before signing; backgrounding
invalidates the flow. The completion step shares an immutable verified receipt.
Explanation is a separate full-screen presentation and cannot authorize signing.

The iPad’s Home uses grouped project rows showing organization and project names, consistent
accent icons and navigation chevrons. Selecting a row activates that project and opens
its requests; the Projects toolbar button returns home. The Mac retains its
native workspace sidebar.

A shared Swift `NWPathMonitor` adapter drives one bottom status control per
visible screen: a floating capsule on iPad and a footer strip on Mac. The iPad
pill uses green when offline and red while locked, with the countdown at the
right. Its reserved footer space prevents overlap with Back and other actions. The iPad workspace mounts only when the path is unavailable.
Available, checking, unknown and connection-on-demand states show a dedicated
full-screen disconnect view. No active reachability probe is sent; the gate is
conservative and also blocks local-only networks and VPN paths. See
[ADR 0003](adr/0003-lock-the-ipad-until-offline.md).

Reconnection removes sensitive UI and its presented sheets, cancels Rust’s pending
approval and increments an authorization generation. Key-use and completion guards
require both offline status and the same generation, so even a rapid reconnect and
disconnect cannot complete an older approval. A key operation already in flight
may return a signature internally; Vow discards it and cannot finalize or export
that approval. The device-key adapter survives UI remounting, while the member
must review the request and draw consent again. Explanation generation is canceled
when its presentation disappears.

This is an app lock, not a firewall or proof of device-wide isolation. It does not
turn off radios or stop other processes. The Mac coordinator stays usable while
connected. Local-transfer and managed-connected signing modes remain future work;
this prototype does not offer a network-lock bypass for AirDrop. UI tests exercise
network transitions through a debug simulator-only monitor substitute. Ordinary
simulator runs and physical-device builds use the live system monitor. Hardware
transition and managed-network tests remain pending.

The shared bottom status bar uses a network glyph on the left and a request expiry
control on the right. The same bar stays visible through iPad review, consent and
authorization; timing details open in a popover rather than repeat in the toolbar
or page. Sample requests carry `demo_expires_at_unix_ms` and show a clearly marked
five-minute Demo countdown. It is a presentation rehearsal, not blockhash evidence.
Real blockhash estimates are distinguished from unavailable expiry context.

Consent and authorization share one screen. One second after the last completed
stroke or delayed PencilKit drawing update, a cancellable preflight checks the exact
consent bytes and current Rust policy. Every new pen contact, drawing change, Clear,
navigation or interruption invalidates readiness. No biometric prompt or key use
occurs during this check. Authorize explicitly invokes the protected key, then Rust
verifies the resulting signature. This is consent readiness, not handwriting matching.

## Device onboarding and registered USB-C keys, 2026-11-10

First-run setup has iPad, Security key and Confirm steps. The app checks whether
its saved device-only identity exists and restores it without creating a new key.
The Secure Enclave reference and public enrollment record stay in a
non-synchronizing, passcode-protected Keychain item under a stable app service and
account. Restore verifies the public key and dual-key enrollment proof. Errors
never silently rotate a key. Device loss, uninstall and biometric/passcode changes
still need explicit recovery and re-enrollment; a public device ID is not a seed.

The normal UI contains no PIV slot or management-key fields. It explains the
selected PIN before the owner focuses the input. Focus hides the navigation and
progress headers and both bottom rows, scrolls the field into view, and leaves
Done available. Done restores the header, actions and floating status pill. The
offline gate remains enforced throughout.

New offline enrollments prefer direct USB signing as described below. Existing
native registrations and explicitly selected iPadOS compatibility mode use Apple
`ASAuthorizationSecurityKeyPublicKeyCredentialProvider` for external USB keys.
Registration requires resident ES256 credentials and user verification. Assertions
allow only the enrolled credential and require user verification; platform passkeys
are never requested as a fallback. iPadOS owns PIN and touch UI. Rust pins the same
HTTPS RP as the app entitlement, validates the client-data origin, type and challenge,
and verifies the returned authenticator signature. Enrollment v3 carries the raw
client JSON. See [ADR 0006](adr/0006-use-native-apple-external-security-keys.md).

The configured RP is `vow.scarce.sh`; its public association was deployed and verified
on 2026-11-10. Physical acceptance is pending. The deployment procedure and association file
are in `services/native-key-association/`. Initial association retrieval happens
online; strictly offline registration and assertions remain physical acceptance
tests. Wireless Xcode delivery does not bypass the offline gate. Native registration
persists the public credential before the second proof so interrupted setup can
resume. Importing a verified public enrollment record recovers the key binding, not
a missing Secure Enclave private key. Apple does not expose credential enumeration
or an authoritative key serial through this API. USB presence is only a UI hint;
the pinned credential proof decides authorization. In native mode, Vow observes
`TKSmartCardSlotManager.slotNames` for insertion/removal and rechecks slot presence
around signing without opening a CCID connection or selecting an applet. This
leaves AuthenticationServices in control of the key. Removal still invalidates
the authorization epoch. Legacy CTAP/PIV mode retains its SDK smart-card session.

For new offline enrollments, inspect direct FIDO2 over USB CCID when the connected
key supports it. This is
available on YubiKey firmware 5.8 and newer; actual applet capabilities are checked
without a PIN attempt. Enrollment uses the existing FIDO2 PIN, obtains a token
for credential discovery, and reads only credentials scoped to `vow.invalid`.
The fixed user handle is SHA-256 of `vow.offline.security-key.v1`, independently of
the iPad identity. A matching discoverable P-256 credential with mandatory user
verification is reused. Successful empty discovery permits explicit creation of
one Vow credential; ambiguous or incompatible matches and lookup errors never
trigger replacement. Other sites' credentials are not enumerated or changed.

The reserved `.invalid` namespace is a prototype CTAP scope, not a registered
website or Apple associated-domain entitlement. These are raw offline CTAP
assertions, not a browser WebAuthn origin claim. Rust verifies an exact 37-byte
authenticator data structure, the Vow RP hash, UP and UV, a non-backup credential,
and the P-256 signature over authenticator data plus SHA-256 of the canonical
message. The device countersigns the enrollment message. Approval bytes bind the
method, credential ID and public key, so completion cannot downgrade to raw PIV.
Counters are carried by the signature but clone/rollback detection is not claimed.

Existing PIV enrollments remain supported without conversion. Unsupported FIDO
transport falls back to inspection only when the applet is explicitly absent,
never after a PIN or transport failure. The UI identifies the smart-card PIN as
separate from the usual sign-in PIN. The explicit Set Up This Key action can prepare
PIV signing on the iPad as described below. It preserves the PIN and existing
credentials. Compatible PIV credentials must be hardware-generated P-256 with
PIN-always and touch-always policies. Occupied incompatible credentials are never
overwritten.

Each submitted incorrect PIN stops without automatic retry. Vow refuses the final
remaining attempt in the direct adapter. Native Apple PIN/retry handling is owned
by iPadOS, and Vow cannot inspect its remaining attempts. No PIN or authorization token is persisted. UI secrets are
cleared on completion, interruption and disappearance; Swift and SDK memory do not
guarantee zeroization of all transient copies. Connection-generation guards and
live reads bracket signing; backgrounding closes USB sessions. Registered key
signatures are verified in Rust in addition to the device signature.

The public signing record is exported from the profile’s Details sheet. It proves control of two
keys, not a person's identity, factory hardware origin, Apple app identity or
on-chain membership. Imported requests requiring unsupported production
attestation evidence still fail closed. The insertion animation never authorizes
signing. Simulator fixtures remain DEBUG and simulator-only.

## Native proof preparation and member address (2026-11-10)

After handwritten consent is ready and the enrolled native key is detected, the
iPad opens the system security-key flow automatically. That proof covers the exact
prepared request and consent. The explicit Authorize action then requests device
biometrics and signs those same bytes. Editing consent, removing the key, changing
network state, leaving the step or cancelling invalidates the cached proof. Rust
verifies both signatures again at completion and consumes the pending attempt.

The profile’s Details sheet displays the offline-derived ExternalAccount bridge
address for its compressed Secure Enclave public key. This does not imply on-chain
activation. The address
is useful to coordinate registration with an admin, but the prototype cannot yet
initialize it or submit a real Squads approval. Address derivation does not check
deployment compatibility. See [ADR 0007](adr/0007-display-external-account-member-address.md)
and [cryptography verification](CRYPTO_TESTING.md).

## Direct USB enrollment defaults (2026-11-10)

Rust's `hardware_key_policy` selects direct FIDO2 for a successful compatible
capability report. A new enrollment may use an existing prepared PIV credential
only after an explicitly unsupported FIDO result. Missing PIV credentials or factory
administrative settings enter explicit on-device setup, never an iPadOS redirect.
Failed and unavailable probes never downgrade a factor. Existing methods remain
pinned, including enrolled native Apple registrations. New production profiles no
longer offer native Apple enrollment. Unfinished native registrations do not force
the assistant into that path.

Settings → Diagnostics provides a read-only capability check and public JSON export. It
reports firmware even when the subsequent signing-capability check fails. Native
mode opens a temporary smart-card connection only outside native authorization
sheets and closes it before returning. Signing refuses to begin while a diagnostic
is still running. A disconnect or cancellation discards the diagnostic result.
Successful discovery is not a signature, factory attestation or migration.
See [ADR 0008](adr/0008-prefer-direct-usb-for-new-offline-enrollment.md).

## Signing profiles and Ledger (2026-11-10)

Personal identities are independent of organizations. Organization registrations bind
those identities to enrolled members; several registrations may refer to one member.
Each registration pins a signing identity, version, policy and verified public proof.
The local public archive lives in Application Support; private keys remain in the
existing device Keychain or on the Ledger. This catalog
is public configuration, not an authenticated production organization registry.
Local revocation is not rollback-resistant or an on-chain membership update.

A new profiled quorum pins one profile per distinct member. Its canonical digest
includes profile versions, policy digests and signer addresses. Different members
may use different methods; duplicate people or addresses cannot inflate a threshold.
Revoked, foreign or changed bindings fail validation. Adding a profile never changes
an existing quorum. Legacy unprofiled rehearsal quorums remain labeled as such.

Both apps expose Profiles, enrollment import, public profile sharing and revocation.
New project/quorum creation selects a profile under each member. Existing iPad
public enrollment can be registered as a profile without rotating its key. First-run
iPad setup can instead create a Ledger profile; no iPad/YubiKey enrollment is required
for that method. A Ledger-only device can later initialize iPad signing separately.
Profile-enabled ceremonies and requests use version 5; version 4 cannot smuggle in
profile bindings. Existing legacy files remain accepted without inferred profiles.

The macOS adapter pins solana-keychain PR 358 and requests account confirmation on
the device at enrollment. It never automatically opens apps, requests PIN/seed input,
loads a software key or broadcasts. Its transitive libusb implementation is vendored
into the static library, avoiding a Homebrew runtime dependency. Ledger transaction
signing and off-chain signing must remain separate operations.

The iPad prototype uses CoreBluetooth for Nano X, Nano Gen5 and Flex service UUIDs. Rust
builds Solana APDUs, frames/reassembles bounded BLE packets and verifies signed
envelopes. A process-wide transport owner prevents overlapping Vow BLE sessions.
Device names/UUIDs do not authenticate a signer. Cancellation, backgrounding, timeout
and disconnect discard pending work. No discovery occurs until the
person chooses Ledger and continues to its connection step. PIN entry stays on the Ledger. USB-C Ledger HID is not exposed through
this iPad mini integration; macOS uses USB. Physical model/app-version support is
pending, including pairing, reconnects and cancellation on the real devices.

A Ledger quorum routes to its own review/authorize/export screen. It generates a
fresh short-lived challenge containing the exact profile, request, quorum, project,
chain/genesis and a nonce. Completion consumes the pending attempt and verifies the
Ed25519 signature over the Ledger off-chain envelope. P-256 and Ledger completion
operations reject each other's pending approvals. The result explicitly states
`prototype_only`, `ledger_offchain_v0` and `local_approval_only`. It cannot execute
a Solana transaction. Real Squads approval transactions, supported on-device clear
signing and on-chain factor enforcement remain production work.

See [ADR 0009](adr/0009-bind-signing-profiles-to-quorum-seats.md).

## Native app experience

The redesign applies across the app, rather than only to onboarding. Mac is the
coordinator: members, physical ceremonies, quorum policies, project configuration,
web capture and request preparation. iPad is the signer: import, inspect, authorize,
export, history, personal profiles and local device controls. Both share a compact
workspace header, dashboard, project rows, network labels, surface components,
method cards and profile assistant. Native platform adapters provide the hardware
and presentation differences. `DESIGN_MEMORY.md` defines the visual and interaction
rules for new work. Axel v0.2.0's shared-view and platform-service separation is the
reference, rather than its old model or persistence implementation.

### Model and ownership

A `PersonalIdentity` belongs to a person and carries a named signing method and
verified public proof. It has no organization or member ID. A physical ceremony
associates an identity with an enrolled `Member` through an organization profile.
That registration has its own ID, version and policy digest. A `Quorum` pins exact
registration versions; a `Project` selects a quorum and a chain. A `Request` is scoped
to the project and exact quorum; an `Approval` binds exact reviewed bytes and proof
scheme. Personal identity creation cannot silently enroll a member or change a
quorum. Local registration remains prototype policy, not an authenticated on-chain
membership operation. See ADR 0010.

### First launch and additional profiles

Load and verify the local archive before choosing a route. Missing records launch
one profile assistant; corrupt or unreadable records show an error without replacing
keys or records. Existing registrations remain accessible after migration. The same
assistant opens from Profiles when adding another profile.

1. Name the profile. No roster entry, organization selection or account path.
2. Choose iPad + security key or Ledger with illustrated side-by-side native cards.
3. Verify hardware. Ledger discovers supported nearby devices, stops a search after
   15 seconds, offers an explicit retry, checks the open app, and requests on-device
   address and proof confirmation. USB provides the Mac path. iPad + security key
   reuses existing enrollment or starts the reusable security-key component, followed
   by biometric confirmation. Existing PINs are never reset.
4. Show the exact signing address and shareable public record. Team registration
   is explicitly subsequent. The profile is saved before success is displayed.

Permission prompts occur inside the hardware task. Cancellation and backgrounding
invalidate pending proof state. Discovery names and OS connection state never count
as signature verification. PIN attempts and signed challenges are never replayed
by an automatic retry.

### Full-app information hierarchy

Home prioritizes the next request and then projects. Projects show their pinned
network and approval policy. Profiles shows personal signing identities separately
from organization registrations. Members and Quorums use direct task titles, with
physical enrollment distinct from quorum selection. Signing retains Review,
Authorize and Export and presents its required factors in one consistent layout.
Network state uses one anchored pill; advanced details live behind disclosures.
Requests, history, public profile sharing and transaction preparation use the same
accent, typography and neutral surfaces. Existing native sharing and drag-and-drop
remain available.

### Local persistence and future iCloud backup

`PublicIdentityStore` writes a bounded schema-versioned public-record archive
atomically under Application Support. Rust verifies every restored profile and
identity. The previous public UserDefaults catalog migrates on first successful
load. The archive is excluded from automatic device/cloud backup until an explicit
backup policy is selected. Device keys stay in nonsynchronizing Keychain/Secure
Enclave storage. Hardware seeds and PINs never belong to this archive.

The following repository boundaries are required before production persistence:

| Repository | Local contents | Future opt-in backup |
|---|---|---|
| Personal identities | Names, public keys, proofs, method and device hints | Eligible, with explicit consent |
| Organization policy | Members, projects, exact quorum/profile bindings, policy epochs | Eligible, authenticated and rollback checked |
| Approval history | Exact exported receipts and signed request references | Separate privacy/retention choice; reverify on restore |
| Device credentials | Secure Enclave reference, local credential references | Device-bound; never copied as signing capability |
| Authorization session | PIN buffers, biometric state, handwritten draft, pending challenges | Never backed up |

Only the identity/registration archive is implemented by this redesign. Organization
workspace state and approval history remain session-scoped. Do not imply otherwise
in release or recovery UX. Plan durable workspace/receipt repositories before wiring
CloudKit. iCloud maintenance must be an explicit online mode that cannot authorize
requests, with a last-successful-backup time and failures visible. Restoring public
metadata on another iPad yields a profile requiring hardware reconnection or member
replacement, never a recovered Secure Enclave key. Cloud data cannot confer ceremony
authority or roll back revocation. Revalidation, authenticated policy epochs and
conflict rules must precede cloud rollout.

### Signer-only iPad and explicit profile selection (2026-11-11)

The iPad has no member-enrollment, ceremony-review, quorum-creation or registration
revocation controls. It manages personal signing profiles and reviews requests.
Organization, project, network and quorum appear as request policy context, not
administrative setup. Mac coordinates the organization and ceremonies. Legacy
ceremony context remains an internal compatibility format, not an iPad workflow.

Importing a request clears the previous selected profile. The signer explicitly
selects a saved profile before opening approval. The choice is frozen into the
presented approval flow. Vow checks the chosen account against the exact request
policy and local key availability; a Ledger account is verified against that choice
before authorization. Selecting a profile does not grant membership or permit
signing an otherwise unverified raw dump. The raw inspector also offers profile
selection but retains all existing validation and signing limitations.

Approval uses stacked full-width summary/signature panels in portrait and a split
layout in landscape. Settings offers Reset Everything with an explicit irreversible-action confirmation.
It clears local profiles, all organization/project/member/quorum context, history,
requests, temporary exports and app preferences. It deletes Vow’s device-only
Keychain identity, including the Secure Enclave wrapped key and saved external-key
registrations, and drops in-memory key objects across scenes. The YubiKey’s own PIN
and credentials, Ledger keys and on-chain memberships are unchanged. Setup creates
a new signing key only when the person chooses iPad signing again.

A device-only Keychain reset-intent marker makes an interrupted reset resumable on
startup before any identity is restored. Public archive data can never authorize
private-key deletion. The empty-workspace marker prevents bundled sample organizations
and projects from returning after reset/relaunch. Reset does not repair an iPadOS
associated-domain cache failure.

The iPad sidebar calls this screen Settings. Its main contents are profile count and local storage,
diagnostics access, app version and Reset Everything. Public keys,
signing addresses and shareable records are in each profile’s Details sheet, with
technical values collapsed. Read-only security-key diagnostics have their own sheet.
New installations start without sample organizations unless a debug sample is
explicitly requested.

### Security-key setup transport lifecycle (2026-11-11)

The setup view synchronizes USB ownership with its selected method on entry,
method changes and foregrounding. Leaving setup restores detection for the saved
registration. Native presence observation does not open a smart-card connection;
it cannot enable direct-USB inspection. Direct setup requires an actual ready
connection; native setup requires native presence observation. This prevents a
stale native monitor from producing a false reconnect error after Back → Continue.

When a completed capability check identifies an unprepared legacy smart-card
path and native signing is configured, the primary action explicitly offers
Continue with iPadOS. Choosing it starts the native setup path; no credential or
PIN is changed by the switch. Existing registered methods remain pinned. Failed
or incomplete probes never switch methods automatically.

## Automatic smart-card PIN handling (2026-11-11)

For a prepared PIV credential, Vow hides the PIN field when metadata identifies the
factory PIN. Before every automatic verification, the adapter reads fresh metadata
and requires more than one retry remaining. It never guesses the factory PIN on a
configured key. Rejected automatic verification reveals the existing-PIN field and
suppresses further automatic attempts for that key for the monitor's lifetime.
Approval uses the same policy and prompts only when needed. FIDO2 and native Apple
PIN handling remain unchanged. No PIN is changed, reset or saved.

The public factory PIN is not an independent knowledge factor. This convenience
mode relies on hardware possession and touch, alongside iPad authentication and
consent. Signature verification, credential pinning, nonfactory management/recovery
settings and always-touch policy remain mandatory. Automatic PIN handling does not
by itself provision a missing credential or fix Apple's domain association. The
separate direct setup action described below handles provisioning. See
[ADR 0011](adr/0011-automatically-use-confirmed-factory-piv-pin.md).

## On-device PIV setup (2026-11-11)

New iPad + security-key profiles stay in direct USB setup. After an explicitly
unsupported direct FIDO result, Vow inspects PIV. Set Up This Key is a distinct
user action, not a side effect of insertion or capability inspection. It verifies
the existing PIN under the automatic-PIN policy before administrative operations.
A customized management key is requested only if Vow has no saved setup record.
Factory management authorization is used only when confirmed by metadata.

Before any administrative mutation, Vow saves a private, device-only Keychain
journal keyed by the YubiKey serial. Newly secured management keys use random
AES-256; a factory recovery code is replaced with a random eight-digit code.
Existing custom management keys and recovery codes are preserved. The PIN is
never changed. The adapter requires firmware supporting AES management and
refuses the final recovery-code retry. Setup secrets never enter public profile
exports, diagnostics or iCloud. Full reset erases these local secrets too.
Losing this private record can lose administrative access to the key's PIV
settings. Recovery export remains outstanding.

The signing key is generated inside the YubiKey in Vow's existing PIV location
only after re-reading it as empty. An existing compatible credential is reused;
an incompatible or changed credential stops setup. Every mutation boundary checks
cancellation and the connection epoch. Network changes cancel the setup task.
Interrupted setup uses the saved journal and fresh key metadata to resume without
rotating secrets again or overwriting a generated key. Hardware signatures are
still verified against the pinned public key before enrollment completes.

The production sequence has hardware-independent fault-injection tests for lost
acknowledgements after management rotation, recovery rotation and key generation,
failed journal storage, occupied locations and final-retry protections. Simulator
onboarding tests exercise the direct setup UI but do not certify physical firmware
behavior. See [ADR 0012](adr/0012-provision-piv-on-ipad-without-native-enrollment.md).
