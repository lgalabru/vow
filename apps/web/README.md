# Vow website

Public product preview at `https://vow.scarce.sh`, built with Next.js, React,
Tailwind, Base UI and the Solana design system. System fonts, local assets,
no analytics, wallet connection or account collection.

```sh
pnpm --dir apps/web install --frozen-lockfile
just web-dev
just web-check
just web-build
pnpm --dir apps/web exec playwright install chromium
just web-test
```

The interactive iPad illustration uses fictional sample data and no signing keys.
Keep availability, supported features and security claims consistent with the native
prototype. The FAQ describes production limitations. There is no download or signup
endpoint until a public release exists.

## Deployment

Vercel project `vow` belongs to `ludogalabru-1362s-projects`, displayed as
`ludo-galabru`. Project root: `apps/web`. Framework: Next.js. Node: 24.x.
Install: `pnpm install --frozen-lockfile`. Build: `pnpm run check && pnpm run build`.

GitHub Actions runs formatting, TypeScript, ESLint, production build and Chromium
checks at desktop and mobile sizes. The Vercel GitHub integration deploys `main`
to production and creates branch previews. No Vercel access token belongs in this
repository or its workflows.

Custom hostname: `vow.scarce.sh`. The external DNS provider is Gandi. Set the
`vow` CNAME to `44166953089c7417.vercel-dns-017.com.` and verify with:

```sh
vercel domains verify vow.scarce.sh --scope ludogalabru-1362s-projects
```

## Apple security-key association

`public/.well-known/apple-app-site-association` is served as HTTP 200 JSON,
without a redirect, and includes `4HY7TSGF6M.org.vow.prototype`.
The header is defined in `next.config.mjs`; Playwright checks both the response
and its exact app identifier. Never remove this file from later deployments.

The installed iPad build currently uses `axel.md`. Hosting this file on the new
site does not migrate existing credentials or change the iPad's pinned RP.
Enable `vow.scarce.sh` only after DNS/HTTPS and the association have been verified,
and treat a changed RP as deliberate re-enrollment. See
`services/native-key-association/README.md` at the repository root.
