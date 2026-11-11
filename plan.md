# Vow implementation plan

Updated: 2026-11-10. Status: native prototypes and a working compatibility spike.
Use case and architecture: [docs/DESIGN.md](docs/DESIGN.md).
Security gates: [docs/SECURITY.md](docs/SECURITY.md).

## Native prototype delivered

- [x] Native Mac ceremony UI: sample member enrollment, quorums, confirmation and JSON export.
- [x] Native iPad UI: local-file import, sample request review, PencilKit consent,
  signature creation, local verification and share/export-ready receipt history.
- [x] Shared Rust `vow-core` state/policy and `vow-ffi` session-based C interface.
- [x] Explicit software-key simulator path; Secure Enclave biometric path compiles
  for physical iPad but remains untested on hardware.
- [x] Automated Mac ceremony and iPad review/consent/signing UI tests, including
  the iPad mini simulator and compact landscape layout.

- [x] Organizations and projects with scoped queues, receipt history, version-four packages,
  context-switch cancellation and Rust tests for isolation and import/export.
- [x] Explicit on-device explanations from Rust-prepared facts; native generation
  tested on Mac and iPad mini simulator. Hardware offline verification remains open.
- [x] Onboarding gives focused fields the full available height. Done restores the
  header and footer; a floating red/green status pill stays clear of Back.
- [x] Fixed two-column authorization on iPad mini in portrait and landscape, with
  request details left, signature right and no screen scrolling. Direct, professional
  enrollment and authorization copy across iPad and Mac.
- [x] Full-screen iPad approval wizard and explanation, step breadcrumbs, and live
  system network-path badge without active probing.
- [x] Grouped iPad project home and a single bottom connection strip. A full-screen
  gate blocks the iPad until offline; reconnection invalidates authorization.
  Native tests cover automatic unlock, sheet dismissal, interrupted signing and
  retry, using simulator-only network injection. Physical-device testing remains open.

- [x] Separate organization enrollment from project approval policies. Project
  creation reuses an immutable quorum or composes one from enrolled members with
  its own threshold. Rust rejects pending, duplicate and foreign members and binds
  the quorum policy into requests and signed approval data.

This is a local rehearsal, not completion of the production phases below.
Workspace state and approvals are session-only. Device identities persist in device-only
Keychain storage. No passports or multisig execution are connected. Registered USB-C
FIDO2 and compatible PIV credentials sign local approvals; production attestation evidence remains unfinished. Build and run instructions are in `README.md`.

## Device onboarding

- [x] First-run iPad assistant creates and persists a biometric Secure Enclave identity.
- [x] Prefer discoverable FIDO2 credentials on compatible USB CCID keys. Use the
  existing sign-in PIN, find and reuse Vow registrations, require PIN and touch.
- [x] Keep compatible PIV registrations; explain separate smart-card setup for older
  keys. Never set/reset/change PINs or ask for management keys in iPad onboarding.
- [x] Restore identity across app restarts; export public dual-key enrollment JSON.
- [x] Rust binds and verifies a registered-key signature over each local approval.
- [ ] Hands-on verification of FIDO2 firmware compatibility, existing PIN, USB touch,
  discoverable credential reuse and interrupted creation,
  biometric-policy invalidation and Keychain restore on the owner's iPad/YubiKey.
- [ ] Verified bridge deployment, on-chain member activation and admin registration.
- [ ] Explicit device loss, biometric changes, reinstall and member replacement recovery.
- [x] Implement native Apple external-key registration and assertion, required user
  verification, pinned HTTPS RP, v3 enrollment and Rust WebAuthn verification.
- [x] Simulator fixture coverage for native enrollment, approval and cancellation;
  compile current iPad hardware and Mac builds.
- [x] Owner selected `vow.scarce.sh`; association file deployed and verified over HTTPS.
- [x] Enable associated-domain provisioning and deliver the activated build wirelessly.
  Signed entitlement and Info.plist match `vow.scarce.sh`; Apple CDN serves the association.
- [ ] Resolve the physical iPad's `ASAuthorizationError/1004` webcredentials
  association failure. Refresh association during an online install, then verify
  a native assertion while offline. Public origin, Apple CDN and entitlements match.
