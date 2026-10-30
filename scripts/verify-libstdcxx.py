#!/usr/bin/env python3
"""Link a C++ standard-library probe and verify target headers and libraries."""
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
    require(run.parent == Path('/work/build/work') and run.name.startswith('libstdcxx-bootstrap.'),
            'unexpected verification directory')
    target = os.environ['LFS_TGT']
    tools = root / 'tools/bin' / target
    compiler = str(tools) + '-g++'
    readelf = str(tools) + '-readelf'
    version = (run / 'gcc-version').read_text().strip()
    source = run / 'smoke.cc'
    source.write_text('#include <algorithm>\n#include <iostream>\n#include <string>\n#include <vector>\n'
                      f'static_assert(_GLIBCXX_RELEASE == {int(version.split(".")[0])}, "libstdc++ release mismatch");\n'
                      'int main() { std::vector<std::string> names{"Lightnix", "glibc"};\n'
                      'std::sort(names.begin(), names.end()); std::cout << names.at(0) << std::endl; }\n')
    binary = run / 'smoke'
    log = run / 'link.log'
    with log.open('w') as stream:
        subprocess.run([compiler, str(source), '-o', str(binary), '-v', '-Wl,--verbose'],
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    trace = log.read_text()
    header_search = re.search(r'#include <\.\.\.> search starts here:\n(.*?)End of search list\.', trace, re.S)
    require(header_search, 'missing header search paths')
    include_paths = [Path(line.strip()).resolve() for line in header_search[1].splitlines() if line.strip()]
    expected_include = root / 'tools' / target / 'include/c++' / version
    require(expected_include in include_paths, 'target C++ include directory missing')
    for path in include_paths:
        require(path.is_relative_to(root), f'host include directory used: {path}')
    opened = [Path(path).resolve() for path in re.findall(r'attempt to open (.+) succeeded', trace)]
    for name in ('libstdc++.so', 'libc.so.6'):
        path = root / 'usr/lib' / name
        require(path.is_file() and path.resolve() in opened, f'target library not linked: {name}')
    for path in opened:
        require(path.is_relative_to(root) or path.is_relative_to(Path('/tmp')),
                f'linker opened a file outside the target: {path}')
    search_paths = re.findall(r'SEARCH_DIR\("([^"\n]+)"\)', trace)
    require(search_paths and all(path.startswith('=') for path in search_paths),
            'linker search directory is not relative to sysroot')
    program_headers = subprocess.check_output([readelf, '-l', str(binary)], text=True)
    interpreter, = re.findall(r'Requesting program interpreter: ([^\]]+)', program_headers)
    require(interpreter == '/lib64/ld-linux-x86-64.so.2', f'wrong interpreter: {interpreter}')
    require((root / interpreter.lstrip('/')).is_file(), 'target loader missing')
    dynamic = subprocess.check_output([readelf, '-d', str(binary)], text=True)
    soname = re.search(r'\(SONAME\).*\[([^\]]+)\]', subprocess.check_output(
        [readelf, '-d', str(root / 'usr/lib/libstdc++.so')], text=True))
    require(soname, 'libstdc++ SONAME missing')
    require(f'Shared library: [{soname[1]}]' in dynamic, 'libstdc++ dependency missing')
    require('Shared library: [libc.so.6]' in dynamic, 'libc dependency missing')
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic, 'unexpected runtime search path')
    for name in ('libstdc++', 'libstdc++exp', 'libstdc++fs', 'libsupc++'):
        require(not (root / 'usr/lib' / (name + '.la')).exists(), f'libtool archive remains: {name}')
    print(f'OK libstdc++ from GCC {version}: target standard headers and libraries')
    print(f'OK ELF interpreter: {interpreter}, dependency: {soname[1]}')
    print(f'OK linked C++ program: {binary} (not executed)')
    print(f'Link trace: {log}')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
