#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make linux-headersで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $(realpath "$LFS") == "$root/build/rootfs" ]] || exit 1
[[ $(realpath "$LFS/usr") == "$root/build/rootfs/usr" ]] || exit 1
mkdir -p "$LFS/usr/include" build/work build/logs build/stamps
[[ $(realpath "$LFS/usr/include") == "$root/build/rootfs/usr/include" ]] || exit 1
exec {binutils_lock}>build/binutils-bootstrap.lock
flock -n "$binutils_lock" || { echo 'Binutilsは構築中です。' >&2; exit 1; }
exec {gcc_lock}>build/gcc-bootstrap.lock
flock -n "$gcc_lock" || { echo 'GCCは構築中です。' >&2; exit 1; }
exec {headers_lock}>build/linux-headers.lock
flock -n "$headers_lock" || { echo 'Linux APIヘッダは生成中です。' >&2; exit 1; }
tools="$LFS/tools/bin/$LFS_TGT"
[[ -x $tools-gcc && -x $tools-readelf ]] || { echo '先にmake gcc-bootstrapを実行してください。' >&2; exit 1; }
[[ $("$tools-gcc" -dumpmachine) == "$LFS_TGT" ]] || exit 1
[[ $("$tools-gcc" -print-sysroot) == "$LFS" ]] || exit 1
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/linux-headers.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/linux-headers.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_headers() {
    date -u
    python3 - "$run" <<'PY'
from pathlib import Path
import sys
import tarfile
sys.path.insert(0, 'scripts')
from sources import load_manifest, verify
package, = [p for p in load_manifest(Path('manifests/toolchain.json')) if p['name'] == 'linux']
if package['kind'] != 'archive':
    raise ValueError('Linux source must be an archive')
archive_path = Path('sources') / package['filename']
verify(archive_path, package)
print(f'Verified {archive_path}', flush=True)
destination = Path(sys.argv[1])
with tarfile.open(archive_path) as archive:
    directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
    if len(directories) != 1:
        raise ValueError('expected one top-level source directory')
    archive.extractall(destination, filter='data')
source = destination / directories.pop()
if not (source / 'Makefile').is_file():
    raise ValueError('Linux Makefile missing')
(destination / 'source-path').write_text(str(source))
# Generate a compile-time assertion from the pinned version, not the host kernel.
major, minor, patch = map(int, package['version'].split('.'))
(destination / 'smoke.c').write_text(
    '#include <linux/version.h>\n#include <linux/types.h>\n#include <asm/unistd.h>\n'
    f'_Static_assert(LINUX_VERSION_CODE == KERNEL_VERSION({major}, {minor}, {patch}), "API version mismatch");\n'
    '__u64 lightnix_kernel_api_probe(void) { return __NR_exit; }\n')
PY
    source_dir=$(cat "$run/source-path")
    cd "$source_dir"
    # LFS uses make headers to avoid a dependency on rsync/headers_install.
    make ARCH=x86 mrproper
    make ARCH=x86 headers
    python3 - "$source_dir/usr/include" "$LFS/usr/include" <<'PY'
from pathlib import Path
import shutil
import sys
source, destination = map(Path, sys.argv[1:])
count = 0
for header in sorted(source.rglob('*.h')):
    if header.is_symlink() or not header.is_file():
        raise ValueError(f'not a regular header: {header}')
    target = destination / header.relative_to(source)
    if not target.resolve().is_relative_to(destination.resolve()):
        raise ValueError(f'header escapes destination: {target}')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(header, target)
    if header.read_bytes() != target.read_bytes():
        raise ValueError(f'copy mismatch: {target}')
    count += 1
if not count:
    raise ValueError('no headers generated')
for name in ('linux/version.h', 'linux/types.h', 'asm/types.h', 'asm/unistd.h', 'asm-generic/errno.h'):
    if not (destination / name).is_file():
        raise ValueError(f'required header missing: {name}')
print(f'Installed and compared {count} API headers', flush=True)
PY
    "$tools-gcc" -std=c11 -nostdinc -isystem "$LFS/usr/include" -c "$run/smoke.c" -o "$run/smoke.o"
    "$tools-readelf" -h "$run/smoke.o"
    "$tools-readelf" -h "$run/smoke.o" | grep -E 'Class:.*ELF64'
    "$tools-readelf" -h "$run/smoke.o" | grep -E 'Type:.*REL'
    "$tools-readelf" -h "$run/smoke.o" | grep -E 'Machine:.*X86-64'
    date -u
}
set +e
(set -e; build_headers) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/linux-headers.success
tail -n 30 "$log"
echo "Linux APIヘッダの生成・配置・検証が完了しました。ログ: $log"
