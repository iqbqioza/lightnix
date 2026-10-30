#!/usr/bin/env python3
"""Fetch and verify pinned source files using only the Python standard library."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def https_url(url):
    if not isinstance(url, str):
        raise ValueError('URL must be a string')
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(f'HTTPS URL required: {url}')
    return url


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        https_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def load_manifest(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get('schema_version') != 1:
        raise ValueError('unsupported manifest schema')
    packages = data.get('packages')
    if not isinstance(packages, list) or not packages:
        raise ValueError('packages must be a nonempty list')
    seen = set()
    for package in packages:
        if not isinstance(package, dict):
            raise ValueError('package must be an object')
        filename = package.get('filename', '')
        if not isinstance(filename, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*', filename):
            raise ValueError(f'invalid filename: {filename!r}')
        if filename in seen:
            raise ValueError(f'duplicate filename: {filename}')
        seen.add(filename)
        if not isinstance(package.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', package['sha256']):
            raise ValueError(f'invalid SHA-256: {filename}')
        size = package.get('size_bytes')
        if type(size) is not int or size <= 0:
            raise ValueError(f'invalid size: {filename}')
        https_url(package.get('url'))
    if seen & {filename + '.part' for filename in seen}:
        raise ValueError('filename conflicts with a partial download')
    return packages


def verify(path, package):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'missing or not a regular file: {path}')
    if path.stat().st_size != package['size_bytes']:
        raise ValueError(f'size mismatch: {path}')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != package['sha256']:
        raise ValueError(f'SHA-256 mismatch: {path}')


def fetch(package, directory, opener):
    path = directory / package['filename']
    if path.exists() or path.is_symlink():
        verify(path, package)
        print(f'REUSE {path.name}', flush=True)
        return
    partial = directory / (path.name + '.part')
    # The directory lock excludes other instances of this command.
    # A failed attempt is retained, then replaced on the next attempt.
    if partial.is_symlink() or (partial.exists() and not partial.is_file()):
        raise ValueError(f'not a regular partial file: {partial}')
    print(f'FETCH {path.name}', flush=True)
    if partial.exists():
        partial.unlink()
    with partial.open('xb') as output:
        with opener.open(package['url'], timeout=60) as response:
            https_url(response.geturl())
            size = 0
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > package['size_bytes']:
                    raise ValueError(f'download exceeds expected size: {path.name}')
                output.write(chunk)
    verify(partial, package)
    partial.replace(path)
    print(f'OK    {path.name}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['fetch', 'verify'])
    parser.add_argument('--manifest', type=Path, default=ROOT / 'manifests/toolchain.json')
    parser.add_argument('--sources', type=Path, default=ROOT / 'sources')
    args = parser.parse_args()
    packages = load_manifest(args.manifest)
    if args.action == 'verify':
        for package in packages:
            verify(args.sources / package['filename'], package)
            print(f'OK    {package["filename"]}', flush=True)
    else:
        args.sources.mkdir(parents=True, exist_ok=True)
        # Lock the directory itself so no extra lock file enters the source cache.
        descriptor = os.open(args.sources, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            opener = urllib.request.build_opener(HTTPSRedirect())
            for package in packages:
                fetch(package, args.sources, opener)
        finally:
            os.close(descriptor)
    print(f'Verified {len(packages)} source files.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
