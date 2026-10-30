#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make m4-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == "$root/build/rootfs" && $(realpath "$LFS") == "$LFS" ]] || exit 1
for directory in usr usr/bin usr/lib tools; do
    [[ $(realpath "$LFS/$directory") == "$LFS/$directory" ]] || exit 1
done
mkdir -p build/work build/logs build/stamps
exec {binutils_lock}>build/binutils-bootstrap.lock
flock -n "$binutils_lock" || exit 1
exec {gcc_lock}>build/gcc-bootstrap.lock
flock -n "$gcc_lock" || exit 1
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || exit 1
exec {glibc_lock}>build/glibc-bootstrap.lock
flock -n "$glibc_lock" || exit 1
exec {libstdcxx_lock}>build/libstdcxx-bootstrap.lock
flock -n "$libstdcxx_lock" || exit 1
exec {m4_lock}>build/m4-bootstrap.lock
flock -n "$m4_lock" || { echo 'M4は構築中です。' >&2; exit 1; }
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-gcc && -f $LFS/usr/lib/libc.so && -f $LFS/usr/include/stdio.h ]] || {
    echo 'クロスGCCとglibcを先に構築してください。' >&2; exit 1;
}
[[ $("$tools-gcc" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-gcc" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/m4-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/m4-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_m4() {
    date -u
    python3 - "$run" <<'PY'
from pathlib import Path
import sys
import tarfile
sys.path.insert(0, 'scripts')
from sources import load_manifest, verify
package, = [p for p in load_manifest(Path('manifests/temporary-tools.json')) if p['name'] == 'm4']
if package['kind'] != 'archive':
    raise ValueError('M4 archive required')
path = Path('sources') / package['filename']
verify(path, package)
print(f'Verified {path}', flush=True)
destination = Path(sys.argv[1])
with tarfile.open(path) as archive:
    directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
    if len(directories) != 1:
        raise ValueError('expected one top-level source directory')
    archive.extractall(destination, filter='data')
source = destination / directories.pop()
if not (source / 'configure').is_file():
    raise ValueError('M4 configure script missing')
(destination / 'source-path').write_text(str(source))
(destination / 'm4-version').write_text(package['version'])
PY
    source_dir=$(cat "$run/source-path")
    mkdir "$run/objects"
    cd "$run/objects"
    time {
        "$source_dir/configure" \
            --prefix=/usr \
            --host="$LFS_TGT" \
            --build="$(bash "$source_dir/build-aux/config.guess")"
        make
        make DESTDIR="$LFS" install
    }
    python3 "$root/scripts/verify-m4.py" "$run"
    date -u
}
set +e
(set -e; build_m4) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/m4-bootstrap.success
tail -n 30 "$log"
echo "M4の構築・配置・検証が完了しました。ログ: $log"
