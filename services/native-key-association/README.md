# Native Apple security-key association

The owner selected `axel.md` on 2026-11-10. The association file is deployed and verified. Serve the provided
`.well-known/apple-app-site-association` JSON at `https://axel.md/.well-known/apple-app-site-association` with HTTP 200 and content
type `application/json`, without redirects. The current development app identifier
is `4HY7TSGF6M.org.vow.prototype`. Change the file and checker argument deliberately
if the signing team or bundle identifier changes.

After the file is live, run from the repository root:

```sh
python3 scripts/configure-native-key-domain.py axel.md
python3 scripts/configure-native-key-domain.py axel.md --enable
```

The second command verifies the association before setting the relying-party
hostname and Associated Domains entitlement in the Apple build configuration.
The same value is compiled into Rust and expanded into the app's Info.plist and
entitlements. No hostname is supplied by an imported transaction or runtime file.
The checked configuration enables `axel.md`. An empty configuration disables native signing.

Build with automatic provisioning updates so Xcode can obtain a profile supporting
Associated Domains. Install while the iPad can retrieve its domain association.
Then disconnect networking and test registration and subsequent assertions with
the external USB key. Initial association verification and strictly offline reuse
are separate hardware acceptance tests, not assumed guarantees.

Xcode's wireless connection uses a local-network tunnel. Vow's offline gate stays
locked while that path is active. Wireless builds do not provide an exception to
the signing policy; disconnect the network after delivery and before signing.

The hosting source is `~/Coding/axel/web/public/.well-known/apple-app-site-association`.
`web/next.config.mjs` supplies the JSON content type. These source changes must remain
in future Axel deployments. The initial deployment used the current production
source tree plus only these two changes.

The activated iPad build was installed wirelessly on 2026-11-10. Its signed
`webcredentials:axel.md` entitlement and Info.plist RP match the Rust build. Apple
CDN returned the association as HTTP 200 JSON. Hardware PIN/touch and strictly
offline acceptance remain unverified.
