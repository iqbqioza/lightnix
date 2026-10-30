#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make ncurses-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == "$root/build/rootfs" && $(realpath "$LFS") == "$LFS" ]] || exit 1
for directory in usr usr/lib usr/include tools tools/bin; do
    [[ $(realpath "$LFS/$directory") == "$LFS/$directory" ]] || exit 1
done
mkdir -p build/work build/logs build/stamps
# Keep every dependency stable while native tic and target libraries are built.
for stage in binutils gcc glibc libstdcxx m4 ncurses; do
    exec {lock_fd}>"build/$stage-bootstrap.lock"
    flock -n "$lock_fd" || { echo "$stage は構築中です。" >&2; exit 1; }
done
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || exit 1
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-g++ && -f $LFS/usr/lib/libstdc++.so && -f $LFS/usr/lib/libc.so ]] || {
    echo '先にクロスツールチェーンを構築してください。' >&2; exit 1;
}
[[ $("$tools-gcc" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-gcc" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/ncurses-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/ncurses-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_ncurses() {
    date -u
    python3 scripts/prepare-package.py manifests/temporary-tools.json ncurses "$run"
    source_dir=$(cat "$run/source-path")
    mkdir "$run/native" "$run/objects"
    cd "$run/native"
    "$source_dir/configure" --prefix="$LFS/tools" AWK=gawk
    make -C include
    make -C progs tic
    install progs/tic "$LFS/tools/bin/tic"
    "$LFS/tools/bin/tic" -V
    cd "$run/objects"
    time {
        "$source_dir/configure" \
            --prefix=/usr \
            --host="$LFS_TGT" \
            --build="$(bash "$source_dir/config.guess")" \
            --mandir=/usr/share/man \
            --with-manpage-format=normal \
            --with-shared \
            --without-normal \
            --with-cxx-shared \
            --without-debug \
            --without-ada \
            --disable-stripping \
            AWK=gawk
        make
        make DESTDIR="$LFS" install
    }
    ln -sfn libncursesw.so "$LFS/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
    python3 "$root/scripts/verify-ncurses.py" "$run"
    date -u
}
set +e
(set -e; build_ncurses) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/ncurses-bootstrap.success
tail -n 30 "$log"
echo "Ncursesの構築・配置・検証が完了しました。ログ: $log"