- [ ] Physical native-key acceptance: usual PIN, USB touch, offline registration and
  assertions, cancellation/removal, interrupted setup and public-record restore.
  Simulator fixtures do not establish these guarantees.

## Mac transaction construction and offline reproduction

[RFD 0002](docs/rfd/0002-mac-dapp-browser-and-proposal-capture.md) records the browser
workflow. [RFD 0003](docs/rfd/0003-guard-and-reproduction.md) covers enforcement and
state reproduction. The delivered slice is review-only.

- [x] Wallet Standard preview provider in an ephemeral WKWebView, explicit native
  origin permission, top-frame validation and navigation/project cancellation.
- [x] Bounded canonical unsigned legacy/v0 SOL-transfer decoder, native multi-step
  preparation, draggable/shareable `.vow` file and independent revalidation.
- [x] Embedded Surfpool SDK 1.7.0 with profiling, pre-transaction snapshot export,
  and independent LiteSVM replay. Initial profile uses synthetic transfer state.
- [x] Explicit opt-in Program Metadata IDL retrieval on Mac; verify canonical PDA,
  owner, bounded direct compressed JSON, program identity, chain and content hash.
- [x] Devnet/Mainnet project binding, fixed RPC genesis verification and signed
  chain/genesis fields. Reject cross-network captures, imports and reproduction.
- [x] Plain binary/hex/base64/JSON transaction dump inspection alongside `.vow`.
- [x] Source-derived Payment Channels open/distribute inspection. Open fixture has
  real ABI and canonical addresses; no fabricated attestation instruction.
- [x] Optional blockhash observation context and estimated offline countdown in the
  shared bottom bar, with a labelled five-minute sample timer and expiry details.
- [ ] Validate real channel account state, mint decimals/authorities, payout deltas,
  program deployment, PDA/account privileges and lookup-table context end to end.
- [ ] Extend snapshot closure to arbitrary approved SBF programs, program-data,
  sysvars, features and clock context; pin binaries and test deterministic replay.
- [ ] Build and test an unavoidable on-chain attestation guard. Prove negative
  bypass cases including stale approved proposals, batches and spending limits.
- [ ] Prove Initiate-only proposal creation and delayed P-256 voting/execution
  against pinned Squads deployments. Test maintenance and recovery authority paths.
- [ ] Test selected public dapps and actual device AirDrop/Files interoperability.
- [ ] Enforce appropriate lifetime semantics for direct transactions, durable
  proposals and fresh outer execution transactions. Never call an offline timer
  an authoritative block-height or validity check.

## Scope and choices

Build two native apps: a Mac ceremony coordinator and an offline iPad signer.
The pilot should support one multisig integration, a small set of fully decoded
actions, installed formats, handwritten consent, device authentication, optional
YubiKey evidence, and export/import with independent verification.

Handwriting matching, App Attest, external readers, network controls and on-chain
factor enforcement each need evidence before the product claims them. Dynamic
retrieval is off by default and happens through explicit maintenance workflows.

Owner decisions needed before selecting the signing route:

- [ ] Existing multisig compatibility versus accepting a P-256 approval adapter.
- [ ] Pilot team size, threshold and simultaneous member-loss tolerance.
- [ ] Required actions, assets, limits and target network.
- [ ] Handwriting as consent versus required biometric matching.
- [ ] Whether YubiKey/provenance evidence must be chain-enforced or audit-only.
- [ ] Strict offline, local-transfer, or managed-connected deployment profile.

## Phase 0: prove the platform assumptions

These experiments precede production architecture commitments. Produce measured
results, source/version pins, negative tests and a go/no-go recommendation.

- [x] Verify CryptoKit software and Mac Secure Enclave P-256 output against the
  pinned bridge's account-registration verifier in LiteSVM. Six acceptance and
  rejection cases pass in each mode. See `spikes/p256/README.md`; iPad authorization
  and full Squads execution are separate unfinished gates.

- [ ] Physical iPad: generate a hardware key, sign an approval digest, verify
  independently, and test per-use authorization, lockout, backgrounding, reboot,
  passcode fallback policy and biometric re-enrollment. Use Touch ID on mini.
