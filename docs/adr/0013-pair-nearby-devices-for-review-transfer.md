# ADR 0013: Pair nearby devices for encrypted review-file transfer

Status: accepted (2026-11-11)

## Context

The owner wants a Mac menu-bar action that prepares clipboard transactions and
delivers them to a nearby signing iPad. AirDrop cannot silently target a particular
device through its public API. Handoff is oriented around resuming an activity.

## Decision

Use Multipeer Connectivity with required encryption and explicit foreground iPad
receiving. Authenticate an ephemeral X25519 exchange with device-only Ed25519
identities, commit before revealing hello data, and compare a short code on both
devices during first pairing. Pin identities and encrypt counter-bound application
messages independently of MCSession transport. Confirm the exact received file hash.

Keep receiving outside the signing workspace. Close transport and require the
existing offline gate before import/review. Preserve USB, file export and AirDrop
as alternative transports. Pairings can be forgotten without changing signing keys.

See [the flow](../DESIGN.md#clipboard-preparation-and-nearby-transfer-2026-11-11).

## Consequences

Nearby transfer requires radios and Local Network permission. It does not require
an Internet connection, authorize signing or establish organization membership.
Physical acceptance and independent protocol review remain production gates.
