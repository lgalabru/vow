<div align="center">
  <img alt="Vow" src="apps/web/public/vow-glyph.png" width="200">
</div>

<p align="center">
  <img alt="Status: experimental" src="https://img.shields.io/badge/status-experimental-orange">
  <img alt="Core: Rust" src="https://img.shields.io/badge/core-Rust-black">
  <img alt="Apps: SwiftUI" src="https://img.shields.io/badge/apps-SwiftUI-black">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

**Vow helps Solana teams prepare transactions on a Mac and approve them on an offline iPad.**
The Mac captures transaction requests, inspects their instructions and exports a
`.vow` review file. Each signer opens it on their iPad, chooses a signing profile,
reviews the request and returns an approval. Portable verification runs in Rust;
SwiftUI supplies the native apps and hardware adapters.

[Website](https://vow.scarce.sh) · [Design](docs/DESIGN.md) ·
[Security](docs/SECURITY.md) · [Implementation plan](plan.md)

> [!WARNING]
> **Experimental and unaudited. Do not use Vow to secure real funds.**
> The apps produce prototype approval evidence, not executable Squads votes.
> Replay currently uses synthetic state. Production enforcement, authenticated
> chain state, recovery and independent security review remain unfinished.

## 🧭 What works

| Area | What it does | Status |
| --- | --- | --- |
| 🖥️ **Prepare** | The Mac menu bar simulates clipboard transactions in Surfnet; the browser captures wallet requests. | Generic legacy/v0 clipboard simulation; browser preview remains limited |
| 📦 **Transfer** | `.vow` files carry bytes, review context and fixtures. Paired nearby devices, USB storage and AirDrop can transport them. | Implemented; physical nearby acceptance ongoing |
| 🔎 **Review** | Rust decodes instructions, binds network context and checks imported evidence. Unknown instructions and unresolved lookup tables block signing. | Limited installed decoders |
| 🧪 **Reproduce** | Embedded Surfpool exports replay fixtures; LiteSVM independently reproduces supported results. | Synthetic state, not authenticated chain state |
| ✍️ **Approve** | Handwritten consent, YubiKey verification and iPad authentication protect a Secure Enclave P-256 approval. Ledger profiles use the device's Solana account. | Prototype signatures and verification; physical-device acceptance ongoing |
| 👤 **Profiles** | Personal signing identities are separate from organization membership and project quorum seats. | Local persistence; iCloud backup is not implemented |
| 👥 **Coordinate** | The Mac manages organizations, members, projects and reusable quorums. | Ceremony rehearsal; passport verification and pairing are unfinished |
| ⛓️ **Execute** | Bind approvals to an enforceable Squads transaction and required attestations. | Compatibility spike exists; production adapter and guard are unfinished |

The [design](docs/DESIGN.md) describes the current flows. The
[contracts](docs/CONTRACTS.md) define their formats, and
[architecture decisions](docs/adr/README.md) record the tradeoffs.

## 🚀 Quick start

Use an Apple Silicon Mac with Xcode 26 or later, an installed iPad simulator,
Rust stable and [`just`](https://github.com/casey/just). Xcode builds and links the
Rust libraries automatically.

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim
just mac-run
just ipad-run
```

To choose a particular iPad simulator:

```sh
python3 scripts/apple-app.py ipad run --simulator <simulator-uuid>
```

You can also open [`apps/apple/Vow.xcodeproj`](apps/apple/Vow.xcodeproj), select
the **Vow** scheme and choose My Mac or an iPad. For a physical device, configure
your development team in Signing & Capabilities. Intel Macs are not configured.

### Try an approval

1. On iPad, create a personal profile and select iPad + security key or Ledger.
2. On Mac, create an organization, add sample members and create a project quorum.
   Use **Requests → Sample request** for a rehearsal, or **Apps** to capture the
   built-in transaction preview and export a `.vow` file.
3. Transfer the file to iPad through Files, AirDrop or another file transport.
4. Select a profile, review the request, add handwritten consent and authorize.
5. Share the resulting approval, or export it again from History.

The iPad workspace requires an unavailable system network path. Connected local
networks and VPNs also lock it; Vow sends no internet probe. Simulator signing uses
explicit software fixtures and does not exercise physical security hardware.
To open the DEBUG simulator with those fixtures after `just ipad-run`:

```sh
xcrun simctl launch --terminate-running-process booted org.vow.prototype \
  --ui-test-onboarding=completed --ui-test-security-key=connected \
  --ui-test-network=offline
```

These flags simulate the hardware and network gate for a UI rehearsal.

## 📋 From clipboard to iPad

With Vow running on Mac, open its V icon in the menu bar. Select Devnet or Mainnet,
copy a serialized transaction as base64, hex or JSON, and choose **Prepare & Send
Clipboard**. Surfnet simulates the original bytes against RPC-derived accounts.
Multiple instructions, arbitrary programs, existing signatures and v0 lookup tables
are accepted independently of Vow's signing decoders. Failed runtime results are
included too. No transaction is submitted to the public network.

On iPad, open **Settings → Receive from Mac**, or use that button on the network-lock
screen. Enable Wi-Fi and Bluetooth and grant Local Network access. Compare the
pairing code on both devices once; later transfers discover the paired iPad
automatically while its receiver is open. Return to Vow and disconnect from the
network before reviewing. Pairing authorizes file delivery, not signing.

For a transfer with radios off, use **Save…** or drag the file onto a USB drive,
then open it through Files on iPad. After import, remove the drive and connect your
YubiKey. AirDrop and Finder export remain available too.

Generic clipboard bundles contain a Mac simulation and state fixtures. Both apps
can reproduce them in a fresh offline Surfpool SDK fork and inspect instruction
profiles, parsed account-state diffs, raw bytes and logs. Fixtures remain unverified
chain context; simulation never grants approval authority. Preparation has an 8 MB
file limit.

## 🔑 Signing profiles

**iPad + YubiKey.** The iPad key is P-256 and stays in Secure Enclave. New profiles
use direct USB signing. Compatible FIDO2 keys use their existing PIN; supported
PIV keys can be prepared on the iPad without replacing existing credentials or
changing the PIN. A metadata-confirmed factory smart-card PIN is handled
without a PIN field. A factory PIN is public and is not a separate knowledge
factor. Existing native Apple registrations retain their original method.

New smart-card setup and recovery secrets are stored in this iPad's private
Keychain. A recovery export is still needed. Secure Enclave keys cannot be
restored onto another iPad, and resetting Vow deletes its local signing and setup
records. See the [setup and recovery boundaries](docs/DESIGN.md#on-device-piv-setup-2026-11-11).

**Ledger.** iPad connects to Nano X, Nano Gen5 and Flex over Bluetooth. The Mac uses
the Rust Ledger adapter. Vow verifies the account and returned signature; it never
asks for the Ledger PIN. Current Ledger approvals remain off-chain evidence.

A profile belongs to its user. Organization membership is enrolled once through a
ceremony coordinated on Mac. A project references a reusable quorum of those
members, and a profile must be explicitly registered for its seat. Creating a
profile alone does not grant multisig membership. Handwriting records consent;
Vow does not authenticate the pen or match the signature to a person's identity.

## 📦 Review files

A `.vow` file is a flattened native Apple `FileWrapper` document, shown as one
file with a document icon and a measurable size in Finder and Files. It contains the original request, transaction bytes and optional
simulation and account snapshots, with a manifest that checks each member.
It carries no signing private keys. Older directory packages and JSON `.vow` files remain readable.
Its exact schemas and limits are in the [contracts](docs/CONTRACTS.md).

The iPad also imports binary, hex, base64 and JSON transaction dumps. A bare Solana
transaction does not identify its network or when its blockhash was observed;
Vow labels those missing facts. A countdown is an estimate, not proof that a
transaction is still valid. Supplied labels, IDLs and fixtures are untrusted input.

## ⌨️ Command line

The Mac app carries a `vow` command at `Vow.app/Contents/Helpers/vow`. It
prepares review files; it holds no keys and cannot sign or submit.

```sh
vow new <bytes> --chain devnet            # writes ./Vow-<digest>.vow
vow new tx.json -c mainnet --simulate     # adds a local-fork simulation (reads the public RPC)
vow mcp                                   # the same function as an MCP tool, over stdio
```

`<bytes>` is hex, base64 or a JSON dump, a file holding one (binary too), or
`-` for standard input. The network is always stated, never inferred. The
output is a JSON `.vow` file, which the apps read like their own documents.
Existing files are not replaced without `--force`.

## 🗂️ Repository layout

```text
vow/
├── apps/
│   ├── apple/          Shared SwiftUI app, platform adapters and UI tests
│   └── web/            Public website at vow.scarce.sh
├── crates/
│   ├── core/           Formats, decoding, identities, policy and signature verification
│   ├── ffi/            C ABI shared by the Apple apps
│   ├── cli/            `vow` command line and MCP server, bundled in the Mac app
│   ├── replay/         Offline replay verification
│   ├── runtime/        Shared offline Surfpool execution and state diffs
│   ├── simulation/     Mac capture, fixture export and shared snapshot profiling
│   └── ledger/         Desktop Ledger adapter
├── spikes/             P-256 and bridge compatibility experiments
├── scripts/            Build, hardware-policy and asset tools
└── docs/               Design, security, contracts, research and decisions
```

## 🛠️ Development

```sh
just crypto-test                  # signatures, enrollment, replay protection and FFI
just crypto-lint                  # Rust Clippy
just crypto-fmt                   # Rust formatting
scripts/test-piv-pin-policy.sh     # PIN selection and interrupted key-setup checks
just mac-test                     # native Mac UI tests
just ipad-test                    # native iPad UI tests
```

[Cryptography verification](docs/CRYPTO_TESTING.md) describes the test coverage.
Native test results and screenshots are written under `.local/`.

For the website, install its dependencies with `pnpm --dir apps/web install`,
then run `just web-dev`. See [`apps/web/README.md`](apps/web/README.md) for the web
build and deployment workflow.

## License

MIT. See [LICENSE](LICENSE).