- [ ] Compare route A's process-visible Ed25519 secret with route B's P-256
  approval path and route C's external signer. Record each threat boundary.
- [ ] Inspect the exact target multisig program and demonstrate an approval and
  execution path that binds an inner action. Do not assume generic PDA membership.
- [ ] Evaluate the existing P-256 WebAuthn External Signature Program bridge before
  designing a new adapter. See the pinned source review in `docs/RESEARCH.md`.
  Verify source-to-deployment and audit coverage, PDA membership, raw P-256 versus
  WebAuthn compatibility, and its 150-slot expiry under realistic review delays.
- [ ] For route B, demonstrate P-256 verification and replay protection locally,
  including precompile offset validation and forged action rejection.
- [ ] USB-C YubiKey: evaluate PIV and FIDO2 on each selected iPad/model/firmware.
  Verify fresh challenge binding, presence/verification policy and offline use.
- [ ] App Attest: enroll online, then deny all network access and test assertions,
  independent validation, version metadata, counters, update and reinstall cases.
- [ ] Passport reader: read full evidence and perform host-chosen AA through the
  Flipper; compare a selected PC/SC reader. Test removal of scans and logs.
- [ ] Verify Mac App Store sandbox feasibility for USB serial/PCSC access and
  iPad App Store entitlement requirements. Assess notarized direct Mac distribution
  as an alternative without assuming it is equivalent to Mac App Store review.
- [ ] Compare removable-media, QR and AirDrop import/export on actual devices.

Exit: choose the signing route and enforcement boundary in an ADR. Stop any claim
that the experiments do not substantiate. Do not provision real treasury keys.

## Phase 1: specify the protocol and review engine

- [ ] Establish `vow-core` and `vow-ffi`: put portable logic in Rust, keep Apple UI
  and hardware APIs behind Swift adapters, generate a versioned C ABI header, and
  package device/simulator/Mac static libraries as an XCFramework. Follow the
  ownership and two-phase signing contracts in `docs/CONTRACTS.md`.

- [ ] Finalize canonical encodings, domain-separated preimages and evidence graph
  from [docs/CONTRACTS.md](docs/CONTRACTS.md). Publish cross-language golden vectors.
- [ ] Finalize organization enrollment credentials, project quorum manifests, epochs,
  transcript authorization and authenticated offline configuration distribution.
- [ ] Select transaction validity model: persistent proposal or durable nonce.
  Test real delay between collection and submission; reject blockhash substitution.
- [ ] Implement bounded chain parsing and one deterministic review model. Bind
  the displayed inner action to the bytes actually authorized.
- [ ] Support a narrow allowlist, initially simple transfers and necessary multisig
  approval actions. Include fee and amount limits and authority-change detection.
- [ ] Implement installed signed format packs and rollback protection. Native
  safety checks remain authoritative. Unknowns reject without a blind-sign path.
- [ ] Define trusted account context and state preconditions. Start without
  unresolved lookup tables or arbitrary program calls. Document offline limits.
- [ ] Build a GUI-independent package and approval verifier.

Exit: malicious proposals, swapped context, unknown instructions and ambiguous
serialization fail. The independent verifier agrees with the iPad's review model.

## Phase 2: deliver use case U without passport dependency

- [ ] Optional on-device explanations using Apple's Foundation Models platform
  adapter. Rust supplies decoded facts; generated prose cannot supply missing
  semantics, alter the approved bytes, or authorize signing. Check local model
  availability, require explicit opt-in and permit no cloud fallback. Provision
  model assets during setup; handle model removal and unavailable devices.

- [ ] Implement iPad import, review, explicit consent, required factor sequence,
  key use, local receipt, share sheet and file fallback.
- [ ] Keep reviewed bytes immutable; any mutation or interrupted authorization
  invalidates the active approval session.
- [ ] Bind optional hardware-key evidence to the same action and policy digest.
- [ ] Treat captured handwriting as private consent data. Add matching behind
  an experimental policy only after measuring false accepts/rejects.
- [ ] Store minimal state with protected files and device-bound key references;
  propagate persistence failures and define backup behavior explicitly.
- [ ] Build collector import, evidence validation and threshold aggregation.
  Show missing factors and stale policy as failures, not success with a footnote.
