#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
if [[ $(uname -m) != x86_64 ]]; then
    echo '現在はx86_64ホストのみ対応しています。' >&2
    exit 1
fi
if [[ $root == *[[:space:]]* ]]; then
    echo 'LFS構築には空白を含まないパスを使ってください。' >&2
    exit 1
fi
umask 022
mkdir -p build/rootfs/{etc,var,tools,usr/{bin,lib,sbin},lib64} build/logs sources
for name in bin lib sbin; do
    target="build/rootfs/$name"
    if [[ ! -e $target && ! -L $target ]]; then
        ln -s "usr/$name" "$target"
    fi
done
{
    printf 'export LFS=%q\n' "$root/build/rootfs"
    printf 'export LFS_TGT=x86_64-lfs-linux-gnu\n'
    printf 'export LC_ALL=POSIX\n'
    printf 'export CONFIG_SITE=%q\n' "$root/build/rootfs/usr/share/config.site"
    printf 'export PATH=%q:/usr/bin:/bin\n' "$root/build/rootfs/tools/bin"
    printf 'export MAKEFLAGS=-j2\n'
    printf 'umask 022\n'
} > build/env.sh
printf '%s\n' '構築先を準備しました。source build/env.sh で環境を読み込めます。'
