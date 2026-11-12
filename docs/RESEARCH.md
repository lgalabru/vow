# Platform research

Evidence checked 2026-11-09. Platform facts below are separate from proposed Vow
behavior. Hardware, entitlements and distribution paths still need device tests.

## Apple signing and device authentication

Apple documents Secure Enclave P-256 signing and key access controls. Vow cannot
assume an enclave-held Ed25519 key. Exact access-control flags and fallback behavior
must be tested rather than inferred from a successful biometric UI prompt.

Sources: [Secure Enclave key protection](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave),
[CryptoKit SecureEnclave.P256](https://developer.apple.com/documentation/cryptokit/secureenclave/p256).

The current iPad mini has Touch ID. Vow should describe its final authorization
step as device authentication, choosing the device's available modality.

Source: [iPad mini specifications](https://www.apple.com/ipad-mini/specs/).

## App identity and distribution

App Attest certifies an app-instance key through Apple. Current validation
documentation includes bundle-version fields and assertion counters. Availability
and version support must be checked explicitly. Offline generation after enrollment
is a feasibility gate, not a confirmed Vow capability. Enrollment needs an online
phase; no production design should silently skip required provenance evidence.

Sources: [App Attest validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server),
[assertion generation](https://developer.apple.com/documentation/devicecheck/dcappattestservice/generateassertion(_:clientdatahash:completionhandler:)),
[WWDC26 App Attest changes](https://developer.apple.com/videos/play/wwdc2026/201/).

Mac notarization checks software distribution artifacts; it is not an approval
signature produced during a Vow session. App Store review and code signing do not
prove transaction comprehension. Foundation publishing would establish a publisher
identity, subject to obtaining that organization's approval and signing setup.

Source: [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Solana and multisig integration

### Squads source follow-up, 2026-11-09

Reviewed `Squads-Protocol/v4` at
`af94153ff77a28b6effe46b9c94baaa93742b48c`. Its `Member` stores a Solana `Pubkey`
and permissions; `ProposalVote` requires `member: Signer` and records that member's
vote. No direct P-256/WebAuthn verifier was found in this revision. A PDA supplied
as a signer by an authorized CPI can satisfy that account model; an ordinary P-256
public key alone cannot.

A public External Signature Program implementation exists at
`0xRigel-squads/external-signature-program`, reviewed at
`9d49672f837f0615f321927975375694fb032e56`. It verifies P-256 WebAuthn payloads,
derives an account from the public key, and executes instructions with a PDA signer.
This is an existing bridge candidate for Vow, rather than evidence that Vow must
invent a new adapter. Its source owner differs from the Squads-Protocol organization;
the reviewed source was not matched to deployed bytecode or a particular audit.

Two integration constraints need experiments. The implemented signature scheme is
WebAuthn, not arbitrary raw P-256 messages, so a CryptoKit signing result is not a
drop-in replacement. The non-sessioned execution path binds a recent slot hash and
rejects a distance of 150 slots or more. A durable outer transaction nonce does not
remove that inner expiry. Human review and delayed offline submission may exceed
the window. Session keys exist but change the custody/authorization model.

Sources: [v4 member type](https://github.com/Squads-Protocol/v4/blob/af94153ff77a28b6effe46b9c94baaa93742b48c/programs/squads_multisig_program/src/state/multisig.rs#L253),
[v4 voting](https://github.com/Squads-Protocol/v4/blob/af94153ff77a28b6effe46b9c94baaa93742b48c/programs/squads_multisig_program/src/instructions/proposal_vote.rs#L12),
[external execution](https://github.com/0xRigel-squads/external-signature-program/blob/9d49672f837f0615f321927975375694fb032e56/src/instructions/execute_instructions.rs),
[WebAuthn verification](https://github.com/0xRigel-squads/external-signature-program/blob/9d49672f837f0615f321927975375694fb032e56/src/state/p256_webauthn/trait_impl.rs),
[nonce validity](https://github.com/0xRigel-squads/external-signature-program/blob/9d49672f837f0615f321927975375694fb032e56/src/utils/nonce.rs).

### General chain constraints

Solana verifies Ed25519 transaction signatures. Its P-256 precompile can verify
additional signatures, but precompiles cannot be invoked through CPI. An adapter
must validate the verification instruction's exact inputs and relation to its
action. A precompile by itself does not implement multisig membership or replay
protection. Integration with existing Squads is still an open feasibility question.

Sources: [Transaction pipeline](https://solana.com/docs/core/transactions/transaction-pipeline),
[precompiles](https://solana.com/docs/core/programs/precompiles),
[Squads accounts](https://docs.squads.so/main/development/reference/accounts).

### CryptoKit bridge compatibility experiment, 2026-11-09

The local [spike](../spikes/p256/README.md) passed the real bridge's account
initialization verifier in LiteSVM using a Mac Secure Enclave key, with software
fixtures as a separate explicit mode. Rust prepares WebAuthn-shaped payloads and
normalizes signatures to low-S; a small Swift adapter signs the requested message.
This demonstrates that a Vow-controlled hardware key can produce accepted bytes.
It does not establish a standards-compliant WebAuthn authenticator or hardware
origin evidence for that key.

Bare challenge signatures, missing user presence, wrong challenges and tampered
signatures were rejected. Missing user verification was accepted, consistent with
the disabled UV check in the reviewed bridge. Vow-controlled UP/UV flags are app
statements, not independent proof of a biometric event. Hardware mode in this run
used a crypto-only key access policy, deliberately without biometric prompts.
Physical iPad and biometric-policy tests, Squads voting and deployed-build matching
remain untested.

## External keys

Yubico recommends its Swift SDK for new work. Its repository lists USB-C transport,
PIV and FIDO2 functionality. This is a candidate, not proof that every YubiKey,
firmware version and iPad combination supports Vow's exact signing workflow. The
SDK also documents a sensitive-memory zeroization limitation; assess exposure of
PINs and authorization material in the integration.

Source: [YubiKit Swift](https://github.com/Yubico/yubikit-swift).

## Offline transport and management

AirDrop needs Bluetooth and Wi-Fi and may continue a transfer over the Internet.
The strict offline profile should use other transfer methods; local AirDrop mode
needs settings and traffic tests. A managed VPN controls routed traffic, not a
general guarantee of radio isolation. Apple exposes different VPN configuration
requirements by OS and management mechanism. Select and validate one deployment
profile instead of assuming all iPads enforce the same restrictions.

Sources: [AirDrop privacy](https://www.apple.com/legal/privacy/data/en/air-drop/),
[traffic filtering](https://support.apple.com/guide/deployment/filter-content-dep1129ff8d2/web),
[Always-on VPN declarative configuration](https://support.apple.com/guide/deployment/dep00e2509ce/web).

## Handwriting and Passport reuse

PencilKit captures drawing input; this is not a public pen-origin attestation API.
DTW and learned signature verification are candidate matchers. Evaluate on the
actual device, with repeated genuine samples and skilled imitations. Do not quote
benchmark accuracy as Vow's expected accuracy.

Sources: [PencilKit](https://developer.apple.com/documentation/pencilkit),
[DeepSign](https://arxiv.org/abs/2002.10119),
[image-based SigNet implementation](https://github.com/luizgh/sigver).

Local source review in `../passport`: `crates/document` defines document evidence
and chip challenges; `crates/drivers/emrtd` implements the passport reader;
`crates/pki` checks native document authentication; `crates/core/src/scan/flipper.rs`
streams reader events over USB serial. A reliable ceremony adapter still needs
complete evidence export, challenge control, reader-model testing and data erasure.
The current Passport verifier requires trusted roots, issuer, nonce and freshness;
its development setup is unsuitable for a production Vow identity certificate.

## Offline explanations, 2026-11-09

Apple's Foundation Models framework exposes an on-device language model that can
work without an Internet connection. Availability depends on supported hardware,
region/language, Apple Intelligence being enabled and model assets being ready.
A setup-time download is distinct from offline inference. The native prototype
now integrates this API, and generation has passed UI tests on Mac and iPad mini
simulator. Physical-device testing with networking disabled remains pending.

For Vow, Rust constructs a bounded set of already-decoded facts. A Swift
platform adapter requests an optional plain-language explanation from the
explicit on-device model. Generated text must not fill in unknown instructions,
change facts or become part of the signing authorization. Unavailable models leave
the deterministic review intact; no server fallback is permitted by offline mode.

Sources: [Foundation Models](https://developer.apple.com/foundation-models-framework/),
[availability checks](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models).

The default model guardrails rejected the sample financial transfer explanation.
The prototype uses Apple’s `permissiveContentTransformations` mode for bounded
source-fact transformation, with this choice disclosed in the explanation panel.
Default input/output filters do not screen this mode; the model may still refuse.
No free-form prompt or tools are exposed. Generated prose remains advisory.

## Network-path observation, 2026-11-09

Apple describes `NWPath.Status.satisfied` as a path available to establish
connections and send data; `unsatisfied` is unavailable, and
`requiresConnection` may activate when a new connection is established. Vow maps
these to red, green and amber respectively and sends no reachability request.
This is not evidence of a device-wide air gap.

Source: [Apple NWPath.Status](https://developer.apple.com/documentation/network/nwpath/status-swift.enum/satisfied).

## Mac dapp browser and proposal capture, 2026-11-09

Solana Wallet Standard discovers providers through registration events. Signing
requests carry serialized transaction bytes, not navigation URLs. The reviewed
`signTransaction` output explicitly supports modified signed transactions for
multisig and meta-transaction wallets. `signAndSendTransaction` returns a transaction
signature, not a pending proposal handle. Supported transaction-version types in
this revision include legacy, zero and one; Vow must advertise only implemented
and tested versions.

Sources: [registration implementation](https://github.com/wallet-standard/wallet-standard/blob/c49b56d60fbac2e68e0f3536707fa33030652f9e/packages/core/wallet/src/register.ts),
[signTransaction types](https://github.com/anza-xyz/wallet-standard/blob/c4d06f9f2668ebec3f2747c9fcf5e2382a2fc36f/packages/core/features/src/signTransaction.ts),
[signAndSendTransaction types](https://github.com/anza-xyz/wallet-standard/blob/c4d06f9f2668ebec3f2747c9fcf5e2382a2fc36f/packages/core/features/src/signAndSendTransaction.ts).

SquadsX exposes the vault PDA, wraps dapp instructions in a signed proposal-creation
transaction, then separates voting and execution. Its published app compatibility
list does not establish Vow compatibility. Squads v4 still resolves to our reviewed
`af94153ff77a28b6effe46b9c94baaa93742b48c` revision. It separates Initiate, Vote and
Execute permissions, making an Initiate-only Mac proposer a candidate to test.

Sources: [SquadsX flow](https://docs.squads.so/main/squadsx-beta-development/understanding-the-squadsx-extension-wallet),
[compatibility list](https://docs.squads.so/main/navigating-your-squad/squadsx/compatible-apps),
[member permissions](https://github.com/Squads-Protocol/v4/blob/af94153ff77a28b6effe46b9c94baaa93742b48c/programs/squads_multisig_program/src/state/multisig.rs).

Apple supplies `WKScriptMessageHandlerWithReply` for asynchronous page/native
messages and `WKScriptMessage.frameInfo.securityOrigin` for the frame origin.
`WKUserScript` supports document-start injection into a selected content world.
`WKWebExtensionController` can explicitly host extensions for associated web views
from macOS 15.4. These findings were also checked against the installed Xcode 27.2
macOS SDK headers. Extension hosting is not automatic inheritance of Safari wallets.

Sources: [native replies](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply),
[security origin](https://developer.apple.com/documentation/webkit/wkframeinfo/securityorigin),
[user scripts](https://developer.apple.com/documentation/webkit/wkuserscript),
[extension controller](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller).

Proposed Vow architecture and unproven compatibility gates are in
[RFD 0002](rfd/0002-mac-dapp-browser-and-proposal-capture.md). Browser capture does
not resolve the P-256 bridge's delayed-approval freshness constraint.

## Squads execution, client kits and replay, 2026-11-09

Pinned sources:

- [Squads v4](https://github.com/Squads-Protocol/v4/tree/af94153ff77a28b6effe46b9c94baaa93742b48c),
  `vault_transaction_create`, `proposal_vote`, `vault_transaction_execute`,
  `batch_execute`, `spending_limit_use` and configuration instructions.
- [multisig-kit](https://github.com/Squads-Protocol/multisig-kit/tree/453717df755d9cab0973eaefae80a0b2f7dd1417),
  version 0.1.1, Kit peer dependency 8.3. Its wrapping/decompilation and lookup
  resolution do not introduce P-256 membership or attestation enforcement.
- [public-v4-client](https://github.com/Squads-Protocol/public-v4-client/tree/02bbd7d45fa60b0d93cd0a8eefdc73c143cd5591),
  version 1.4.1. Preflight validators and account preparation inform the Rust design.
- [Surfpool](https://github.com/txtx/surfpool), local source revision
  `9be726da6456b58a3b39c099885c6c5904da4543`, SDK 1.7.0. Vow embeds that crate;
  the locally installed CLI is a different version and is not invoked by the app.
- [Payment Channels](https://github.com/solana-foundation/payment-channels/tree/3ffa4d6728ad88e4a9667a76ad9ccd68a302c696),
  program `CHNLxYvVA28MJP9PrFuDXccuoGXAx7jBacfLEkahyGsX`.
  Generated clients, program instruction handlers, account derivation and metadata
  publishing recipe were read. Open discriminator is 1; distribute is 7.
- [Program Metadata](https://github.com/solana-program/program-metadata/tree/2d000d543f683e8c5760641b2640b6ae25f27d92),
  program `ProgM6JCCvbYkfKqJYHePx4xxSUSqJp7rh8Lyv7nk7S`.
  Canonical `idl` seed is padded to 16 bytes; header is 96 bytes. The implemented
  parser accepts bounded direct JSON with supported compression, rejecting URL
  and external-account indirection. See the code for the exact pinned program ID.

Squads creator requires Initiate; voting requires a signer with Vote; execution
requires a signer with Execute and an approved proposal whose timelock has elapsed.
Already-approved stale proposals can execute. Vault execution resolves stored
message accounts and invokes its instructions with vault/ephemeral PDA signatures.
Precompiles cannot be embedded as inner CPI checks. Spending limits are a separate
transfer authorization path. These findings motivate [RFD 0003](rfd/0003-guard-and-reproduction.md).

Surfpool SDK defaults to an offline fork and supports snapshots. A null snapshot
entry is not a cryptographic absence proof. `surfnet_profileTransaction` explicitly
verifies signatures and returns a UUID. Executed profiles support pre-transaction
snapshot export by signature. `includeProgramAccounts` must be explicitly enabled
when collecting program dependencies. Vow currently reproduces a synthetic System
transfer with signature/blockhash checks disabled, using native builtins only.
The Cargo lock pins compatible LiteSVM/Agave versions across Mac and iOS.

Payment Channels open creates escrow, transfers deposit and commits distribution
shares, with a separately authorized Ed25519 voucher signer. The channel PDA uses
`channel`, payer, payee, mint, voucher signer, salt and open slot. Event authority
uses `event_authority`. Distribution uses settled/payout state; instruction bytes
alone cannot yield payouts. Full 32-recipient distributions require v0 and lookup
tables. Metadata publication is explicit and chain-specific; an IDL's presence
is not proof that a program's behavior is safe.

Payment Channels also imposes an action-specific lifetime: `open_slot` must be at
most 1,500 slots old and cannot be in the future. It is a channel PDA seed. A
long-running multisig ceremony can therefore invalidate an opening even after
refreshing the outer blockhash. Refreshing `open_slot` changes the channel address
and action and requires renewed approval. This is distinct from recent-blockhash
expiry and must be reviewed before selecting a delayed multisig workflow.

## USB-C YubiKey integration, 2026-11-10

Reviewed [YubiKit Swift 1.4.0](https://github.com/Yubico/yubikit-swift/tree/e19212f2efbca9af280e57542e669885de5acdc1).
`USBSmartCardConnection.availableDevices` enumerates matching CCID slots; sessions
require explicit close, and `waitUntilClosed` observes removal through CryptoTokenKit.
`Management.Session.getDeviceInfo` is a read-only metadata operation. The integration
uses no configuration writes, PIN attempts or private-key commands. Transitive
dependencies are pinned in the Xcode workspace's `Package.resolved`.

The current installed iPhoneOS 27.2 SDK is more specific than the generic online
configuration guides: `CryptoTokenKit.framework/Headers/TKSmartCard.h` states that
`defaultManager` always is accessible on iOS; `com.apple.security.smartcard` gates
access on macOS. Xcode removes this Mac entitlement from the iOS signature, and
manually adding it produces a provisioning-profile rejection. The iPad target
therefore uses normal development signing and no Mac smart-card entitlement.
Yubico's [USB configuration guide](https://yubico.github.io/yubikit-swift/documentation/yubikit/gettingstarted)
is useful for the transport API, but its cross-platform entitlement advice must be
read against the target SDK. Presence gating is not proof of an enrolled key or of
transaction-bound consent.

The user's physical iPad mini was paired, development-signed, installed and launched
from this workspace. Simulator tests cover absent/present gating and removal during
a pending authorization. Actual 5C NFC insertion and biometric signing still require
hands-on verification on that iPad.

## PIN-protected offline USB-C enrollment, 2026-11-10

The pinned YubiKit Swift 1.4.0 source exposes `PIVSession`, slot metadata, PIN retry
metadata, PIN verification, empty-slot key generation and P-256 signing over USB
smart-card transport. Slot policies can require a PIN and physical touch for every
signature. This supports an offline local registered-key challenge without an
AuthenticationServices relying-party setup. The implementation uses PIV slot 82,
not the device's FIDO2 PIN or passkeys.

Yubico's current firmware table places FIDO2-over-CCID support at firmware 5.8.
We cannot assume a 5C NFC with older firmware supports offline CTAP over USB CCID.
PIV is the selected path; actual firmware and physical touch still need testing.

Sources: [Yubico firmware overview](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-firmware-overview.html),
[Yubico PIV documentation](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-piv.html),
[YubiKit Swift 1.4.0](https://github.com/Yubico/yubikit-swift/tree/1.4.0),
[Apple Secure Enclave signing key restoration](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey).

## Discoverable FIDO credentials and installation identity, 2026-11-10

Yubico documents FIDO2 over USB CCID beginning with firmware 5.8. The pinned
YubiKit Swift 1.4.0 exposes a CTAP session over SmartCard, GetInfo, PIN tokens,
credential enumeration by RP hash, discoverable credential creation and assertion
signing. This permits a direct offline CTAP implementation on compatible keys.
The app queries capabilities and requires resident credentials and credential
management. It does not infer these from a model name alone.

We use `vow.invalid` as a reserved prototype namespace and a fixed opaque Vow user
handle. Only Vow-scoped credentials are enumerated after PIN verification. This
supports rediscovery of the same security-key credential without exposing a
storage location or asking for a management key. It is not full WebAuthn origin
validation, hardware attestation or an Apple app identity proof. Native Apple
security-key UI with an associated domain is a separate possible route for older
keys; it needs a controlled domain, deployment configuration and offline tests.

Apple documents that `identifierForVendor` can change after removal of all apps
from a vendor. Neither a public identifier nor a stable Keychain query can recreate
a missing Secure Enclave private key. We restore a device-bound reference when it
exists, but do not promise uninstall or device-migration recovery. The app's
Keychain access is scoped to its signing identity; publisher or bundle changes
need an explicit migration plan. This prototype has not verified reinstall recovery
on the physical iPad.

Sources: [Yubico FIDO specifics](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-fido.html),
[YubiKit Swift 1.4.0](https://github.com/Yubico/yubikit-swift/tree/1.4.0),
[Apple identifierForVendor](https://developer.apple.com/documentation/uikit/uidevice/identifierforvendor),
[Apple Secure Enclave protection](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave).

USB compatibility follow-up: YubiKit 1.4.0 `SmartCardInterface` converts SELECT
`fileNotFound` and `invalidInstruction` responses into `featureNotSupported`.
Checking only raw response status misses unavailable FIDO applets. Vow now limits
this fallback to session creation, before GetInfo or PIN operations. Registered
FIDO factors, parsing failures and transport/PIN errors never downgrade to PIV.
Simulator regression tests inject the SDK's actual normalized error and a parsing
failure through the same session-opening function. UI errors expose readable
instructions and a bounded support code, not opaque SDK exception text.


## Native security-key session ownership (2026-11-10)

The owner reported `AS10004` from Authorize while USB detection showed connected.
The old wrapper prefixed every NSError code with `AS` and attributed all failures
to association/key availability, discarding the actual domain and underlying
errors. The served association file, Apple CDN copy, signed entitlement and
provisioning capability were checked and matched `vow.scarce.sh` and the app ID.
That does not prove the iPad's cached association state or successful offline use.

The previous detector held a `USBSmartCardConnection` and Management session while
calling Apple's native security-key API. YubiKit opens `TKSmartCard.beginSession`
and keeps it until explicit close or removal. Apple's API documents that a second
smart-card session fails while another exists. This is a conflict risk, not a
confirmed explanation of the owner's numeric code.

Native mode now uses passive slot-name observation and fresh enumeration, without
opening a smart-card session. The exact enrolled credential and Rust proof checks
remain mandatory. Legacy direct CTAP/PIV mode keeps its existing transport. Error
messages retain bounded NSError domains/codes and underlying system failure text;
PINs, APDUs and challenges are not logged. Physical retry remains the acceptance
test; simulator fixtures cannot establish the hardware root cause.

- [Apple beginSession](https://developer.apple.com/documentation/cryptotokenkit/tksmartcard/beginsession(reply:))
- Local pinned YubiKit: `YubiKit/Connection/SmartCard/USBSmartCardConnection.swift`.

The diagnostic build then exposed the actual failure in the owner's screenshot:
`com.apple.AuthenticationServices.AuthorizationError/1004`, with the explicit
reason that the webcredentials association could not be verified for
`4HY7TSGF6M.org.vow.prototype` and `vow.scarce.sh`. This identifies association
verification as the observed blocker; it does not confirm the USB-session
hypothesis. The iPad was offline and the candidate was installed over USB. An
online association refresh followed by an offline assertion is the next test.

## Crypto regression verification (2026-11-10)

The pinned bridge compatibility check accepts a wrapped CryptoKit assertion and
rejects bare signatures, missing presence, wrong challenges and message tampering.
It accepts the missing-user-verification case. Vow rejects that case locally, but
local checks cannot enforce policy against direct program submission. The planned
on-chain policy boundary must cover user verification before treasury use. Test
commands and remaining hardware limits are in [CRYPTO_TESTING.md](CRYPTO_TESTING.md).

## solana-keychain Ledger backend (2026-11-10)

Read the clean local repository at `ed68ba3232c99fa3ed3b57344e0b6e496aa08777`.
`rust/src/ledger/mod.rs` implements desktop USB-HID through solana-remote-wallet,
with a serialized actor and exclusive claims. It verifies returned signatures over
exact message bytes before attaching them. Caller deadlines cannot interrupt the
underlying blocking HID read; the claim remains held until that operation returns.

The configurable default path is `m/44'/501'/0'`. Address confirmation defaults off
and automatic Solana-app opening defaults on; Vow should override both for verified
enrollment and passive discovery respectively. The `ledger` Cargo feature is
explicitly excluded from `all`. Use a macOS-only adapter and pin the dependency;
the existing HID backend is not an iPad implementation.

The transaction signer preserves message bytes and supports partial signatures.
The message signer wraps UTF-8 payloads in a Ledger off-chain envelope, with an
85-byte V0 one-signer header and all-zero application domain. It does not sign raw
Vow JSON. Tests pin Ledger app source at
`c855c1a0ea12e76406efbfd17203ecf419952e27`. That source conformance is not evidence
that every released Ledger Solana app supports the operation. Test actual versions.

Ledger's old `hw-transport-ios-ble` repository is archived. The current native
mobile Device Management Kit is a candidate for an iPad transport investigation.
Its current documentation labels it alpha and lists Bluetooth for iOS. The mobile
Solana signer documents address retrieval, transaction signing and off-chain message
signing. These API descriptions do not certify Vow's intended device/app matrix.
The resulting model, UX and proof boundaries are in
[RFD 0005](rfd/0005-signing-profiles-and-ledger.md).

Sources: [local backend](../../solana-keychain/rust/src/ledger/mod.rs),
[Ledger transport documentation](https://developers.ledger.com/docs/device-interaction/dmk-ts/integration/how_to/transports),
[archived Swift BLE transport](https://github.com/LedgerHQ/hw-transport-ios-ble).

## Ledger transport implementation update (2026-11-10)

The owner selected Nano X, Nano Gen5 and Flex. Published solana-keychain PR 358 at
`0b7bf8368ea5650e6870504c6c36ac2d1aad3bc8` is the macOS dependency. Its exclusive
claim remains process-wide while sessions are keyed by device path. Vow validates
its own enrollment/approval domains before entering the hardware adapter and tests
its mobile envelope against the pinned backend's serialization.

Apple documents USBDriverKit on M-series iPads. It is not the generic HID route
needed by this A-series iPad mini. The current Ledger native SDK documents Bluetooth
for iOS and is alpha. Vow's prototype uses a thin CoreBluetooth adapter and bounded
Rust framing/APDU validation instead. Ledger's published identifiers list normal
Nano X `0004` and Nano Gen5 `8004` services; Gen5's alternate `9004` is documented
for early bootloader modes, which are excluded from signing discovery.

Protocol references: [Ledger identifiers](https://developers.ledger.com/docs/device-interaction/dmk-ts/references/identifiers),
[Apple USBDriverKit](https://developer.apple.com/documentation/usbdriverkit),
[Ledger APDU framing reference](https://github.com/LedgerHQ/hw-transport-ios-ble/blob/main/Sources/BleTransport/APDU.swift).
The archived framing source was read as a protocol reference, not added as a package.

2026-11-10 physical feedback: the owner's connected device is a Flex. Add its
normal `13d63400-2c97-3004-0000-4c6564676572` BLE service to discovery, alongside
Nano X and Nano Gen5. Retrieve already-connected matching peripherals before
scanning, and display scanning progress. Service/name matching remains a hint,
not an authenticated device identity.

## Native security-key domain association recheck (2026-11-11)

The installed-development entitlement is `webcredentials:vow.scarce.sh`; signed
application ID is `4HY7TSGF6M.org.vow.prototype`. The origin AASA at
`https://vow.scarce.sh/.well-known/apple-app-site-association` returns HTTP 200,
JSON and that exact webcredentials app ID. Apple's correct CDN endpoint,
`https://app-site-association.cdn-apple.com/a/v1/vow.scarce.sh`, also returns HTTP 200
and the matching file. The unversioned `/a/<domain>` diagnostic URL returns 404
and must not be mistaken for an association failure. Neither a CDN success nor an
origin check proves the device's cached state. The owner sees AS1004 specifically
naming a webcredentials association failure after offline development updates.

Apple documents association retrieval during installation through its CDN, delayed
CDN updates and periodic device refresh. An online installation is required for the
next physical test; a successful origin check alone cannot establish that iPadOS
accepted the association. Do not rotate the key, change the RP or reset a PIN to
address this error. Developer alternate-mode fetching exists but requires device
opt-in and changes certificate trust behavior; it is not enabled as a default for
this signing application.

Sources: [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains),
[Associated Domains entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains).

## Apple nearby file transport (2026-11-11)

[Handoff](https://developer.apple.com/documentation/foundation/implementing-handoff-in-your-app)
can resume an activity and establish continuation streams. It requires a user
continuation action. [Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity)
provides nearby discovery, messaging and file transfer across app instances. Vow
uses it for explicit foreground receiving, with application pairing and encryption
in addition to required MCSession encryption. It does not infer trusted identity
from a peer's display name.

[External storage on iPad](https://support.apple.com/en-lb/guide/ipad/ipad75b7b23f/ipados)
is available through Files and supported document pickers. A USB-C drive formatted
as exFAT or APFS can transport the same `.vow` while Wi-Fi and Bluetooth remain off.