- [ ] Submit a harmless action through the chosen wallet path. Verify resulting
  state and return an execution receipt to the iPad through import.

Exit: two independent devices approve the same action while disconnected from
the Internet. Evidence verifies on another machine. A changed action, duplicate
signer, stale policy, removed required factor and replay all fail.

## Phase 3: deliver ceremony and identity binding

- [ ] Implement the Mac ceremony wizard and device-generated key registration.
- [ ] Build Passport reader adapter and native PKI verification with pinned anchors.
  Do not use development ZK proofs as identity authority.
- [ ] Bind passport check, member/device proof of possession, team and session.
  Add independently witnessed identity review and final digest comparison.
- [ ] Enroll local handwriting references and optional hardware-key credentials.
- [ ] Separate witnessed member enrollment from authorized project/quorum configuration.
  Persist enrollment so members are not enrolled again for each project. Require
  confirmation of the selected quorum and its project-specific policy.
- [ ] Create/configure the multisig and verify deployed authorities independently.
- [ ] Run approval rehearsal, loss/replacement drill and recovery quorum exercise.
- [ ] Export privacy-minimized public transcripts to independent custodians;
  erase transient passport scans and reader artifacts according to policy.

Exit: a malicious organizer cannot substitute one member's key or alter threshold
without a detectable confirmation mismatch. A surviving quorum can replace a lost
iPad without the original Mac or a central Vow service.

## Phase 4: provenance, maintenance and managed deployment

- [ ] Integrate only the App Attest behavior verified in Phase 0. Require explicit
  enrollment/renewal, evidence policy, counter persistence and reinstall recovery.
- [ ] Add installed format/policy updates via signed offline packages. Online
  discovery remains opt-in; no proposal may turn it on implicitly.
- [ ] Add a maintenance flow for approved app/OS updates and trust-root rotation.
- [ ] Validate selected MDM/VPN profile against IPv4/IPv6, DNS, captive portal,
  restart, tunnel failure, profile removal and local wireless bypasses.
- [ ] Document which authority can install updates, wipe devices, alter network
  rules or disable signing. Preserve quorum recovery through management outages.
- [ ] Obtain publisher approval, entitlement confirmation and release-signing
  arrangements. Publish verification instructions and signed release manifests.

Exit: no routine signing requires a live service. An optional connected deployment
has measured traffic behavior and accurately described residual trust.

## Phase 5: independent review and limited pilot

- [ ] Fuzz imported packages, schemas and chain messages; test resource exhaustion,
  malformed encodings, replay, rollback and display/signing inconsistencies.
- [ ] Audit the adapter if used, key management, factor binding, decoding,
  ceremony, supply chain and recovery. Exercise direct submission bypasses.
- [ ] Measure usability with representative members: identify the recipient,
  amount, authority changes and exceptions before signing. Include accessibility.
- [ ] Pilot with low-value assets and a published support matrix. Rehearse an app
  update compromise, organizer loss, member loss, revoked device and unavailable MDM.
- [ ] Fix material findings and define ongoing release, incident and key-rotation
  ownership before allowing production treasury use.

## Deferred work

General arbitrary-program signing, remote ceremony, production Passport ZK
credentials, arbitrary downloadable decoder code, threshold Ed25519/DKG, and
unmeasured handwriting-based identity claims are outside the initial pilot.
Expand one boundary at a time with new threat analysis and acceptance tests.

## Verification update (2026-11-10)

- [x] Verify the owner's exported native offline approval with both P-256 keys.
- [x] Derive the ExternalAccount member address in Rust with an independent PDA
  vector and display pending activation in This iPad.
- [x] Automatically request the native YubiKey proof after consent is ready;
  preserve explicit device biometric authorization and invalidate stale proofs.
- [x] Add crypto regression tests and a dedicated CI workflow. Reject missing
  WebAuthn keys and reserved registration flags. Bind each approval attempt to a
  fresh random nonce, including across app sessions.
- [ ] Initialize the chosen bridge execution mode and verify deployed bytecode on
  each supported cluster before real Squads voting or funded quorum membership.
- [ ] Complete physical reboot, reinstall/recovery and failure-path testing. One
  successful offline owner approval does not close these production gates.

