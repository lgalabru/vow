# RFD 0004: Offline hardware keys with approachable defaults

State: discussion
Authors: Vow team · Started: 2026-11-10

## Problem

The owner wants a hardware key that remains usable without internet access, with
ordinary PIN and touch prompts. Native Apple WebAuthn has produced AS1004 after
app installation. Online installation restored service previously, but Apple does
not document a permanent offline-validity guarantee for domain associations.
The current app prefers native WebAuthn whenever its domain is configured.

Slots, protocol choices and management keys should not be part of daily signing.
We cannot hide the fact that different applets may use different PINs or silently
replace a registered security factor.

## Sketch

For new offline enrollments, prefer direct FIDO2 over USB CCID on hardware that
passes the capability probe and physical acceptance tests. Use the existing FIDO2
PIN. Require P-256, presence and user verification for every approval. Pin the
credential, method and RP in the enrollment. Native WebAuthn credentials and direct
CTAP credentials have different RP bindings; sharing a PIN does not make them the
same credential.

Existing enrollments retain their pinned method. An AS1004, transport error,
incorrect PIN or parse failure never selects another adapter. An explicit migration
requires a fresh proof and updated enrollment binding. Preserve the device's Secure
Enclave key and derived member address; do not silently rotate either key. Updating
any enforced public registry remains a separate authorization step.

For an older key without direct CCID FIDO2, offer two clear choices during setup:
use a key certified for offline signing, or have the Mac prepare smart-card signing.
Keep native Apple signing available as a compatibility option with an explained
online installation dependency, outside the default offline profile.

PIV preparation belongs in the Mac ceremony assistant. It inspects existing state
before writing. Reuse a compatible credential only after checking its public key,
PIN policy and touch policy and obtaining a proof. Never overwrite an occupied
location or reset an existing PIN. Show slots only in technical details or an
administrator conflict screen. Store the chosen location in the authenticated
public enrollment record, then verify it on reconnect.

An unconfigured PIV key needs deliberate administrator preparation. Remove factory
PIN, PUK and management-key defaults through a guided, explicitly authorized setup;
do not leave the default management key as the production provisioning mechanism.
Explain that the smart-card PIN is shared by that key's PIV application and is
separate from the normal FIDO2 sign-in PIN. The iPad does not set or reset it.
Recovery secret custody must be settled before implementing this setup.

### Daily experience

1. Connect the key. Show `Security key detected` until a proof identifies it.
2. Finish handwritten consent. After the existing pause, request the key proof.
3. Prompt `Enter your security-key PIN`, with a setup-specific explanation of which
   PIN on the prompt. Show touch guidance. Do not expose slots or management keys.
4. Show `Security key verified` only after Rust validates the exact prepared bytes.
5. Authorize requests iPad biometrics, then the Secure Enclave signs the same bytes.

Changing consent, request, network state or key connection invalidates the proof.
Do not cache a PIN or reusable authorization token across approvals. Incorrect PIN
entry stops without retries. Wrong or unsupported keys get a specific explanation,
never a factor downgrade. Serial numbers and USB presence do not authenticate a key.

### Implementation boundaries

Rust owns capability-to-policy decisions, enrollment bindings, signature validation,
canonical challenges, proof freshness and migration validation. Swift owns USB/APDU
transport, key discovery, native prompts and Secure Enclave operations through the
existing narrow FFI. Discovery is read-only and does not submit a PIN.

Define one adapter interface for capability inspection, enrollment proof and
approval proof. Distinguish `unsupported` from `unavailable`, `cancelled`, `wrongPin`,
`blocked`, `transportFailure` and `invalidProof`. Only a successful unsupported
capability result may offer a different method during new enrollment. Registration
and approval stay explicit operations; no key writes happen on insertion.

The implementation must not take a CCID connection while a native Apple request
owns the key. Release one transport before using another during explicit setup.
Capability reports are inputs to selection, not evidence of a key's factory origin.

## Open questions

- Which actual firmware does the owner's key report, and what operations succeed
  over iPad USB? Record a read-only probe and physical signing results.
- Which firmware/model combinations meet the offline profile? Test real units;
  a model name or firmware table alone does not certify support.
- Where does an organization keep PIV recovery and management secrets? Decide with
  the owner before implementing write operations; never put secrets in exports.
- How is a method migration authorized by a future on-chain factor registry?
  Exercise old-proof rejection before enabling migration for funded accounts.

## Acceptance plan

- Unit-test adapter selection and failure classification, no silent downgrade,
  immutable enrolled bindings and migration rejection with incomplete proofs.
- Exercise real direct-CTAP PIN/touch and exact-message signatures on the iPad.
- Repeat offline signing after app termination, reboot, seven days offline and an
  offline app update. Document results rather than promise indefinite availability.
- Test wrong key/PIN, cancellation, low retry counts, unplugging during each phase,
  changed consent and replay across fresh app sessions.
- Test PIV setup on a spare key with empty, occupied and custom-management states;
  verify no overwrite, implicit PIN change or leaked recovery material.
- Preserve local-vs-on-chain policy distinctions. Existing bridge UV enforcement
  gaps still need the separate production policy layer.

## Risks

PIV's separate PIN cannot be abstracted into the existing FIDO2 PIN. Raw PIV proofs
also differ from FIDO assertions and must not inherit their verification claims.
Native WebAuthn remains dependent on OS association state. A direct transport avoids
that dependency but still needs hardware validation, resource bounds and lifecycle
handling. An iPad reinstall cannot reconstruct a lost Secure Enclave private key.

## What we learned

2026-11-10: Yubico documents FIDO2 over CCID from firmware 5.8. The repository already
contains direct CTAP and PIV implementations, but configured builds prefer native
WebAuthn. This proposal changes the default for new offline-profile enrollments;
it does not change existing credentials or the current app behavior.

## References

- [Current onboarding design](../DESIGN.md#device-onboarding-and-registered-usb-c-keys-2026-11-10)
- [Yubico firmware capabilities](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-firmware-overview.html)
- [Yubico PIV](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-piv.html)
- [PIV setup requirements](https://developers.yubico.com/PIV/Guides/Device_setup.html)
- [Apple association caching](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links)

2026-11-10 implementation: [ADR 0008](../adr/0008-prefer-direct-usb-for-new-offline-enrollment.md)
adopts the new enrollment default and preserves registered methods. Rust selection,
iPad diagnostic/export and explicit native compatibility mode are implemented.
The iPad's factory-management PIV generation path is removed. Physical direct-USB
acceptance and the Mac provisioning assistant remain open; no migration is enabled.
