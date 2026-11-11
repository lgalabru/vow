# Compatibility spike only; no network transaction is submitted.
fmt:
    cargo +stable fmt --all -- --check
    cargo +stable fmt --manifest-path spikes/bridge-check/Cargo.toml -- --check

lint:
    cargo +stable clippy --locked --workspace --all-targets -- -D warnings
    cargo +stable clippy --locked --manifest-path spikes/bridge-check/Cargo.toml --all-targets -- -D warnings
    swift build -c release --package-path spikes/p256 -Xswiftc -warnings-as-errors

test:
    cargo +stable test --locked --workspace
    python3 scripts/check-p256.py -- --software-fixture

# Creates an ephemeral hardware key without biometric policy. Tests crypto only.
test-hardware:
    python3 scripts/check-p256.py -- --hardware-crypto-only

# Interactive diagnostic; requires OS authentication. Not run by CI/default tests.
test-biometric:
    python3 scripts/check-p256.py -- --secure-enclave

# Native app prototypes, Apple Silicon. Rust is built automatically by Xcode.
mac-build:
    python3 scripts/apple-app.py mac build

mac-run:
    python3 scripts/apple-app.py mac run

mac-test:
    python3 scripts/apple-app.py mac test

ipad-build:
    python3 scripts/apple-app.py ipad build

ipad-run:
    python3 scripts/apple-app.py ipad run

ipad-test:
    python3 scripts/apple-app.py ipad test

core-test:
    cargo +stable test --locked --workspace

core-lint:
    cargo +stable clippy --locked --workspace --all-targets -- -D warnings

# Public website. Vercel's project root is apps/web.
web-dev:
    pnpm --dir apps/web dev

web-check:
    pnpm --dir apps/web check

web-build:
    pnpm --dir apps/web build

web-test:
    pnpm --dir apps/web test

# Portable signature verification, enrollment, replay protection and C ABI tests.
crypto-test:
    cargo +stable test --locked -p vow-core -p vow-ffi -p vow-ledger --lib

crypto-lint:
    cargo +stable clippy --locked -p vow-core -p vow-ffi -p vow-ledger --all-targets -- -D warnings

crypto-fmt:
    cargo +stable fmt --all -- --check

# Exact envelope conformance against the PR-pinned desktop Ledger backend; no hardware I/O.
ledger-test:
    cargo +stable test --locked -p vow-ledger --lib