## Hardware-key exploration (2026-11-10)

Design: [RFD 0004](docs/rfd/0004-offline-hardware-key-defaults.md).

- [x] Define a Rust selection policy and typed capability outcomes. Prefer physically
  tested direct USB CTAP for new offline enrollments; keep enrolled methods pinned.
- [x] Expose a read-only iPad capability diagnostic outside active native requests,
  with firmware, explicit failure outcomes and a public report export.
- [ ] Record actual firmware and direct signing results on the owner's hardware.
- [ ] Test direct USB PIN/touch signing on compatible hardware, including reboot,
  prolonged offline operation and offline app updates.
- [ ] Design the Mac PIV preparation assistant for older hardware. Explain its
  separate PIN, preserve existing credentials and settle recovery-secret custody
  before enabling any provisioning writes.
- [ ] Simplify the common iPad flow to connect, PIN, touch, then device biometrics.
  Display protocol and slot information only in technical details.
- [x] Add method-selection/no-downgrade unit tests and native UI regressions for
  default selection, diagnostic export and unprepared PIV state.
- [ ] Add explicit migration and physical hardware interruption acceptance tests.
- [x] Install the diagnostic/default-selection build on the owner's iPad. Preserve
  its existing native registration; switching methods remains a separate step.

## Signing profiles and Ledger exploration (2026-11-10)

Design: [RFD 0005](docs/rfd/0005-signing-profiles-and-ledger.md). The USB key
migration/provisioning exploration is deferred while this model is considered.

- [ ] Add user-owned versioned signing profiles, organization registration of each
  profile, and quorum seats referencing one exact profile per enrolled member.
- [ ] Preserve the existing iPad identity as one profile without repeating the
  physical ceremony or rotating keys. Adding another key still needs proof and
  authorized member binding.
- [ ] Reject duplicate people or signer addresses in a quorum, incompatible methods,
  inactive/revoked registrations and stale profile versions. Bind the full profile
  policy into the quorum digest and version imported/exported schemas.
- [ ] Add profile management and per-member profile selection during quorum setup.
- [ ] Prototype macOS USB Ledger support using pinned solana-keychain, with explicit
  device address confirmation and exact-byte transaction signature verification.
- [ ] Separate Ledger off-chain enrollment envelopes, real Solana transaction
  signatures and P-256 local approvals in the Rust/FFI proof types and tests.
- [ ] Validate actual Ledger/Solana app versions and real Squads approval display.
  Investigate a native iPad transport separately; desktop HID is not iPad support.

## Profiles / Ledger implementation status (2026-11-10)

- [x] Rust profile catalog, proof verification, immutable quorum seat binding,
  duplicate member/address checks, revocation and v5 public schemas.
- [x] Native Profiles screens, public record sharing/import and per-member profile
  picker when creating quorums. Preserve existing unprofiled rehearsal quorums.
- [x] Register existing iPad enrollment without rotating the key or repeating its
  factor setup. Add a separate first-run Ledger path.
- [x] Pin published solana-keychain PR 358 for macOS USB; no sibling-path dependency.
- [x] Prototype Nano X / Nano Gen5 / Flex iPad BLE with Rust APDUs, framing and signature
  verification. Keep desktop HID out of the iOS graph.
- [x] Separate Ledger and P-256 authorization and export explicit off-chain rehearsal
  evidence. Add Rust and native UI regressions and macOS adapter CI.
- [ ] Run physical Nano X, Nano Gen5 and Flex BLE/USB acceptance: pairing, address display,
  Solana app versions, enrollment, cancellation, wrong device, timeout and reconnect.
- [ ] Add authenticated organizational profile registration, rollback-resistant
  revocation, authorized profile replacement and per-cluster on-chain activation.
- [ ] Construct and verify real Squads approval transactions and validate Ledger
  clear-signing coverage. Off-chain rehearsal evidence cannot substitute for votes.

## Full-app UX and data redesign (2026-11-10)

