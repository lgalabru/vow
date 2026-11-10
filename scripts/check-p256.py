#!/usr/bin/env python3
"""Build pinned bridge code and test Apple signatures locally. Never broadcasts."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REV = "9d49672f837f0615f321927975375694fb032e56"
URL = "https://github.com/0xRigel-squads/external-signature-program"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=["--software-fixture", "--hardware-crypto-only", "--secure-enclave"])
# A positional starting with -- follows the standard '--' separator.
args = parser.parse_args()
env = os.environ.copy()
env["RUSTUP_TOOLCHAIN"] = "stable"

def run(*command, cwd=ROOT, capture=False):
    return subprocess.run(command, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

source = ROOT / ".local" / "external-signature-program"
if not source.exists():
    source.mkdir(parents=True)
    run("git", "init", str(source))
    run("git", "remote", "add", "origin", URL, cwd=source)
    run("git", "fetch", "--depth", "1", "origin", REV, cwd=source)
    run("git", "checkout", "--detach", "FETCH_HEAD", cwd=source)
if run("git", "rev-parse", "HEAD", cwd=source, capture=True).strip() != REV:
    raise SystemExit("Unexpected bridge revision; refusing to use it")
run("git", "diff", "--exit-code", "HEAD", "--", "src", "Cargo.toml", cwd=source)
shutil.copyfile(ROOT / "spikes/bridge-check/upstream-Cargo.lock", source / "Cargo.lock")
run("swift", "build", "-c", "release", "--package-path", "spikes/p256")
run("cargo", "build-sbf", "--arch", "v0", "--", "--locked", cwd=source)
env["VOW_KEY_MODE"] = args.mode
env["VOW_SWIFT_PROBE"] = str(ROOT / "spikes/p256/.build/release/vow-p256-probe")
env["VOW_BRIDGE_SO"] = str(source / "target/deploy/external_signature_program.so")
run("cargo", "test", "--locked", "--manifest-path", "spikes/bridge-check/Cargo.toml", "--", "--nocapture")
