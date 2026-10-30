#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make bash-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == "$root/build/rootfs" && $(realpath "$LFS") == "$LFS" ]] || exit 1
for directory in usr usr/bin usr/lib tools; do
    [[ $(realpath "$LFS/$directory") == "$LFS/$directory" ]] || exit 1
done
[[ -L $LFS/bin && $(readlink "$LFS/bin") == usr/bin ]] || exit 1
mkdir -p build/work build/logs build/stamps
for stage in binutils gcc glibc libstdcxx m4 ncurses bash; do
    exec {lock_fd}>"build/$stage-bootstrap.lock"
    flock -n "$lock_fd" || { echo "$stage は構築中です。" >&2; exit 1; }
done
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || exit 1
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-gcc && -f $LFS/usr/lib/libc.so && -f $LFS/usr/lib/libncurses.so ]] || {
    echo '先にクロスGCC・glibc・Ncursesを構築してください。' >&2; exit 1;
}
[[ $("$tools-gcc" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-gcc" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/bash-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/bash-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_bash() {
    date -u
    python3 scripts/prepare-package.py manifests/temporary-tools.json bash "$run"
    source_dir=$(cat "$run/source-path")
    mkdir "$run/objects"
    cd "$run/objects"
    time {
        "$source_dir/configure" \
            --prefix=/usr \
            --build="$(bash "$source_dir/support/config.guess")" \
            --host="$LFS_TGT" \
            --without-bash-malloc
        make
        make DESTDIR="$LFS" install
    }
    ln -sfn bash "$LFS/usr/bin/sh"
    python3 "$root/scripts/verify-bash.py" "$run"
    date -u
}
set +e
(set -e; build_bash) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/bash-bootstrap.success
tail -n 30 "$log"
echo "Bashの構築・配置・検証が完了しました。ログ: $log"
