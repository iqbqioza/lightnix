#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make libstdcxx-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == "$root/build/rootfs" && $(realpath "$LFS") == "$LFS" ]] || exit 1
for directory in usr usr/lib tools; do
    [[ $(realpath "$LFS/$directory") == "$LFS/$directory" ]] || exit 1
done
mkdir -p build/work build/logs build/stamps
exec {binutils_lock}>build/binutils-bootstrap.lock
flock -n "$binutils_lock" || { echo 'Binutilsは構築中です。' >&2; exit 1; }
exec {gcc_lock}>build/gcc-bootstrap.lock
flock -n "$gcc_lock" || { echo 'GCCは構築中です。' >&2; exit 1; }
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || { echo 'Linux APIヘッダは生成中です。' >&2; exit 1; }
exec {glibc_lock}>build/glibc-bootstrap.lock
flock -n "$glibc_lock" || { echo 'glibcは構築中です。' >&2; exit 1; }
exec {libstdcxx_lock}>build/libstdcxx-bootstrap.lock
flock -n "$libstdcxx_lock" || { echo 'libstdc++は構築中です。' >&2; exit 1; }
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-g++ && -f $LFS/usr/lib/libc.so && -f $LFS/usr/include/stdio.h ]] || {
    echo '先にmake gcc-bootstrapとmake glibc-bootstrapを実行してください。' >&2; exit 1;
}
[[ $("$tools-g++" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-g++" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/libstdcxx-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/libstdcxx-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_libstdcxx() {
    date -u
    python3 - "$run" <<'PY'
from pathlib import Path
import sys
import tarfile
sys.path.insert(0, 'scripts')
from sources import load_manifest, verify
package, = [p for p in load_manifest(Path('manifests/toolchain.json')) if p['name'] == 'gcc']
if package['kind'] != 'archive':
    raise ValueError('GCC archive required')
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
if not (source / 'libstdc++-v3/configure').is_file():
    raise ValueError('libstdc++ configure script missing')
(destination / 'source-path').write_text(str(source))
(destination / 'gcc-version').write_text(package['version'])
PY
    source_dir=$(cat "$run/source-path")
    gcc_version=$(cat "$run/gcc-version")
    [[ $("$tools-g++" -dumpfullversion) == "$gcc_version" ]] || exit 1
    mkdir "$run/objects"
    cd "$run/objects"
    time {
        "$source_dir/libstdc++-v3/configure" \
            --host="$LFS_TGT" \
            --build="$(bash "$source_dir/config.guess")" \
            --prefix=/usr \
            --disable-multilib \
            --disable-nls \
            --disable-libstdcxx-pch \
            --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/$gcc_version"
        make
        make DESTDIR="$LFS" install
    }
    # LFS removes these libtool archives to avoid host paths in later cross builds.
    python3 - "$LFS/usr/lib" <<'PY'
from pathlib import Path
import sys
directory = Path(sys.argv[1])
for name in ('libstdc++', 'libstdc++exp', 'libstdc++fs', 'libsupc++'):
    path = directory / (name + '.la')
    path.unlink(missing_ok=True)
    print(f'Removed libtool archive: {path}')
PY
    python3 "$root/scripts/verify-libstdcxx.py" "$run"
    date -u
}
set +e
(set -e; build_libstdcxx) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/libstdcxx-bootstrap.success
tail -n 30 "$log"
echo "libstdc++の構築・配置・リンク検証が完了しました。ログ: $log"
