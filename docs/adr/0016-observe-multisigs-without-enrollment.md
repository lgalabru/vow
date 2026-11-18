# ADR 0016: Observe multisigs independently of signing enrollment

Status: accepted (2026-11-17)

## Context

A coordinator needs to retrieve proposals from multiple existing Squads multisigs,
including ones where this Mac holds no member key. Requiring a local organization
or ceremony first would conflate discovering public chain state with signing
permission. Raw vote messages also omit the stored action they authorize.

## Decision

Keep a small local Mac watchlist keyed by canonical address and explicit network.
Decode account data and derive proposal/transaction PDAs in Rust through bounded,
read-only RPC calls. Show stored actions alongside proposal status and voting
history. Preparation revalidates the selected existing member, builds an unsigned
native Squads vote, and includes the stored action in its review fixtures.

Watching, simulation and transfer do not grant signing authority. The existing
hardware/guard policy remains in force. See [the design](../DESIGN.md#observing-squads-multisigs)
for the user flow and [contracts](../CONTRACTS.md#connected-multisig-observation)
for limits and network handling.

## Consequences

Teams can watch and prepare requests without importing keys or inventing
organization enrollment. A stale proposal cannot appear approvable solely because
its status enum is Active. RPC data remains coordinator context, not a chain
proof; actual on-chain signing and execution require their own verified adapter.
