#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make gcc-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == /work/build/rootfs && ! -L $LFS && ! -L $LFS/tools ]] || exit 1
[[ $(realpath "$LFS/tools") == "$root/build/rootfs/tools" ]] || exit 1
mkdir -p build/work build/logs build/stamps
# Hold Binutils' lock too: neither recipe may replace tools used by the other.
exec {binutils_lock}>build/binutils-bootstrap.lock
flock -n "$binutils_lock" || { echo 'Binutilsは構築中です。' >&2; exit 1; }
exec {gcc_lock}>build/gcc-bootstrap.lock
flock -n "$gcc_lock" || { echo 'GCCは構築中です。' >&2; exit 1; }
tools="$LFS/tools/bin/$LFS_TGT"
for tool in as ld readelf; do
    [[ -x $tools-$tool ]] || { echo "Binutilsがありません: $tools-$tool" >&2; exit 1; }
done
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/gcc-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/gcc-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_gcc() {
    date -u
    python3 scripts/prepare-gcc.py "$run"
    source_dir=$(cat "$run/source-path")
    glibc_version=$(cat "$run/glibc-version")
    binutils_version=$(cat "$run/binutils-version")
    "$tools-as" --version | grep -F "$binutils_version"
    "$tools-as" --version | grep -F "$LFS_TGT"
    "$tools-ld" --version | grep -F "$binutils_version"
    [[ $("$tools-ld" --print-sysroot) == "$LFS" ]]
    sed -e '/m64=/s/lib64/lib/' -i.orig "$source_dir/gcc/config/i386/t-linux64"
    mkdir "$run/objects"
    cd "$run/objects"
    time {
        "$source_dir/configure" \
            --target="$LFS_TGT" \
            --prefix="$LFS/tools" \
            --with-glibc-version="$glibc_version" \
            --with-sysroot="$LFS" \
            --with-newlib \
            --without-headers \
            --enable-default-pie \
            --enable-default-ssp \
            --disable-nls \
            --disable-shared \
            --disable-multilib \
            --disable-threads \
            --disable-libatomic \
            --disable-libgomp \
            --disable-libquadmath \
            --disable-libssp \
            --disable-libvtv \
            --disable-libstdcxx \
            --enable-languages=c,c++
        make
        make install
    }
    bash "$root/scripts/verify-gcc-bootstrap.sh" "$run"
    date -u
}
set +e
(set -e; build_gcc) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/gcc-bootstrap.success
tail -n 30 "$log"
echo "GCCブートストラップの構築・検証が完了しました。ログ: $log"
