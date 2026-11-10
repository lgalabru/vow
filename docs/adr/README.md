# Architecture decisions

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-rust-core-and-apple-platform-adapters.md) | Share portable logic in Rust through a narrow C ABI | accepted |
| [0002](0002-organization-enrollment-and-project-quorums.md) | Enroll organization members once and reuse project quorums | accepted |
| [0003](0003-lock-the-ipad-until-offline.md) | Lock the iPad app until its network path is unavailable | accepted |
| [0004](0004-persist-device-identity-and-pin-a-piv-signing-key.md) | Persist device identity and pin a PIN-protected PIV signing key | superseded by 0005 |
| [0005](0005-prefer-discoverable-fido-credentials-and-never-change-pins.md) | Prefer discoverable FIDO credentials; never change a PIN in Vow | superseded by 0006 |
| [0006](0006-use-native-apple-external-security-keys.md) | Prefer Apple native external security keys when configured | accepted |
