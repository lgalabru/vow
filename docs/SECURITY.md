# Soundness and threat model

Status: preliminary analysis, 2026-11-09. No implementation has been audited.

## Intended guarantee

A quorum of independently provisioned members authorizes a particular action under
a particular project quorum policy. Organization enrollment alone does not grant
permission to approve every project. The executor cannot replace that action,
count a member twice, count a member outside the selected quorum, or reuse an
approval under another organization, project, quorum, chain, proposal or policy epoch.
The hardware-backed route adds nonexportable device signing keys. Handwriting and
identity checks supply additional evidence with the limitations below.

Enrollment credentials must be authenticated independently of project creation.
Creating or reusing a quorum references existing enrollments; it cannot silently
add an unverified member or edit a quorum used by other projects. Revocation and
device replacement must account for every project referencing the affected member
or reusable quorum. Authorized transition and offline freshness rules remain
production design work. Prototype readiness flags and unsigned workspace imports
are not enrollment evidence or a production authorization mechanism.

## Adversaries and boundaries

Assume the organizer Mac, proposer, RPC endpoint, package transport, and collector
can be malicious. Assume imported schemas, state and labels can be misleading.
Plan for stolen iPads, captured packages, replay, substituted device keys, a
compromised member, and coercion. A threshold of compromised members can authorize
actions; that is the multisig's stated trust boundary.

A compromised iPad OS or Vow app can falsify what it displays or what matching
checks it performs. Secure Enclave protects its key, not the accuracy of the app's
screen. All signers using the same malicious app update is a correlated failure.
Offline operation reduces remote access; it does not repair a compromised install.

## Soundness findings

| Issue | Assessment and required response |
|---|---|
| Secure Enclave Ed25519 | Incompatible with the stated hardware assumption. Evaluate P-256 adapter, software Ed25519, or an external signer. |
| Malicious organizer | Member keys originate on iPads; independent roster/digest checks and quorum confirmation prevent unilateral substitution. Passport checks still require honest identity witnesses. |
| Blind or misleading review | Pin semantics as well as schemas, reject unknowns, and display the inner action. Do not trust an RPC summary or supplied lookup-table mapping. |
| Upgraded target program | An unchanged program address can execute changed logic. Pin/restrict upgrades or enforce compatible execution preconditions. A local snapshot alone cannot freeze on-chain code. |
| Stale offline state | Declare snapshot trust and age limits; enforce action preconditions and policy epoch at execution. Offline inspection cannot promise current chain state. |
| Replay or approval substitution | Bind all factors to one canonical action digest, organization, project, quorum policy digest, chain, multisig, member, epoch and unique request. Chain enforcement consumes replay state. |
| Factor stripping | Appended evidence is removable unless the accepting policy and enforcement point require it. Verify this with a direct bypass attempt. |
| Handwriting forgery or replay | Use matching as a measured risk signal, not a cryptographic factor. Bind fresh consent to an action. App compromise can inject strokes. |
| Biometric misunderstanding | OS key access control checks enrollment, not passport identity or transaction comprehension. Shared passcodes and extra enrolled biometrics affect assurance. |
| WebAuthn-shaped evidence | The compatibility spike confirmed that the reviewed bridge accepts a signed payload without UV. App-constructed UP/UV fields cannot independently attest a biometric event, even if UV checking is enabled. |
| Lost device or changed biometrics | Nonexportable keys cannot be restored onto another iPad. Replace membership through a surviving quorum with delays and independent checks. |
| App or format update compromise | Separate app distribution, decoder signing and team policy authorities. Updates never silently broaden permitted operations. Use independent release review. |
| Central witness, registry, VPN or MDM | No one service may authorize a transfer or block all recovery. Preserve offline verification and alternative collector paths. MDM admins remain trusted for device administration. |
| Passport data exposure | Keep raw scans transient where possible; minimize retained identity evidence and access. Flipper storage and logs need explicit erasure handling. |
| Device-family common failure | Independent members alone do not diversify Apple OS or distribution risk. Consider a separate hardware signer or independent review implementation for high-value policy. |

## Recovery and policy changes

Define the number of simultaneously lost or unavailable members the threshold
must tolerate. Keep recovery authorities separate from the organizer and avoid a
single backup key that can bypass the ordinary threshold. Record timelocks and
notifications where the target wallet supports them. Test recovery before funding.

Membership, factor requirements, decoder trust roots and recovery changes need
quorum authorization and a monotonic policy epoch. Store the latest accepted epoch
on each device; a stale device still needs execution-side enforcement. Restoring
an old local backup must not resurrect revoked signing authority.

## Production gates

No funds before an independent review of the selected signing route, decoder and
display binding, ceremony protocol, replay protection and recovery implementation.
Physical-device tests must demonstrate the documented biometric and YubiKey policy.
Red-team tests must attempt execution with missing evidence and a compromised Mac.
No assurance label may imply that a pen, passport issuer or Apple authenticated
facts they did not actually attest.

## Prototype offline UI gate

