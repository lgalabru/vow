# ADR 0003: Lock the iPad app until its network path is unavailable

Status: accepted (2026-11-09)

## Context

Repeated connectivity warnings cluttered the UI. The owner requested one clean
bottom status indicator and a blocked UI when the signing device can reach the
internet. Detecting internet reachability with a probe introduces traffic and
cannot prove device isolation.

## Decision

Show one bottom status strip per visible screen. Keep the iPad app locked until
`NWPathMonitor` reports an unavailable path. Available, checking, unknown and
connection-on-demand states are locked. This conservatively includes local-only
networks and VPNs. Do not send an internet probe.

Reconnection removes sensitive UI, cancels pending authorization and changes a
monotonic interruption generation. Before key use and approval completion, require
offline status and the original generation. Keep the device key alive across UI
remounts. Unlock automatically after disconnection, requiring a fresh review.
The Mac coordinator remains available while connected.

## Consequences

The UI gate cannot disable networking for the OS or other apps, and monitor updates
have latency. Already-started key operations may finish internally; their result
is discarded after an interruption. There is no normal-use bypass in the iPad app.
AirDrop and managed-connected profiles need a separate authorized transfer design.
Simulator-only debug test controls never compile into physical-device or release
builds. Hardware network-transition verification remains required.

See [DESIGN](../DESIGN.md#prototype-workspace-and-approval-ui) and
[SECURITY](../SECURITY.md#prototype-offline-ui-gate).
