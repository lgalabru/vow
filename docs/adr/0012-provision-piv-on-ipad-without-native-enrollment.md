# ADR 0012: Provision direct PIV signing on iPad without native enrollment

Status: accepted (2026-11-11)

## Context

Native Apple domain association repeatedly blocked the owner's YubiKey setup.
Direct setup still redirected to that same failing path because it could not
prepare an empty PIV location. The owner requested one offline flow with defaults.

## Decision

New profiles use direct USB. An unsupported FIDO applet can select PIV inspection
and an explicit Set Up This Key action. We no longer offer native Apple enrollment
for new production profiles. Existing native enrollments remain pinned and work
through their original adapter. Pending native registration alone does not select
that adapter.

On supported firmware, we verify the existing PIN, durably journal administrative
secrets before writes, secure factory administrative settings and generate a
P-256 key only in an empty Vow location. We preserve custom settings, PINs and all
existing credentials. We recheck the connection at each mutation boundary and
resume from fresh metadata after interruption.

See [the implementation flow](../DESIGN.md#on-device-piv-setup-2026-11-11).

## Consequences

This removes associated-domain state from new direct profiles. Vow holds new PIV
administrative secrets in this iPad's private Keychain. Full reset deletes them;
losing the journal may lose administrative access. Recovery export and physical
firmware verification remain required work. Older firmware can still require Mac
preparation. Factory PIN use follows ADR 0011 and is not a knowledge factor.
