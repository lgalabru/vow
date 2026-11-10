#!/usr/bin/env python3
"""Build, run, or UI-test Vow's native local prototypes."""
import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('platform', choices=['mac', 'ipad'])
parser.add_argument('action', choices=['build', 'run', 'test'])
parser.add_argument('--simulator', help='An installed iPad simulator UUID')
args = parser.parse_args()

def run(*command, capture=False):
    return subprocess.run(command, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

platform = args.platform
build = ROOT / '.local' / ('build-mac' if platform == 'mac' else 'build-ipad')
if platform == 'ipad':
    inventory = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json', capture=True))
    choices = []
    for runtime, devices in inventory['devices'].items():
        version = tuple(map(int, re.findall(r'\d+', runtime.split('SimRuntime.')[-1])))
        for device in devices:
            if device.get('isAvailable') and 'iPad' in device['name']:
                choices.append((version, 'mini' in device['name'], device))
    if not choices:
        raise SystemExit('Install an iPad simulator runtime in Xcode first.')
    if args.simulator:
        device = next((d for _, _, d in choices if d['udid'] == args.simulator), None)
        if device is None:
            raise SystemExit('The selected simulator is not an available iPad.')
    else:
        device = sorted(choices, key=lambda x: (x[0], x[1]))[-1][2]
    identifier = device['udid']
    sdk = 'iphonesimulator'
    destination = 'platform=iOS Simulator,id=' + identifier
    signing = ['CODE_SIGNING_ALLOWED=NO']
else:
    sdk = 'macosx'
    destination = 'platform=macOS,arch=arm64'
    signing = ['CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES']

command = ['xcodebuild', '-project', 'apps/apple/Vow.xcodeproj', '-scheme', 'Vow',
           '-configuration', 'Debug', '-sdk', sdk, '-destination', destination,
           '-derivedDataPath', str(build), *signing]
if args.action == 'test':
    result = ROOT / '.local' / (platform + '-tests-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.xcresult')
    command += ['-resultBundlePath', str(result), 'test']
else:
    command += ['build']
run(*command)
if args.action == 'run':
    if platform == 'mac':
        run('open', str(build / 'Build/Products/Debug/Vow.app'))
    else:
        if device['state'] != 'Booted':
            run('xcrun', 'simctl', 'boot', identifier)
        run('xcrun', 'simctl', 'bootstatus', identifier, '-b')
        run('xcrun', 'simctl', 'install', identifier, str(build / 'Build/Products/Debug-iphonesimulator/Vow.app'))
        developer = Path(run('xcode-select', '-p', capture=True).strip())
        viewers = [developer / 'Applications/Simulator.app',
                   developer.parent / 'Applications/DeviceHub.app']
        viewer = next((p for p in viewers if p.exists()), None)
        if viewer is None:
            raise SystemExit('Vow is running. Open the device viewer from Xcode to interact with it.')
        run('open', '-a', str(viewer), '--args', '-CurrentDeviceUDID', identifier)
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', identifier, 'org.vow.prototype')
