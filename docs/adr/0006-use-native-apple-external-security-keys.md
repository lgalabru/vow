# ADR 0006: Prefer Apple's native external security-key API when configured

Status: superseded by 0008

## Context

The owner's YubiKey 5C NFC cannot use direct FIDO2 over USB CCID. Requiring a
separate PIV PIN makes onboarding harder. Apple supports external security keys
through AuthenticationServices, but requires an associated HTTPS domain.

## Decision

Prefer native external-key registration and assertions when the owner-controlled
RP is configured and matches the app. Require user verification and ES256. Request
only external keys, never platform passkeys. Let iPadOS own PIN and touch prompts.
Pin the HTTPS RP in Rust, Info.plist and Associated Domains. Validate the public
association before enabling configuration; leave the default build disabled.

Use enrollment v3 with the exact WebAuthn client JSON and authenticator data.
Rust verifies origin, type, challenge, RP hash, presence, verification and signature.
Keep the direct CTAP and PIV paths for existing records and unconfigured builds.
Preserve the no-PIN-change rule and all offline/signing generation guards.

## Consequences

Older keys can use the owner's usual FIDO2 PIN without a PIV setup. The owner must
provide an HTTPS host and deploy the association file. Initial domain association
requires connectivity; offline registration and signing must pass physical tests.
System PIN retry handling cannot be inspected by Vow. Native credentials cannot
be enumerated through this API, so interrupted creation persists the public binding
and reinstall recovery can import a verified public record. This cannot restore a
lost Secure Enclave private key. No app-version or factory attestation is claimed.

## References

- [Onboarding design](../DESIGN.md#device-onboarding-and-registered-usb-c-keys-2026-11-10)
- [Configuration and deployment](../../services/native-key-association/README.md)
- [Apple external security keys](https://developer.apple.com/documentation/authenticationservices/supporting-security-key-authentication-using-physical-keys)
