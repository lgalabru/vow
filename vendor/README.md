# Compatibility patches

`nix` 0.31.3 is the crates.io source under its original MIT license. Surfpool's
Solana client dependency reaches its socket module on iPadOS. Four platform
annotations now limit the macOS kernel-control API and its private string helper
to macOS, where libc defines `SYSPROTO_CONTROL` and `UTUN_OPT_IFNAME`.
No socket implementation or cryptographic code changed.
Remove this patch when the dependency includes the iPadOS platform fix.