The iPad UI is fail-closed on system network-path state. Only an unavailable path
opens the workspace. Connectivity interrupts pending approval, and the native
signing flow checks offline state and an unchanged interruption generation before
key use and before completion. Changing back to offline does not revive old consent.
This protects the normal app flow; it does not independently enforce a chain policy,
prevent other processes from communicating or establish a physical air gap.
Monitor transition latency and OS key operations remain platform boundaries. A
signature operation already started cannot be undone, but its result must not be
finalized or exported after a detected interruption. Physical-device tests must
exercise rapid path changes, backgrounding, VPN and external network adapters.

## Transaction capture and reproduction boundary, 2026-11-09

The WKWebView provider has no signing-key interface. A main-frame origin grant is
scoped to one document and organization/project/quorum context. Navigation and
process termination revoke it. Captured bytes are bounded, independently decoded
and rejected when unsupported by the signing preview. Other transactions may be
inspected, but inspection cannot authorize them. Plain dumps without network
metadata require an explicit local project assumption. A devnet/mainnet name from
a page is not sufficient; packaged context and RPC reads bind the genesis hash.

The prototype replay accepts only synthetic state and native builtins. Matching
logs, compute units and balances proves reproduction relative to those fixtures.
It does not authenticate chain state, validate real signatures, or guarantee a
future transaction's outcome. Executable downloads remain disabled. Program
Metadata authorship and matching IDL hashes do not establish program semantics.

An attestation plan is descriptive. No deployed guard, Squads membership bridge,
YubiKey verifier or App Attest assertion verifier is supplied by it. Required
unimplemented factors block prototype approval. Real execution requires an
unavoidable guard and tests of every alternate authority path, including already
approved stale proposals and spending limits. See RFD 0003.

Refreshing a supported unsigned draft's blockhash creates a new captured session,
preserves its decoded action and invalidates prior replay evidence. The bundle
records observation time and expiry height. The offline timer is estimated and
cannot establish chain validity. When context is present, Rust also rejects local
approval preparation/completion past that estimate or with an inconsistent future
observation. Historical transaction inspection remains available. Persistent
multisig actions, bridge proofs, durable nonces and instruction-specific deadlines
need separate lifetime policies.

USB-C connection gating, added 2026-11-10, is distinct from security-key proof.
YubiKit Management metadata can be emulated. The local gate neither creates nor
verifies a key signature, and is not included as an authenticated factor in exported
approvals. Rust continues to reject requests requiring unimplemented security-key
evidence. Device connection epochs and a final live read prevent the normal UI
from completing an interrupted operation; they are not an on-chain enforcement
boundary. Simulator presence injection is DEBUG and simulator-only.

## Device identity and local registered-key enforcement

The iPad persists the enclave's opaque key reference in a non-synchronizing,
passcode-protected, device-only Keychain item. The enclave key uses current-biometry
access control. Restore errors fail closed and never trigger automatic replacement.
The app has no identity deletion or recovery shortcut. Workspace reset does not
delete the signing identity. A lost device or invalidated biometric policy requires
an administrator-approved member replacement, still unimplemented.

When configured, the preferred USB adapter uses Apple external-key WebAuthn with
a compile-time pinned HTTPS RP and associated domain. The system owns PIN entry
and retry limits; Vow cannot inspect remaining attempts. Only external security-key
requests are submitted, with required user verification and the exact credential.
Rust validates raw client JSON, type, origin, challenge, RP hash, UP/UV, non-backup
flags and the P-256 signature before permitting the device signing operation.
Registration CBOR/COSE is bounded and strictly parsed. Factory attestation is not
verified. Neither an associated domain nor the signed origin proves a particular
app version or hardware provenance. Offline behavior needs hardware validation.

The legacy direct USB factor is a discoverable FIDO2 P-256 credential with mandatory
user verification. Rust checks the pinned key, credential binding, RP hash, UP/UV,
non-backup flags and exact signed bytes. The fixed `vow.invalid` CTAP namespace is
not proof of an Apple app identity, a legitimate website origin or factory hardware.
A PIN token permits credential discovery, but the app reads only Vow's RP scope.
Unknown, ambiguous or incompatible credentials are never replaced after a failed
lookup. Counter-based clone detection is not implemented.

Legacy PIV credentials remain pinned and require PIN-always and touch-always.
The UI makes the separate PIN explicit. The app never sets, changes or resets a
PIN, never requests a management key, never changes retry limits and, in the direct
adapter, never uses the final remaining attempt. Factory smart-card PINs require external setup. An
explicit enrollment can create a key in an empty reserved PIV location only after
checking existing nonfactory PIN and factory management configuration. Occupied
incompatible credentials are rejected. A failed PIN is not retried automatically.

Keychain restores the existing device key when available within the same signing
identity. A missing Secure Enclave reference cannot be reconstructed from a public
device ID, app ID, account ID or FIDO credential. Reinstall and device replacement
must not be presented as guaranteed recovery. The public record keeps chain
registration and factory/app attestation explicitly unverified.

PINs and tokens never enter Rust, exports or persistent storage. Swift UI strings
and SDK internals do not guarantee secure zeroization of all transient copies.
Physical input, token lifetime, firmware compatibility and removal behavior remain
hardware validation gates. Local signatures do not satisfy the separate unfinished
production attestation guard, passport enrollment or multisig activation.
