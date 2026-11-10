# ADR 0002: Enroll organization members once and reuse project quorums

Status: accepted (2026-11-09)

## Context

The first prototype used a team-wide threshold shared by all projects. The owner
clarified that organization members complete physical enrollment once, while each
project chooses its own quorum or reuses an existing one.

## Decision

Organization enrollment binds a member to their identity evidence and device key.
It is independent of any project. An organization owns reusable named quorums,
each containing enrolled-member references and a threshold. A project references
one quorum. Project creation either selects an existing quorum or creates a new
one from enrolled members, without repeating physical enrollment.

Quorums are immutable in the prototype. Requests and approvals bind organization,
project, quorum ID and quorum policy digest. Project creation does not alter the
enrollment fingerprint or any existing project’s approval policy.

See [DESIGN](../DESIGN.md#4-organization-enrollment-and-project-setup) for lifecycle
and [CONTRACTS](../CONTRACTS.md#implemented-prototype-abi) for prototype commands.

## Consequences

Enrollment, quorum policy and project configuration have separate trust and
update boundaries. Reusing a quorum does not merge vaults or replay domains.
The rehearsal’s readiness flags are not authenticated enrollment evidence.
Production needs durable enrollment credentials, signer-key membership checks,
authorized project configuration and revocation/replacement protocols.
