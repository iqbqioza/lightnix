#!/usr/bin/env python3
"""Verify and unpack one archive from a manifest into a fresh work directory."""
from pathlib import Path
import sys
import tarfile

from sources import load_manifest, verify


def prepare(manifest, name, destination):
    package, = [p for p in load_manifest(manifest) if p['name'] == name]
    if package['kind'] != 'archive':
        raise ValueError(f'{name}: archive required')
    path = Path('sources') / package['filename']
    verify(path, package)
    print(f'Verified {path}', flush=True)
    with tarfile.open(path) as archive:
        directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
        if len(directories) != 1:
            raise ValueError('expected one top-level source directory')
        archive.extractall(destination, filter='data')
    source = destination / directories.pop()
    if not (source / 'configure').is_file():
        raise ValueError(f'{name}: configure script missing')
    (destination / 'source-path').write_text(str(source))
    (destination / 'source-version').write_text(package['version'])


if __name__ == '__main__':
    prepare(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]))
