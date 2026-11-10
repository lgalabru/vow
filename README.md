# Vow

The public website is built in [apps/web](apps/web/README.md) and deploys to
`https://vow.scarce.sh`. Run `just web-dev` to work on it locally.

Vow is a proposed ceremony coordinator for Mac and an offline approval app for
iPad. Teams enroll members in person, inspect multisig actions on separate
devices, and export approvals that can be verified before execution.

Status: native prototypes and feasibility work, 2026-11-09. A
[P-256 compatibility spike](spikes/p256/README.md) exercises Apple signing against
the existing bridge in LiteSVM. The native apps rehearse ceremonies and approvals; no production app or on-chain adapter exists here.
Rust owns portable logic; Swift supplies Apple UI and platform adapters through FFI.
Solana Foundation distribution is
a proposed distribution arrangement, not an established publisher relationship.

Start with the approval use case in [docs/DESIGN.md](docs/DESIGN.md), then read:

- [Security and soundness](docs/SECURITY.md)
- [Proposed package contracts](docs/CONTRACTS.md)
- [Implementation plan and acceptance gates](plan.md)
- [Platform evidence and research](docs/RESEARCH.md)
- [Open design choices](docs/rfd/0001-signing-and-enforcement.md)

Secure Enclave signing uses P-256. The Squads adapter remains a production gate;
registration compatibility does not yet prove delayed voting and execution.

## Run the native prototypes

