#!/usr/bin/env python3
"""Coordinate native UI assertions with real simctl text-size changes; restore on exit."""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
device, name = sys.argv[1:]
if not name or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in name):
    raise SystemExit('Supply a simple unique run name')
subprocess.run([sys.executable, str(root/'scripts/prepare_large_text_ui_tests.py')], check=True)
original = subprocess.check_output(['xcrun','simctl','ui',device,'content_size'], text=True).strip()
result = root/f'dist/large-text-ui/{name}.xcresult'
if result.exists():
    raise SystemExit(f'Result already exists: {result}')
command = ['xcodebuild','-project',str(root/'dist/large-text-ui/Hub Ball.xcodeproj'),'-scheme','LargeTextLiveSize','-configuration','Debug','-destination',f'platform=iOS Simulator,id={device}','-derivedDataPath',str(root/'dist/large-text-ui/refined-derived'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','-only-testing:LargeTextUITests/LargeTextUITests/testLiveTextSizeRetainsState','CODE_SIGNING_ALLOWED=NO','test']
process = None
try:
    subprocess.run(['xcrun','simctl','ui',device,'content_size','large'], check=True)
    with (root/f'dist/large-text-ui/{name}.log').open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if line.startswith('HUBBALL_SIZE_REQUEST:'):
                size = line.strip().split(':',1)[1]
                if size not in ('large','accessibility-extra-extra-extra-large'):
                    raise RuntimeError(f'Unexpected category: {size}')
                subprocess.run(['xcrun','simctl','ui',device,'content_size',size], check=True)
                print(f'Changed simulator text size to {size}', flush=True)
        status = process.wait()
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    subprocess.run(['xcrun','simctl','ui',device,'content_size',original], check=True)
print(f'Result: {result}')
raise SystemExit(status)
