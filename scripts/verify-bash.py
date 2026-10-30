#!/usr/bin/env python3
"""Inspect target Bash and test builtins without host commands or startup files."""
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
    require(run.parent == Path('/work/build/work') and run.name.startswith('bash-bootstrap.'),
            'unexpected verification directory')
    binary = root / 'usr/bin/bash'
    require(binary.is_file() and binary.read_bytes() == (run / 'objects/bash').read_bytes(),
            'installed Bash differs from build output')
    shell = root / 'usr/bin/sh'
    require(shell.is_symlink() and shell.readlink() == Path('bash') and shell.resolve() == binary,
            'sh must be a relative link to Bash')
    require((root / 'bin/sh').resolve() == binary, '/bin/sh does not resolve to target Bash')
    readelf = str(root / 'tools/bin' / (os.environ['LFS_TGT'] + '-readelf'))
    header = subprocess.check_output([readelf, '-h', str(binary)], text=True)
    require(re.search(r'Class:.*ELF64', header) and re.search(r'Machine:.*X86-64', header), 'wrong ELF architecture')
    program = subprocess.check_output([readelf, '-l', str(binary)], text=True)
    interpreter, = re.findall(r'Requesting program interpreter: ([^\]]+)', program)
    require(interpreter == '/lib64/ld-linux-x86-64.so.2', 'wrong interpreter')
    loader = root / interpreter.lstrip('/')
    require(loader.is_file() and loader.resolve().is_relative_to(root), 'wrong loader location')
    dynamic = subprocess.check_output([readelf, '-d', str(binary)], text=True)
    require('Shared library: [libc.so.6]' in dynamic, 'libc dependency missing')
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic, 'unexpected runtime search path')
    environment = {'LC_ALL': 'C', 'PATH': '/nonexistent', 'HOME': str(run),
                   'TERMINFO': str(root / 'usr/share/terminfo')}
    command = [str(loader), '--inhibit-cache', '--library-path', str(root / 'usr/lib')]
    libraries = subprocess.check_output(command + ['--list', str(binary)], text=True, env=environment)
    (run / 'libraries.log').write_text(libraries)
    require('libncursesw.so' in libraries and 'libc.so.6 =>' in libraries, 'target Ncurses/libc dependency missing')
    for path in re.findall(r'=> (/\S+)', libraries):
        require(Path(path).resolve().is_relative_to(root), f'host library resolved: {path}')
    version = (run / 'source-version').read_text().strip()
    output = subprocess.check_output(command + [str(binary), '--noprofile', '--norc', '--version'],
                                     text=True, env=environment)
    require(re.search(r'GNU bash, version ' + re.escape(version) + r'(?:\.|\()', output), 'Bash version mismatch')
    script = r'''set -euo pipefail
name=Lightnix
items=("$name" glibc)
[[ ${items[0]} == Lightnix && ${#items[@]} == 2 ]]
[[ $((2 + 3)) == 5 ]]
[[ $(printf '%s' "$name") == Lightnix ]]
result=
for item in "${items[@]}"; do result+="$item:"; done
[[ $result == Lightnix:glibc: ]]
printf '%s\n' "$name"
'''
    result = subprocess.run(command + [str(binary), '--noprofile', '--norc', '-c', script],
                            capture_output=True, text=True, env=environment, check=True)
    require(result.stdout == 'Lightnix\n', 'Bash builtin smoke test failed')
    result = subprocess.run(command + [str(shell), '--noprofile', '--norc', '-c',
                            'set -eu; value=Lightnix; printf "%s\\n" "$value"'],
                            capture_output=True, text=True, env=environment, check=True)
    require(result.stdout == 'Lightnix\n', 'sh-link smoke test failed')
    print(f'OK Bash {version}: installed ELF, sh link, target Ncurses and libc')
    print('OK target-loader execution: version, variables, arrays, arithmetic, substitution, loops, sh')
    print(f'Library resolution: {run / "libraries.log"}')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
