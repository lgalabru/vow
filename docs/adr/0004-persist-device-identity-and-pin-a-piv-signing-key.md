# ADR 0004: Persist the device identity and pin a PIN-protected PIV signing key

Status: superseded by [ADR 0005](0005-prefer-discoverable-fido-credentials-and-never-change-pins.md). The device-only persistence policy is retained.

## Context

Session-only device keys cannot provide a stable enrollment identity. Recognizing a
USB serial number does not prove possession of a registered signing key. The owner
uses a USB-C YubiKey 5C NFC on an offline iPad mini. FIDO2 over USB CCID cannot be
assumed for older firmware; AuthenticationServices enrollment introduces separate
relying-party and distribution requirements.

## Decision

Persist the Secure Enclave P-256 reference in device-only, passcode-protected,
non-synchronizing Keychain storage. Retain current-biometry access control. Do not
silently replace unreadable identities or provide a software fallback on hardware.

Use a generated P-256 credential in PIV slot 82 with PIN-always and touch-always
policies. Inspect before any write. Reject incompatible occupied slots. Require
explicit management authorization for empty-slot creation and an owner-selected
replacement for any factory PIV PIN. Never reset a key or consume its final PIN
attempt. A failed PIN is never retried automatically.

Rust prepares enrollment bytes that bind both public keys and a fresh nonce, then
verifies both signatures. Each local approval binds the enrolled security-key
public key and requires its signature over the same exact bytes as the device.
The exported enrollment states that chain registration and hardware attestation
are incomplete. It is not presented as a Solana member address.

## Consequences

The device identity survives app restarts. Approval requires the registered key,
its PIV PIN, physical touch and iPad authentication. Swift handles Apple and USB
hardware; Rust owns canonical messages and signature verification.

PIV PIN changes affect other PIV credentials on the same key. Interrupted setup
can leave a changed PIN or newly created credential, so inspection must support
resumption. Keys with incompatible slot 82 contents cannot enroll through this
flow. Biometric changes, device loss and reinstall need a recovery design before
production membership. Local policy observations are not remote attestations.

## Possible future improvements

Verify a deployed multisig adapter, activate membership through an admin-reviewed
registration transaction, implement member replacement and recovery, and evaluate
factory attestation and supported FIDO2 firmware independently.

## References

- [Device onboarding design](../DESIGN.md#device-onboarding-and-registered-usb-c-keys-2026-11-10)
- [USB-C and PIV research](../RESEARCH.md#pin-protected-offline-usb-c-enrollment-2026-11-10)
- [Enrollment contract](../CONTRACTS.md#offline-device-enrollment-version-1)
