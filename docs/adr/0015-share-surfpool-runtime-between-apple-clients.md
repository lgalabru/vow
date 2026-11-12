# ADR 0015: Share the Surfpool SDK runtime between Apple clients

Status: accepted (2026-11-11)

## Context

Mac preparation embeds Surfpool while the old iPad adapter directly creates LiteSVM.
That split restricts reproduction to simple built-in transfers and cannot expose
Studio-style instruction profiles for a prepared channel transaction.

## Decision

Both clients use `vow-runtime` with pinned Surfpool SDK 1.7.0. Snapshot execution
starts a fresh offline SDK fork, restores bounded account and program fixtures,
reconstructs managed sysvars through the recorded clock, and exports runtime
results and instruction profiles. No remote endpoint enters the offline API.
The [design](../DESIGN.md) describes presentation and authorization boundaries.

## Consequences

We share execution behavior and profile schemas with Surfpool Studio. The mobile
binary grows because the published SDK includes its local RPC services. A local
nix compatibility patch excludes macOS-only kernel APIs from the iPadOS build.

Simulation remains inspection evidence. It cannot authenticate downloaded state
or program deployment, extend an expired blockhash, or establish a multisig and
execution guard. Existing rehearsal approvals retain their stricter program policy.
