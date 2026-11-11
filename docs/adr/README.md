# Architecture decisions

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-rust-core-and-apple-platform-adapters.md) | Share portable logic in Rust through a narrow C ABI | accepted |
| [0002](0002-organization-enrollment-and-project-quorums.md) | Enroll organization members once and reuse project quorums | accepted |
| [0003](0003-lock-the-ipad-until-offline.md) | Lock the iPad app until its network path is unavailable | accepted |
| [0004](0004-persist-device-identity-and-pin-a-piv-signing-key.md) | Persist device identity and pin a PIN-protected PIV signing key | superseded by 0005 |
| [0005](0005-prefer-discoverable-fido-credentials-and-never-change-pins.md) | Prefer discoverable FIDO credentials; never change a PIN in Vow | superseded by 0006 |
| [0006](0006-use-native-apple-external-security-keys.md) | Prefer Apple native external security keys when configured | superseded by 0008 |
| [0007](0007-display-external-account-member-address.md) | Display the ExternalAccount bridge member address with pending registration | accepted |
| [0008](0008-prefer-direct-usb-for-new-offline-enrollment.md) | Prefer direct USB for new offline enrollments and preserve existing methods | superseded by 0012 |
| [0009](0009-bind-signing-profiles-to-quorum-seats.md) | Bind signing profiles to quorum seats and separate Ledger proof schemes | accepted |
| [0010](0010-separate-personal-identities-and-share-native-design.md) | Separate personal identities from organization registration and share native design | accepted |
| [0011](0011-automatically-use-confirmed-factory-piv-pin.md) | Automatically use a metadata-confirmed factory PIV PIN | accepted |
| [0012](0012-provision-piv-on-ipad-without-native-enrollment.md) | Prepare direct PIV signing on iPad without new native enrollment | accepted |
