#!/usr/bin/env python3
"""Check the LFS 12.4 build host without changing system files."""
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

os.environ['LC_ALL'] = 'C'
os.environ['PATH'] = '/usr/bin:/bin'
errors = []


def fail(message):
    errors.append(message)
    print(f'FAIL {message}')


def version_tuple(value):
    return tuple(int(part) for part in value.split('.'))


requirements = {
    'bash': ('3.2', None), 'ld': ('2.13.1', '2.45'),
    'bison': ('2.7', None), 'sort': ('8.1', None),
    'diff': ('2.8.1', None), 'find': ('4.2.31', None),
    'gawk': ('4.0.1', None), 'gcc': ('5.4', '15.2.0'),
    'g++': ('5.4', '15.2.0'), 'grep': ('2.5.1', None),
    'gzip': ('1.3.12', None), 'm4': ('1.4.10', None),
    'make': ('4.0', None), 'patch': ('2.5.4', None),
    'perl': ('5.8.8', None), 'python3': ('3.4', None),
    'sed': ('4.1.5', None), 'tar': ('1.22', None),
    'makeinfo': ('5.0', None), 'xz': ('5.0.0', None),
}
for command, (minimum, maximum) in requirements.items():
    if not shutil.which(command):
        fail(f'{command}: missing')
        continue
    result = subprocess.run([command, '--version'], capture_output=True, text=True)
    match = re.search(r'\d+\.\d+(?:\.\d+)*', result.stdout + result.stderr)
    if result.returncode or not match:
        fail(f'{command}: version could not be determined')
        continue
    version = match.group()
    # Normalize trailing zero components before comparison.
    current = version_tuple(version) + (0,) * (4 - len(version_tuple(version)))
    low = version_tuple(minimum) + (0,) * (4 - len(version_tuple(minimum)))
    high = (version_tuple(maximum) + (0,) * (4 - len(version_tuple(maximum)))) if maximum else None
    if current < low or (high and current > high):
        fail(f'{command}: {version}, supported {minimum} .. {maximum or "newer"}')
    else:
        print(f'OK   {command}: {version}')

for alias, expected in [('sh', 'bash'), ('awk', 'GNU Awk'), ('yacc', 'bison')]:
    try:
        output = subprocess.run([alias, '--version'], capture_output=True, text=True)
        if output.returncode or expected.lower() not in (output.stdout + output.stderr).lower():
            fail(f'{alias}: must use {expected}')
    except FileNotFoundError:
        fail(f'{alias}: missing')

if platform.machine() != 'x86_64':
    fail('only x86_64 is currently supported')
kernel = re.match(r'(\d+)\.(\d+)', platform.release())
if not kernel or tuple(map(int, kernel.groups())) < (5, 4):
    fail('Linux kernel >= 5.4 required')

with tempfile.TemporaryDirectory(prefix='lightnix-check-') as directory:
    for compiler, suffix, source in [
        ('gcc', 'c', '#include <stdio.h>\nint main(void) { puts("ok"); return 0; }\n'),
        ('g++', 'cc', '#include <iostream>\nint main() { std::cout << "ok"; }\n'),
    ]:
        if not shutil.which(compiler):
            continue
        path = Path(directory) / f'check.{suffix}'
        binary = Path(directory) / f'check-{compiler}'
        path.write_text(source)
        result = subprocess.run([compiler, str(path), '-o', str(binary)], capture_output=True, text=True)
        if result.returncode:
            fail(f'{compiler}: compilation failed: {result.stderr.strip()}')
        elif subprocess.run([str(binary)], capture_output=True).returncode:
            fail(f'{compiler}: compiled program failed')
        else:
            print(f'OK   {compiler}: compile and run')

free = shutil.disk_usage('.').free // (1024 ** 3)
print(f'INFO available disk space: {free} GiB (plan for at least 30 GiB)')
if errors:
    print(f'\nHost check failed: {len(errors)} issue(s). See container/Dockerfile.')
    raise SystemExit(1)
print('\nHost check passed.')
