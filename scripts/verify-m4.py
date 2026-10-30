#!/usr/bin/env python3
"""Inspect target M4 and test macro expansion through the target loader."""
import os
from pathlib import Path
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(run):
    root = Path('/work/build/rootfs')
    require(Path(os.environ['LFS']) == root, 'unexpected sysroot')
    run = run.resolve()
    require(run.parent == Path('/work/build/work') and run.name.startswith('m4-bootstrap.'),
            'unexpected verification directory')
    binary = root / 'usr/bin/m4'
    require(binary.is_file() and binary.read_bytes() == (run / 'objects/src/m4').read_bytes(),
            'installed M4 differs from build output')
    readelf = str(root / 'tools/bin' / (os.environ['LFS_TGT'] + '-readelf'))
    headers = subprocess.check_output([readelf, '-h', str(binary)], text=True)
    require(re.search(r'Class:.*ELF64', headers) and re.search(r'Machine:.*X86-64', headers), 'wrong ELF architecture')
    program_headers = subprocess.check_output([readelf, '-l', str(binary)], text=True)
    interpreter, = re.findall(r'Requesting program interpreter: ([^\]]+)', program_headers)
    require(interpreter == '/lib64/ld-linux-x86-64.so.2', f'wrong interpreter: {interpreter}')
    loader = root / interpreter.lstrip('/')
    require(loader.is_file() and loader.resolve().is_relative_to(root), 'target loader missing or outside rootfs')
    dynamic = subprocess.check_output([readelf, '-d', str(binary)], text=True)
    require('Shared library: [libc.so.6]' in dynamic, 'libc dependency missing')
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic, 'unexpected runtime search path')
    environment = {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'}
    command = [str(loader), '--inhibit-cache', '--library-path', str(root / 'usr/lib')]
    libraries = subprocess.check_output(command + ['--list', str(binary)], text=True, env=environment)
    (run / 'libraries.log').write_text(libraries)
    require('libc.so.6 =>' in libraries, 'loader did not resolve libc')
    for path in re.findall(r'=> (/\S+)', libraries):
        require(Path(path).resolve().is_relative_to(root), f'host library resolved: {path}')
    version = (run / 'm4-version').read_text().strip()
    output = subprocess.check_output(command + [str(binary), '--version'], text=True, env=environment)
    require(output.splitlines()[0] == f'm4 (GNU M4) {version}', 'M4 version mismatch')
    macro = "define(`distro', `Lightnix')dnl\ndistro\n"
    result = subprocess.run(command + [str(binary)], input=macro, capture_output=True,
                            text=True, env=environment, check=True)
    require(result.stdout == 'Lightnix\n', f'macro expansion failed: {result.stdout!r}')
    print(f'OK M4 {version}: ELF64/x86_64, installed binary, target loader and libc')
    print('OK target-loader execution: --version and macro expansion')
    print(f'Library resolution: {run / "libraries.log"}')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
