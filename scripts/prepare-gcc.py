#!/usr/bin/env python3
"""Verify and unpack GCC and its in-tree dependencies for a bootstrap build."""
from pathlib import Path
import sys
import tarfile

from sources import load_manifest, verify


def prepare(destination):
    packages = load_manifest(Path('manifests/toolchain.json'))
    selected = {}
    for name in ('gcc', 'gmp', 'mpfr', 'mpc', 'glibc', 'binutils'):
        package, = [p for p in packages if p['name'] == name]
        selected[name] = package
    # Check every required archive before extracting anything.
    for name in ('gcc', 'gmp', 'mpfr', 'mpc'):
        package = selected[name]
        if package['kind'] != 'archive':
            raise ValueError(f'{name}: archive required')
        verify(Path('sources') / package['filename'], package)
        print(f'Verified {package["filename"]}', flush=True)
    extracted = {}
    for name in ('gcc', 'gmp', 'mpfr', 'mpc'):
        package = selected[name]
        with tarfile.open(Path('sources') / package['filename']) as archive:
            directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
            if len(directories) != 1:
                raise ValueError(f'{name}: expected one top-level directory')
            archive.extractall(destination, filter='data')
        extracted[name] = destination / directories.pop()
        if not extracted[name].is_dir():
            raise ValueError(f'{name}: source directory missing')
    source = extracted['gcc']
    for name in ('gmp', 'mpfr', 'mpc'):
        extracted[name].rename(source / name)
    if not (source / 'configure').is_file():
        raise ValueError('GCC configure script missing')
    (destination / 'source-path').write_text(str(source))
    for name in ('gcc', 'glibc', 'binutils'):
        (destination / f'{name}-version').write_text(selected[name]['version'])


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
