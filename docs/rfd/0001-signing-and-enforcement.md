# RFD 0001: signing keys and policy enforcement

State: discussion
Authors: Vow project · Started: 2026-11-09

## Problem

The intended device holds a nonexportable key, authorizes multisig actions while
offline, and requires handwriting, biometrics and optionally a YubiKey. Native
Solana transaction signatures use Ed25519; Apple's public Secure Enclave signing
API does not supply that key type. Existing multisig compatibility is unresolved.

## Sketch

Prototype three routes from [DESIGN.md](../DESIGN.md#3-signing-routes-to-evaluate).
Prefer P-256 device approvals if they can be enforced by an acceptable multisig
integration. Keep software Ed25519 as an explicit compatibility tradeoff rather
than claiming enclave custody. Evaluate an external Ed25519 signer where useful.

Separate fund-moving signatures from attached evidence. If YubiKey evidence is
mandatory, find an unavoidable verifier. Handwriting remains an app-level check;
there is no proposed secure hardware matcher. Preserve the distinction in UI.

## Open questions

- Must the first version integrate with an existing Squads deployment? Inspect
  the exact deployed program and test member/PDA approval constraints.
- Can a small adapter enforce P-256 approvals, factor signatures, epochs and
  replay rules without becoming a unilateral vault authority? Build a minimal
  end-to-end prototype and independently review its authority graph.
- Can the chosen USB-C YubiKey model produce the required offline action-bound
  signature on the target iPadOS? Test PIV and FIDO2 separately on real hardware.
- Can App Attest assertions be generated and independently validated without
  network access after enrollment, including after reboot and app update? Test
  version fields, counters, reordering, reinstall and unsupported-device behavior.
- Is handwritten capture sufficient, or is biometric matching mandatory? Measure
  false accept/reject rates and define an accessible recovery policy before use.
- What team sizes, threshold, loss tolerance, transaction families and state
  freshness are required? Obtain these from the owner before fixing the pilot.

## Risks

A custom adapter adds on-chain code and upgrade governance. Software Ed25519
permits key exposure to the process. An external signer adds hardware and transport
constraints. Requiring every optional factor can make recovery impossible.
Treating attached attestations as enforced policy creates misleading assurance.

## What we learned

2026-11-09 follow-up: The linked v4 revision uses Solana signer accounts for votes.
An existing External Signature Program supplies P-256 WebAuthn verification and
PDA-signed execution. Evaluate that bridge before proposing a new program, with
special attention to its 150-slot expiry and the distinction between WebAuthn and
raw Secure Enclave signatures. Pinned sources are in `../RESEARCH.md`.

2026-11-09: Public platform documentation supports P-256 hardware signing, current
App Attest version metadata, and external-key SDK paths. None establishes the full
offline approval workflow. Source references live in [RESEARCH.md](../RESEARCH.md).
