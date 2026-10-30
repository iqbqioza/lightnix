#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make glibc-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
source config/toolchain.env
[[ $LFS == "$root/build/rootfs" && $(realpath "$LFS") == "$LFS" ]] || exit 1
# Installation must stay within the target tree even when rerunning a build.
for directory in usr usr/lib usr/include usr/bin usr/sbin etc var lib64; do
    [[ $(realpath -m "$LFS/$directory") == "$LFS/$directory" ]] || exit 1
done
[[ -L $LFS/lib && $(readlink "$LFS/lib") == usr/lib ]] || exit 1
mkdir -p build/work build/logs build/stamps "$LFS/usr/lib" "$LFS/usr/sbin"
exec {binutils_lock}>build/binutils-bootstrap.lock
flock -n "$binutils_lock" || { echo 'Binutilsは構築中です。' >&2; exit 1; }
exec {gcc_lock}>build/gcc-bootstrap.lock
flock -n "$gcc_lock" || { echo 'GCCは構築中です。' >&2; exit 1; }
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || { echo 'Linux APIヘッダは生成中です。' >&2; exit 1; }
exec {glibc_lock}>build/glibc-bootstrap.lock
flock -n "$glibc_lock" || { echo 'glibcは構築中です。' >&2; exit 1; }
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-gcc && -f $LFS/usr/include/linux/version.h ]] || {
    echo '先にmake gcc-bootstrapとmake linux-headersを実行してください。' >&2; exit 1;
}
[[ $("$tools-gcc" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-gcc" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/glibc-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/glibc-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_glibc() {
    date -u
    python3 scripts/prepare-glibc.py "$run"
    source_dir=$(cat "$run/source-path")
    patch_path=$(cat "$run/patch-path")
    cd "$source_dir"
    patch --batch --fuzz=0 -Np1 -i "$patch_path"
    ln -sfn ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-linux-x86-64.so.2"
    ln -sfn ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
    mkdir "$run/objects"
    cd "$run/objects"
    printf 'rootsbindir=/usr/sbin\n' > configparms
    time {
        "$source_dir/configure" \
            --prefix=/usr \
            --host="$LFS_TGT" \
            --build="$(bash "$source_dir/scripts/config.guess")" \
            --disable-nscd \
            libc_cv_slibdir=/usr/lib \
            --enable-kernel="$LINUX_MIN_VERSION"
        make
        make DESTDIR="$LFS" install
    }
    sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
    python3 "$root/scripts/verify-glibc.py" "$run"
    date -u
}
set +e
(set -e; build_glibc) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/glibc-bootstrap.success
tail -n 30 "$log"
echo "glibcの構築・配置・リンク検証が完了しました。ログ: $log"
