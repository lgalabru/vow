# ADR 0010: Separate personal identities from organization registration

Status: accepted (2026-11-10)

## Context

The previous profile form required an enrolled organization member before a person
could configure signing hardware. It mixed personal setup, physical enrollment and
quorum composition. Mac and iPad screens also accumulated inconsistent titles,
spacing, accent colors and connection controls.

## Decision

Create an organization-independent personal identity first. It has a stable ID,
version, display name, method, public key, address, optional account path and proof.
Ledger proves an exact `vow.identity.enrollment.v1` challenge. The iPad reuses its
verified dual-key enrollment without rotating a device key.

Keep organization registration separate. A version-2 organization profile embeds
the verified personal identity, pins its key and policy, and associates it with an
already enrolled member. Quorum seats continue pinning exact registration versions
and digests as in ADR 0009. Version-1 registrations remain supported. A local
association does not prove that the organization authorized it; production ceremony
policy must authenticate that association.

Use shared native SwiftUI components and task vocabulary across the full app.
Keep BLE, USB, Secure Enclave and security-key operations in platform adapters and
canonical bytes and validation in Rust. First launch and Add Profile use the same
assistant. See the interface rules in `../../DESIGN_MEMORY.md`.

Store public identity and registration records in a versioned atomic local archive,
separate from nonsynchronizing device Keychain records. Read and verify saved
records before deciding setup is needed. Migrate the previous UserDefaults catalog
without changing signing keys. Do not enable iCloud sync implicitly.

## Consequences

Personal setup no longer depends on an organization roster. Different hardware
profiles remain independently identifiable; a second label for the existing iPad
uses the same underlying signing key and cannot count twice in a quorum.

The archive currently covers personal identities and organization profile records.
Workspace state and approval history still require durable repositories. Cloud
backup requires explicit consent, deliberate online maintenance and a restore flow
that distinguishes public metadata from locally available keys. A restored profile
must never imply that a Secure Enclave key was restored or a member was reauthorized.

## References

- [Full-app interaction and storage design](../DESIGN.md#native-app-experience)
- [Apple onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Apple iPadOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)
