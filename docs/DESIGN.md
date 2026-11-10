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
right. Neither column scrolls on iPad mini in portrait or landscape. Footer actions
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

When a verified associated domain is configured, prefer Apple
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

Without native configuration, retain direct FIDO2 over USB CCID when the connected
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
separate from the usual sign-in PIN. A factory smart-card PIN or custom management
authorization requires one-time setup with an administrator on Mac. The iPad never
sets, changes or resets a PIN and never asks for a management key. With an existing
nonfactory PIN and confirmed factory management configuration, explicit enrollment
can generate a P-256 credential only in the empty reserved PIV location, requiring
PIN-always and touch-always. Occupied incompatible credentials are not overwritten.

Each submitted incorrect PIN stops without automatic retry. Vow refuses the final
remaining attempt in the direct adapter. Native Apple PIN/retry handling is owned
by iPadOS, and Vow cannot inspect its remaining attempts. No PIN or authorization token is persisted. UI secrets are
cleared on completion, interruption and disappearance; Swift and SDK memory do not
guarantee zeroization of all transient copies. Connection-generation guards and
live reads bracket signing; backgrounding closes USB sessions. Registered key
signatures are verified in Rust in addition to the device signature.

The public enrollment record is exported from This iPad. It proves control of two
keys, not a person's identity, factory hardware origin, Apple app identity or
on-chain membership. Imported requests requiring unsupported production
attestation evidence still fail closed. The insertion animation never authorizes
signing. Simulator fixtures remain DEBUG and simulator-only.
