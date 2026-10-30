#!/usr/bin/env python3
"""Compile/link a C probe and audit its target headers, startup files and libc."""
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
    require(run.parent == Path('/work/build/work') and run.name.startswith('glibc-bootstrap.'),
            'unexpected verification directory')
    tools = root / 'tools/bin' / os.environ['LFS_TGT']
    compiler = str(tools) + '-gcc'
    readelf = str(tools) + '-readelf'
    version = (run / 'glibc-version').read_text().strip()
    major, minor = map(int, version.split('.'))
    source = run / 'smoke.c'
    source.write_text('#include <features.h>\n#include <stdio.h>\n'
                      f'_Static_assert(__GLIBC__ == {major} && __GLIBC_MINOR__ == {minor}, "glibc version mismatch");\n'
                      'int main(void) { return puts("Lightnix glibc")==EOF; }\n')
    binary = run / 'smoke'
    log = run / 'link.log'
    with log.open('w') as stream:
        subprocess.run([compiler, str(source), '-o', str(binary), '-v', '-Wl,--verbose'],
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    trace = log.read_text()
    header_search = re.search(r'#include <\.\.\.> search starts here:\n(.*?)End of search list\.', trace, re.S)
    require(header_search, 'missing compiler header search paths')
    include_paths = [Path(line.strip()) for line in header_search[1].splitlines() if line.strip()]
    require(root / 'usr/include' in include_paths, 'target include directory missing')
    for path in include_paths:
        require(path.resolve().is_relative_to(root), f'host include directory used: {path}')
    for name in ('Scrt1.o', 'crti.o', 'crtn.o'):
        path = Path(subprocess.check_output([compiler, '-print-file-name=' + name], text=True).strip())
        require(path.is_file() and path.resolve().is_relative_to(root), f'wrong startup file: {path}')
        require(any(Path(found).resolve() == path.resolve() for found in
                    re.findall(r'attempt to open (.+) succeeded', trace)), f'startup file not linked: {name}')
    libc = root / 'usr/lib/libc.so.6'
    opened = [Path(found).resolve() for found in re.findall(r'attempt to open (.+) succeeded', trace)]
    require(libc.resolve() in opened, 'target libc was not linked')
    for path in opened:
        require(path.is_relative_to(root) or path == (run / 'smoke.o').resolve() or path.is_relative_to(Path('/tmp')),
                f'linker opened a file outside the target: {path}')
    search_paths = re.findall(r'SEARCH_DIR\("([^"\n]+)"\)', trace)
    require(search_paths and all(path.startswith('=') for path in search_paths),
            'linker search directory is not relative to sysroot')
    program_headers = subprocess.check_output([readelf, '-l', str(binary)], text=True)
    interpreter, = re.findall(r'Requesting program interpreter: ([^\]]+)', program_headers)
    require(interpreter == '/lib64/ld-linux-x86-64.so.2', f'wrong interpreter: {interpreter}')
    require((root / interpreter.lstrip('/')).resolve() == (root / 'usr/lib/ld-linux-x86-64.so.2').resolve(),
            'loader symlink does not resolve to target loader')
    require((root / interpreter.lstrip('/')).is_file(), 'target loader missing')
    dynamic = subprocess.check_output([readelf, '-d', str(binary)], text=True)
    require('Shared library: [libc.so.6]' in dynamic, 'libc dependency missing')
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic, 'unexpected runtime search path')
    print(f'OK glibc {version}: target headers, startup files, libc, sysroot search paths')
    print(f'OK ELF interpreter: {interpreter}')
    print(f'OK linked C program: {binary} (not executed)')
    print(f'Link trace: {log}')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
