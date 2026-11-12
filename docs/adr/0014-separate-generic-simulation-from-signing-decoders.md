# ADR 0014: Separate generic simulation from signing decoder coverage

Status: accepted (2026-11-11)

## Context

The existing browser preview accepts a single unsigned SOL transfer. The owner
requires clipboard preparation for any transaction kind, including multiple
programs and address lookup tables.

## Decision

Parse canonical legacy/v0 wire transactions independently of signing decoders.
Simulate original bytes in a connected Mac's local Surfnet fork, using a
source-genesis-checked network and recording state provenance and clock context.
Export an inspection container with bounded fixtures, runtime results and a
separately labeled follow-up execution profile. Retain failed runtime results.
Never broadcast the transaction to the source RPC or strip existing signatures.

Generic simulation evidence remains untrusted review context on iPad. It does not
relax decoder, profile, quorum, signing or executable-loading requirements.

## Consequences

Preparation covers arbitrary programs within runtime and resource limits. It does
not establish atomic/authenticated chain state, future execution success or
independently reproduced results on iPad. Generic offline replay remains separate
work. The existing synthetic transfer replay retains its narrower verification.
