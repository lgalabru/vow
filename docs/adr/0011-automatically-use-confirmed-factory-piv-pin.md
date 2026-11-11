# ADR 0011: Automatically use a metadata-confirmed factory PIV PIN

Status: accepted (2026-11-11)

## Context

The owner requested automatic factory-PIN handling, with an existing-PIN prompt
only when needed. Repeated mode and PIN choices obscure the signing flow.

## Decision

For prepared PIV signing keys, we use the factory PIN only after fresh key metadata
confirms it. We never guess on configured keys or use the final retry. A rejected
automatic attempt reveals the PIN prompt and suppresses automatic attempts for
that key for the monitor's lifetime. We retain the credential and administrative
configuration checks. We do not change PINs or provision keys in this change.

See [the flow](../DESIGN.md#automatic-smart-card-pin-handling-2026-11-11).

## Consequences

A public factory PIN supplies no independent knowledge factor. Touch, possession,
iPad authentication and cryptographic verification remain required. Existing
custom PINs and native Apple authentication remain supported. Missing signing
credentials still require preparation.
