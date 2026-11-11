# ADR 0009: Bind immutable signing profiles to quorum seats

Status: accepted (2026-11-10)

## Context

The owner wants Nano X, Nano Gen5 and Flex Ledger identities alongside the existing
iPad/security-key flow. A member can use different signing keys and policies in
different quorums. The former member-ID-only quorum cannot express this choice.

## Decision

Register named profiles against enrolled organization members. A quorum seat pins
member, profile ID/version/digest and signer address. Reject duplicate people or
addresses, foreign bindings, stale versions and revoked profiles. Preserve existing
unprofiled rehearsal quorums explicitly; do not change their keys or policy on adding
a profile. Profile-enabled ceremony/request schemas use version 5.

Keep signature schemes distinct. Ledger enrollment and rehearsal approvals use
verified Ed25519 off-chain envelopes. Existing iPad approvals retain P-256 and the
pinned security-key policy. Neither is an executable Squads vote. Profile changes
and local revocation do not update on-chain membership.

Use solana-keychain published PR 358 at
`0b7bf8368ea5650e6870504c6c36ac2d1aad3bc8` for macOS USB. Keep that dependency out
of the iPad graph. Use a thin native CoreBluetooth adapter for the target Ledger
services on iPad, with Rust APDU/framing and signature checks. The iPad mini cannot
use the desktop HID backend or the M-series-only USBDriverKit path. Do not add the
archived Swift BLE package or an alpha KMP dependency to the app.

## Consequences

Members can reuse profiles across quorums without repeating identity enrollment.
Profiles and public proof records persist locally and can be shared/imported.
The public catalog is a prototype registry, not authenticated organization policy
or rollback-resistant revocation storage. Production needs authorized registration,
on-chain profile membership/enforcement and recovery.

Both target Ledger models need physical BLE and USB acceptance. Device UUIDs and
names are hints, not factory attestation. Bluetooth can operate while internet is
disconnected; that differs from an all-radios-off requirement. Host cancellation
cannot guarantee dismissal of a Ledger prompt. No blind-signing setting is changed.

## References

- [Flow and acceptance plan](../rfd/0005-signing-profiles-and-ledger.md)
- [Published dependency PR](https://github.com/solana-foundation/solana-keychain/pull/358)
- [Ledger identifiers](https://developers.ledger.com/docs/device-interaction/dmk-ts/references/identifiers)
- [Apple USBDriverKit constraints](https://developer.apple.com/documentation/usbdriverkit)
