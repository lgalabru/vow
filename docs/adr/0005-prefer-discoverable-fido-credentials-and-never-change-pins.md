# ADR 0005: Prefer discoverable FIDO credentials and never change a PIN in Vow

Status: superseded by 0006

## Context

The owner could not complete the smart-card setup flow. PIV slot identifiers,
management keys and factory PIN changes are inappropriate requirements for ordinary
member onboarding. A YubiKey's FIDO2 sign-in PIN is separate from its PIV PIN.
Yubico documents direct FIDO2 over USB CCID starting with firmware 5.8.

## Decision

Retain the device-only Keychain and Secure Enclave policy from ADR 0004. Prefer
PIN-verified CTAP2 over USB CCID when the connected key exposes the required
capabilities. Use discoverable P-256 credentials protected by mandatory user
verification. The offline namespace is `vow.invalid`, with a fixed opaque user
handle derived from `vow.offline.security-key.v1`. This is an internal CTAP
namespace, not a website, Apple associated domain or app identity attestation.

After the owner submits the existing PIN, enumerate only credentials for Vow's
namespace. Reuse the matching credential. Create one only if enumeration succeeds
and proves no matching credential exists. Ambiguous, incompatible and failed
lookups fail closed. Do not enumerate other relying parties, overwrite a matching
credential, or delete any credential.

Vow never sets, changes or resets a PIN. Unconfigured FIDO keys require PIN setup
with Yubico tools. Compatible existing PIV enrollment remains supported without
conversion. A legacy key needing a separate smart-card PIN or custom management
authorization gets explicit Mac/administrator instructions. The iPad never asks
for a management key. If a nonfactory smart-card PIN is already set and the
management credential is confirmed as factory-default, explicit enrollment can
create a key in the empty reserved location without further management input.

Rust verifies the exact challenge, pinned credential public key, Vow RP hash,
user-presence and user-verification flags. Device enrollment v2 carries FIDO
credential information; v1 PIV records remain valid. Signing methods cannot be
downgraded within a Rust session.

## Consequences

Compatible keys use the owner's usual FIDO2 PIN and require no new PIN or slot
selection. Vow can rediscover its hardware credential across app installations,
but this does not recreate a lost Secure Enclave private key. Keychain lookup uses
a stable service and account within the same app signing identity. Recovery after
uninstall, device loss or biometric invalidation remains a separate admin process.

Older keys can still need one-time smart-card setup outside the iPad app. The
new CTAP path needs hands-on validation on the selected firmware. The protocol is
offline CTAP, not a full WebAuthn browser client. Neither the namespace nor a
signature attests to an Apple app version, a person or factory hardware origin.

## References

- [Onboarding design](../DESIGN.md#device-onboarding-and-registered-usb-c-keys-2026-11-10)
- [FIDO and reinstall research](../RESEARCH.md#discoverable-fido-credentials-and-installation-identity-2026-11-10)
- [Yubico FIDO transport](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-fido.html)
- [Apple identifierForVendor](https://developer.apple.com/documentation/uikit/uidevice/identifierforvendor)
