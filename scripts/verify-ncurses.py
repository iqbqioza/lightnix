#!/usr/bin/env python3
"""Check native tic and compile, link, and run a target Ncurses/terminfo probe."""
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
    require(run.parent == Path('/work/build/work') and run.name.startswith('ncurses-bootstrap.'),
            'unexpected verification directory')
    version = (run / 'source-version').read_text().strip()
    release, patch = version.split('-')
    major, minor = map(int, release.split('.'))
    expected = f'{release}.{patch}'
    tic = subprocess.check_output([str(root / 'tools/bin/tic'), '-V'], text=True).strip()
    require(tic == f'ncurses {expected}', f'wrong native tic: {tic}')
    tools = root / 'tools/bin' / os.environ['LFS_TGT']
    source = run / 'smoke.c'
    source.write_text('#include <curses.h>\n#include <term.h>\n#include <unistd.h>\n#include <stdio.h>\n'
                      f'_Static_assert(NCURSES_VERSION_MAJOR == {major} && NCURSES_VERSION_MINOR == {minor}'
                      f' && NCURSES_VERSION_PATCH == {int(patch)}, "Ncurses version mismatch");\n'
                      '_Static_assert(NCURSES_WIDECHAR, "wide-character ABI required");\n'
                      'int main(void) { int status; if(setupterm("xterm", STDOUT_FILENO, &status) == ERR) return 1;\n'
                      'char *cap = tigetstr("clear"); if(!cap || cap == (char *)-1) return 1;\n'
                      'puts(curses_version()); del_curterm(cur_term); return 0; }\n')
    binary = run / 'smoke'
    with (run / 'link.log').open('w') as output:
        subprocess.run([str(tools) + '-gcc', str(source), '-o', str(binary), '-lncurses', '-v', '-Wl,--verbose'],
                       stdout=output, stderr=subprocess.STDOUT, check=True)
    trace = (run / 'link.log').read_text()
    search = re.search(r'#include <\.\.\.> search starts here:\n(.*?)End of search list\.', trace, re.S)
    require(search, 'missing header search paths')
    for line in search[1].splitlines():
        require(Path(line.strip()).resolve().is_relative_to(root), f'host include path: {line}')
    opened = [Path(path).resolve() for path in re.findall(r'attempt to open (.+) succeeded', trace)]
    for name in ('libncursesw.so', 'libc.so.6'):
        require((root / 'usr/lib' / name).resolve() in opened, f'target library not linked: {name}')
    require((root / 'usr/lib/libncurses.so').resolve() == (root / 'usr/lib/libncursesw.so').resolve(),
            'compatibility link does not use wide-character library')
    readelf = str(tools) + '-readelf'
    header = subprocess.check_output([readelf, '-h', str(binary)], text=True)
    require(re.search(r'Class:.*ELF64', header) and re.search(r'Machine:.*X86-64', header), 'wrong ELF architecture')
    program = subprocess.check_output([readelf, '-l', str(binary)], text=True)
    interpreter, = re.findall(r'Requesting program interpreter: ([^\]]+)', program)
    require(interpreter == '/lib64/ld-linux-x86-64.so.2', 'wrong interpreter')
    dynamic = subprocess.check_output([readelf, '-d', str(binary)], text=True)
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic, 'unexpected runtime search path')
    require((root / 'usr/lib/libncurses++w.so').is_file(), 'C++ shared binding missing')
    loader = root / interpreter.lstrip('/')
    environment = {'LC_ALL': 'C', 'PATH': '/usr/bin:/bin', 'TERMINFO': str(root / 'usr/share/terminfo'),
                   'TERMINFO_DIRS': str(root / 'usr/share/terminfo')}
    command = [str(loader), '--inhibit-cache', '--library-path', str(root / 'usr/lib')]
    libraries = subprocess.check_output(command + ['--list', str(binary)], text=True, env=environment)
    (run / 'libraries.log').write_text(libraries)
    require('libncursesw.so' in libraries, 'runtime Ncurses dependency missing')
    for path in re.findall(r'=> (/\S+)', libraries):
        require(Path(path).resolve().is_relative_to(root), f'host library resolved: {path}')
    result = subprocess.run(command + [str(binary)], capture_output=True, text=True, env=environment, check=True)
    require(expected in result.stdout, f'wrong Ncurses runtime version: {result.stdout!r}')
    print(f'OK native tic and target Ncurses {expected}')
    print('OK target headers, wide-character ABI, compatibility link, C++ shared binding, ELF and libc')
    print('OK target-loader execution: xterm terminfo lookup and clear capability')
    print(f'Link trace: {run / "link.log"}')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
