#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [[ $# == 0 ]]; then
    set -- /bin/bash
fi
options=(--rm --userns=keep-id --user "$(id -u):$(id -g)"
    -v "$PWD:/work:Z" -w /work)
if [[ -t 0 && -t 1 ]]; then
    options+=(-it)
fi
exec podman run "${options[@]}" localhost/lightnix-builder "$@"