Use an Apple Silicon Mac with Xcode 26 or later, Rust stable, and `just`.
Install the Rust targets once:

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim
just mac-run
just ipad-run
```

The iPad command chooses an available recent iPad simulator. To select one:

```sh
python3 scripts/apple-app.py ipad run --simulator <simulator-uuid>
```

You can also open `apps/apple/Vow.xcodeproj` and choose the Vow scheme with
My Mac or an iPad simulator. Xcode builds and links the Rust static library.
For a physical iPad, select your development team in Signing & Capabilities.
The current project builds arm64 targets; Intel Mac support is not configured.

### Try the flow

On Mac, open Members, finish Jordan's sample enrollment and confirm the rehearsal.
Use Quorums or New Project to compose a policy or reuse an existing quorum. Export its ceremony transcript if you want to import
it on iPad. In Requests, create and export a sample request.

On iPad, complete device setup, choose a project from Home, then choose Load Sample Request or import the Mac's JSON request. Review the amount,
recipient and fingerprint. Choose Review & Approve and follow the full-screen Review → Authorize → Export flow. Draw in the consent canvas. After a one-second pause, Vow checks readiness; tap
Authorize, enter the registered key’s PIN, touch the key and authenticate on iPad to create the approval. Vow verifies the signature in Rust before offering Share
Approval. History lets you export the approval again.

The simulator explicitly uses a software key. Physical iPads use a device-bound
Secure Enclave key with biometric access control and no software fallback. That
app is installed on a physical iPad mini; hands-on biometric signing verification
remains pending. Signing identities persist in device-only Keychain storage; workspace state
and receipt history remain in memory. Handwriting is captured, not matched.
Passport reading, pairing, production attestation policy and on-chain
submission are not implemented. Prototype files cannot authorize a real transfer.

Organizations own members who enroll through a physical ceremony once. Projects
select a reusable quorum of enrolled members and an approval threshold. In Mac’s
New Project form, choose Reuse existing or Create new. Creating projects never
resets enrollment or changes another project’s quorum. New organizations start
empty; add members and complete their sample enrollment first. State remains
in memory, and enrollment is simulated until Passport and device pairing are wired.

Explain Request optionally uses Apple’s on-device Foundation Models API after an
explicit tap. Rust supplies bounded transfer facts; generated prose cannot alter
or authorize an approval. Availability is checked locally, with no cloud fallback.
Model assets must already be installed. Native generation has been exercised on
Mac and the iPad mini simulator; physical-device offline testing remains pending.

The iPad opens to a grouped project home with team subtitles and project rows.
A Projects toolbar button returns there from a project’s requests.

A floating red or green connection pill sits at the bottom left on iPad, clear
of Back and other actions, with the request countdown on the right. Mac retains
a footer strip. Sample requests show a five-minute Demo
timer; real blockhash estimates and missing expiry context are labelled separately.
Tap the countdown for details. The same status control stays visible during consent. During onboarding, focusing
a field hides the header and both footer rows to preserve keyboard space. Done
restores them; the offline gate remains active throughout. The iPad app stays
locked until the system reports no available network path. A connected, uncertain
or on-demand path shows a dedicated disconnect screen and blocks the workspace,
review and sharing flows. Disconnecting unlocks automatically. Reconnecting cancels
pending authorization, closes sensitive screens and requires a fresh review.

Vow sends no internet probe. The gate conservatively locks for local networks and
VPNs too, even when they cannot reach the internet. This is an app interaction and
approval guard, not a system firewall. The Mac ceremony coordinator has the bottom
status strip but remains usable while connected.

### Capture a transaction from a webpage

On Mac, open **Apps → Connect Vow → Connect Preview Account → Sign transaction**.
Review optionally refreshes the unsigned draft blockhash using the project RPC,
after checking its genesis, and records its observation and expiry-height context.
Changing the blockhash discards any previous replay.
The native Review → Replay → Checks → Export sheet runs the embedded Surfpool SDK,
exports its pre-state and independently reproduces the result in LiteSVM. Drag the
`.vow` tile, choose Share, or save it. The provider reports explicitly that nothing
was signed or submitted. The accepted signing preview is one unsigned SOL transfer
from a public fixture account, not a general-purpose wallet.

Transactions outside that transfer preview open the generic native wire inspector.
Installed decoding currently recognizes Payment Channels open/distribute as test
cases. These are examples of supported instruction layouts, not app actions.
The inspector exports raw transaction bytes or an optional `.vow` companion.
Account-state verification and an attestation guard remain required before signing
such actions. Unknown instructions and unresolved lookup tables stay blocked.

The iPad also accepts plain binary, hex, base64 and JSON transaction dumps through
Import, Files or a file URL. A `.vow` container is optional. Plain transactions do
not encode their chain or blockhash observation time; the inspector labels the
selected project network as an assumption and shows lifetime as unavailable.
When companion blockhash context exists, it displays an estimated countdown,
observation timestamp and last valid block height. Offline expiry cannot be proven
from time alone. A persistent Squads action needs a fresh outer execution blockhash.

Project networks are explicit: Community grants defaults to Devnet; Operations to
Mainnet. New projects require a network. Captures, RPC metadata reads, review files,
replay bundles and approval preimages are bound to the selected chain and genesis.
The current transfer replay is always synthetic local state, even for a Mainnet
project. Neither app submits to a public network.

### Verification

```sh
just core-test
just core-lint
just mac-test
just ipad-test
```

UI tests exercise the Mac ceremony and the iPad review/consent/sign/share-ready
flow. Xcode stores test screenshots in its `.xcresult` bundle under `.local`.
The production design and remaining milestones still apply beyond this rehearsal.

### iPad setup and your security key

Vow first restores an existing signing identity from device-only Keychain storage,
or asks you to create one. Plug in the security key and choose Check This Key.
Vow never sets, changes or resets a PIN, and never asks for a management key.

When the native Apple security-key domain is configured, iPadOS handles your usual
FIDO2 PIN and key touch in its system sheet. Vow has no PIN field in this path.
This supports older USB security keys without direct CCID FIDO2 support. Activation
requires a controlled HTTPS domain and an associated-domain-capable signing profile;
the current configuration uses `axel.md`. See
[native-key configuration](services/native-key-association/README.md). Offline
registration and assertions still require validation on the physical iPad.

In the legacy adapter, on keys supporting FIDO2 over USB smart-card transport, use the usual security-key
PIN. Vow finds and reuses its existing discoverable credential, or adds one for
Vow if none exists. Your other sign-ins are unchanged. Direct USB CCID FIDO2 needs
YubiKey firmware 5.8 or newer and the required applet capabilities.

Older keys can require a separate smart-card signing setup. The app explains this
before asking for a PIN. A smart-card PIN is different from a FIDO2 sign-in PIN.
If setup is needed, the screen gives Mac/administrator instructions without asking
you to manage PIV locations or reset anything. Existing compatible PIV enrollments
remain supported.

Touch the key when it flashes, then authenticate on iPad to finish. Failed PINs are
never retried automatically. The direct adapter refuses the final remaining attempt;
iPadOS owns PIN handling and retry limits in the native flow. Focusing
a field hides the header and footers; Done restores them. The offline lock stays
active. Simulator tests cover native WebAuthn and legacy signing with labelled software fixtures;
physical FIDO2 and firmware behavior still need hands-on validation.

Under This iPad, share `Vow-device-enrollment.json` with the administrator. This is
a public dual-key proof, not an activated Solana multisig member address. On-chain
registration, production attestation and recovery remain unfinished.

Vow's stable credential namespace helps discover a key's registration across
installations. It cannot regenerate a lost iPad private key. Keychain identity
lookup is scoped to the app signing identity and device; do not rely on uninstall,
new devices or biometric changes preserving it. Those cases need re-enrollment.
