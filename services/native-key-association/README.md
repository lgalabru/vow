# Native Apple security-key association

The current RP is `vow.scarce.sh`, selected on 2026-11-10. The site serves
`https://vow.scarce.sh/.well-known/apple-app-site-association` as HTTP 200,
`application/json`, without redirects. Apple’s association CDN also returns this
file successfully. The development app identifier is `4HY7TSGF6M.org.vow.prototype`.

The hosting source is `apps/web/public/.well-known/apple-app-site-association`.
`apps/web/next.config.mjs` supplies the JSON header. Keep both in future Vercel
builds. The site project is `vow` under the `ludo-galabru` team; Cloudflare serves
its DNS. Website CI verifies this endpoint against the app identifier.

To recheck and enable the same domain from the repository root:

```sh
python3 scripts/configure-native-key-domain.py vow.scarce.sh
python3 scripts/configure-native-key-domain.py vow.scarce.sh --enable
```

The checker verifies the HTTPS association before setting the RP and entitlement
path in `apps/apple/Config/NativeSecurityKey.xcconfig`. Rust, Info.plist and signed
Associated Domains must match. No imported transaction can select the RP.
An empty configuration disables native signing. If a local resolver still caches
an old negative DNS result, resolve the hostname through public DNS and use that
address only for the connection; retain HTTPS hostname and certificate validation.
Do not skip TLS verification.

Build with automatic provisioning updates and install while the iPad can retrieve
its association. The current physical build passed compilation and entitlement
checks for `webcredentials:vow.scarce.sh`. The previous prototype used `axel.md`.
Existing credentials are bound to their RP and cannot silently migrate. No PIN
reset, credential deletion or automatic signing-identity rotation is performed.

Xcode wireless delivery uses a local-network tunnel. The iPad must disconnect
networking after delivery before signing. The strict offline gate stays in place.
Then test registration and an assertion using the external USB key, the owner's
usual FIDO2 PIN and touch, followed by iPad biometric authentication. System PIN
entry never passes through Vow. Initial association retrieval and offline reuse
are separate acceptance tests. Hardware PIN/touch, offline operation, interruption
and recovery remain unverified until performed on the physical iPad.
