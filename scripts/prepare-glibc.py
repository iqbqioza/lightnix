#!/usr/bin/env python3
"""Verify and extract the pinned glibc source and select its FHS patch."""
from pathlib import Path
import sys
import tarfile

from sources import load_manifest, verify


def prepare(destination):
    packages = load_manifest(Path('manifests/toolchain.json'))
    glibc, = [p for p in packages if p['name'] == 'glibc']
    patch, = [p for p in packages if p['name'] == 'glibc-fhs']
    if glibc['kind'] != 'archive' or patch['kind'] != 'patch':
        raise ValueError('glibc archive and FHS patch required')
    if not patch['version'].startswith(glibc['version'] + '-fhs-'):
        raise ValueError('FHS patch does not match glibc version')
    for package in (glibc, patch):
        path = Path('sources') / package['filename']
        verify(path, package)
        print(f'Verified {path}', flush=True)
    with tarfile.open(Path('sources') / glibc['filename']) as archive:
        directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
        if len(directories) != 1:
            raise ValueError('expected one top-level source directory')
        archive.extractall(destination, filter='data')
    source = destination / directories.pop()
    if not (source / 'configure').is_file():
        raise ValueError('glibc configure script missing')
    (destination / 'source-path').write_text(str(source))
    (destination / 'patch-path').write_text(str((Path('sources') / patch['filename']).resolve()))
    (destination / 'glibc-version').write_text(glibc['version'])


if __name__ == '__main__':
    prepare(Path(sys.argv[1]))
