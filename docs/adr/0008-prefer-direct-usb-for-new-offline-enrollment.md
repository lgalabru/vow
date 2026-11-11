# ADR 0008: Prefer direct USB signing for new offline enrollments

Status: superseded by 0012

## Context

Repeated native Apple AS1004 failures after offline development installations make
associated-domain state a poor default dependency for the offline profile. The
owner wants simple PIN and touch UX with safe defaults. Existing direct USB CTAP
and PIV adapters already validate bound P-256 proofs.

## Decision

For new enrollments, inspect direct USB capabilities before selecting a method.
Rust prefers compatible direct FIDO2. Only an explicit unsupported applet result
may offer prepared PIV signing. Probe errors never select another method. Keep
native Apple signing as an explicit compatibility option and preserve all existing
native, direct CTAP and PIV registrations without automatic migration.

The iPad never provisions PIV keys using a factory management key. Unprepared PIV
keys require Mac administrator setup. PINs, credentials and the Secure Enclave key
remain unchanged by capability inspection. Read-only diagnostics expose firmware,
probe outcome and the preserved enrollment method without claiming hardware origin.

## Consequences

New compatible USB FIDO enrollments avoid Apple domain association and use the
existing FIDO2 PIN. Older keys can need a separate PIV setup and PIN. A read-only
probe is not a physical signing certification. Real hardware acceptance, explicit
migration authorization and a secure Mac provisioning assistant remain necessary.
The owner must settle recovery-secret custody before provisioning writes are built.

## References

- [Flow and safety constraints](../rfd/0004-offline-hardware-key-defaults.md)
- [Current design](../DESIGN.md#direct-usb-enrollment-defaults-2026-11-10)
