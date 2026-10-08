#!/usr/bin/env python3
"""Run the native Swift Testing target, including an isolated local HTTP fixture."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite')
    parser.add_argument('--device', default=os.environ.get('HUB_TEST_DEVICE'))
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    derived = Path(os.environ.get('HUB_TEST_DERIVED_DATA', '/tmp/hub-ball-architecture-build'))
    if not args.device:
        devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
        candidates = [item for group in devices['devices'].values() for item in group]
        args.device = next((item['udid'] for item in candidates if item['state'] == 'Booted'), candidates[0]['udid'])
    destination = f'platform=iOS Simulator,id={args.device}'
    with tempfile.TemporaryDirectory(prefix='hub-ball-native-tests-') as scratch:
        scratch = Path(scratch)
        def run(command: list[str], label: str) -> None:
            log = derived / f'{label}.log'
            derived.mkdir(parents=True, exist_ok=True)
            print(f'{label}: {log}', flush=True)
            with log.open('w') as output:
                result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
            if result.returncode:
                print('\n'.join(log.read_text().splitlines()[-100:]))
                raise SystemExit(result.returncode)
        if not args.skip_build:
            run(['xcodebuild', '-project', 'ios/Hub Ball/Hub Ball.xcodeproj', '-scheme', 'Hub Ball',
                 '-destination', destination, '-derivedDataPath', str(derived),
                 'CODE_SIGNING_ALLOWED=NO', 'build-for-testing'], 'test-build')
        ready = scratch / 'port'
        server = subprocess.Popen(['python3', str(root / 'scripts/test_http_cache_server.py'), str(ready)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if ready.exists() and ready.stat().st_size: break
                if server.poll() is not None: raise RuntimeError('HTTP fixture exited before startup')
                time.sleep(0.05)
            origin = f'http://localhost:{ready.read_text().strip()}'
            products = derived / 'Build/Products'
            test_run = max(products.glob('*.xctestrun'), key=lambda path: path.stat().st_mtime)
            settings = plistlib.loads(test_run.read_bytes())
            for configuration in settings['TestConfigurations']:
                for target in configuration['TestTargets']:
                    target.setdefault('EnvironmentVariables', {}).update({
                        'HUB_UNIT_TESTS': '1', 'HUB_HTTP_CACHE_FIXTURE_ORIGIN': origin,
                    })
                    target.setdefault('TestHostEnvironmentVariables', {}).update({
                        'HUB_UNIT_TESTS': '1', 'HUB_HTTP_CACHE_FIXTURE_ORIGIN': origin,
                    })
            # __TESTROOT__ in the generated file is relative to its own location.
            temporary_run = products / f'audit-{os.getpid()}.xctestrun'
            temporary_run.write_bytes(plistlib.dumps(settings))
            try:
                command = ['xcodebuild', 'test-without-building', '-xctestrun', str(temporary_run),
                           '-destination', destination, '-parallel-testing-enabled', 'NO']
                if args.suite: command.append(f'-only-testing:HubBallTests/{args.suite}')
                run(command, 'test-results')
                if 'Test run with 0 tests' in (derived / 'test-results.log').read_text():
                    raise SystemExit('Native test selection executed zero tests; verification failed.')
                for line in (derived / 'test-results.log').read_text().splitlines():
                    if 'Test run with' in line or 'TEST SUCCEEDED' in line or 'passed' in line:
                        print(line)
            finally:
                temporary_run.unlink(missing_ok=True)
        finally:
            server.terminate()
            server.wait(timeout=5)


if __name__ == '__main__':
    main()