- [x] Shared native design primitives and written full-app rules in DESIGN_MEMORY.md.
- [x] Compact Mac/iPad workspace chrome, common home/dashboard and project/network rows.
- [x] Consistent accent, icon, surfaces and typography through profiles, review and preparation.
- [x] Personal identity separated from organization ceremony registration; preserve v1 records.
- [x] One assistant for first launch and Add Profile: name, method, hardware, public address.
- [x] Reuse verified iPad enrollment without rotating keys; new Ledger personal-proof domain.
- [x] Bounded BLE discovery, explicit retry and cancellation, app check and exact device errors.
- [x] Versioned atomic local public-record archive; migrate the old public catalog.
- [ ] Durable organization/project/policy and receipt repositories with verified restore.
- [ ] Explicit opt-in iCloud maintenance and backup/restore UX; never back up signing capability.
- [ ] Authenticated ceremony registrations, revocation epochs and rollback-resistant restore.
- [ ] Physical-device acceptance of the redesigned Ledger and security-key flows.
- [ ] Accessibility acceptance at largest Dynamic Type sizes and small multitasking windows.

### Page alignment review

- [x] One WorkspacePage column and margins across Mac/iPad content pages.
- [x] Shared full-width empty-state and context cards; compact page headings.
- [x] Mac Requests real preparation/import primary actions and secondary samples.
- [x] Native trailing toolbar utilities with no centered overflow menu.
- [x] iPad request/history/organization alignment and bounded device-settings width.
- [x] Regression checks for home, projects, request approval, compact landscape and key diagnostics.

### Signer scope and latest feedback (2026-11-11)

- [x] Remove ceremony and member-administration UI from iPad; retain request policy context.
- [x] Explicit per-request profile selection, reset on a new request, with policy/key checks.
- [x] Freeze the chosen signing identity through the approval presentation.
- [x] Stack full-width approval panels in portrait; retain split layout in landscape.
- [x] Remove overlapping sidebar prototype caption and duplicate profile import button.
- [x] Reset Everything with confirmation: delete device identity and all Vow data; preserve hardware-key PINs.
- [ ] Physical online-install test for AS1004 domain association, followed by offline signing.

### Settings cleanup and full reset (2026-11-11)

- [x] Replace This iPad with minimal Settings; move key/address records into profile details.
- [x] Put read-only hardware diagnostics in a dedicated sheet.
- [x] Full reset clears organizations/projects, personal profiles, public records, preferences and exports.
- [x] Delete device-only Keychain identity and registered-key references; clear cached keys across scenes.
- [x] Recover interrupted resets using a private Keychain intent, never public backup metadata.
- [x] Persist a blank workspace so sample organizations/projects do not reappear after reset.

### YubiKey setup navigation fix (2026-11-11)

- [x] Synchronize setup UI and monitor transport on entry, method changes and resume.
- [x] Restore saved-registration detection on leaving setup; require real USB readiness for direct inspection.
- [x] Explicit iPadOS setup offer for confirmed unprepared legacy USB keys when configured.
- [x] UI regressions: native → Back → direct setup, native opt-in, successful native signing, direct preference and no fallback on failed probes.
- [ ] Physical YubiKey verification on the updated iPad build.

## Automatic PIV PIN handling (2026-11-11)

- [x] Hide PIN input for prepared keys reporting the factory PIN.
- [x] Inspect fresh metadata before automatic verification; preserve the final retry.
- [x] Reveal existing-PIN input on rejection without automatically retrying.
- [x] Preserve custom PINs, credential pinning and administrative readiness gates.
- [x] Add standalone production-policy tests and onboarding regression coverage.
- [x] Add explicit on-device PIV setup with private recovery journaling and no overwrite of existing keys.
- [ ] Verify automatic handling on the owner's physical prepared key.

## Remove the native-setup dead end (2026-11-11)

- [x] Remove new-profile iPadOS compatibility options and the primary redirect.
- [x] Ignore unfinished native registrations when choosing a new-profile adapter.
- [x] Add explicit direct setup: verify existing PIN, journal secrets, secure factory administrative settings, generate only in an empty location.
- [x] Preserve existing native enrollments and all customized PINs and credentials.
- [x] Fault-test interrupted writes, failed journal persistence, occupied keys and final recovery retry.
- [ ] Verify fresh-key provisioning with the owner's physical YubiKey.
- [ ] Add a secure recovery export for app-managed PIV administrative secrets before production release.
