#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
[[ $root == /work ]] || { echo 'make binutils-bootstrapで専用コンテナから実行してください。' >&2; exit 1; }
[[ $(id -u) != 0 ]] || { echo 'rootでは実行できません。' >&2; exit 1; }
python3 scripts/check-host.py
bash scripts/prepare.sh
source build/env.sh
[[ $LFS == /work/build/rootfs && ! -L $LFS && ! -L $LFS/tools ]] || exit 1
[[ $(realpath "$LFS/tools") == "$root/build/rootfs/tools" ]] || exit 1
mkdir -p build/work build/logs build/stamps
exec 9>build/binutils-bootstrap.lock
flock -n 9 || { echo 'Binutils pass 1は実行中です。' >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
Path('build/stamps/binutils-bootstrap.success').unlink(missing_ok=True)
PY
run=$(mktemp -d "$root/build/work/binutils-bootstrap.XXXXXXXX")
log="$root/build/logs/$(basename "$run").log"
echo "ログ: $log"
echo "作業先: $run"
build_binutils() {
    date -u
    python3 - "$run" <<'PY'
import sys
import tarfile
from pathlib import Path
sys.path.insert(0, 'scripts')
from sources import load_manifest, verify
packages = load_manifest(Path('manifests/toolchain.json'))
package, = [p for p in packages if p['name'] == 'binutils']
if package['kind'] != 'archive':
    raise ValueError('Binutils source must be an archive')
path = Path('sources') / package['filename']
verify(path, package)
print(f'Verified {path}', flush=True)
with tarfile.open(path) as archive:
    directories = {Path(member.name).parts[0] for member in archive.getmembers() if member.name}
    if len(directories) != 1:
        raise ValueError('expected one top-level source directory')
    archive.extractall(sys.argv[1], filter='data')
source = Path(sys.argv[1]) / directories.pop()
if not (source / 'configure').is_file():
    raise ValueError('source configure script is missing')
(Path(sys.argv[1]) / 'source-path').write_text(str(source))
(Path(sys.argv[1]) / 'source-version').write_text(package['version'])
PY
    source_dir=$(cat "$run/source-path")
    version=$(cat "$run/source-version")
    mkdir "$run/objects"
    cd "$run/objects"
    time {
        "$source_dir/configure" \
            --prefix="$LFS/tools" \
            --with-sysroot="$LFS" \
            --target="$LFS_TGT" \
            --disable-nls \
            --enable-gprofng=no \
            --disable-werror \
            --enable-new-dtags \
            --enable-default-hash-style=gnu
        make
        make install
    }
    tools="$LFS/tools/bin/$LFS_TGT"
    "$tools-as" --version
    "$tools-ld" --version
    "$tools-as" --version | grep -F "$version"
    "$tools-as" --version | grep -F "$LFS_TGT"
    "$tools-ld" --version | grep -F "$version"
    [[ $("$tools-ld" --print-sysroot) == "$LFS" ]]
    # Assemble and link without libc; inspect the resulting ELF rather than running it.
    cat > smoke.s <<'ASM'
.global _start
.text
_start:
    nop
ASM
    "$tools-as" -o smoke.o smoke.s
    "$tools-ld" -o smoke smoke.o
    "$tools-readelf" -h smoke
    "$tools-readelf" -h smoke | grep -E 'Class:.*ELF64'
    "$tools-readelf" -h smoke | grep -E 'Machine:.*X86-64'
    date -u
}
# Run in a subshell with errexit active; do not place the function in an if condition.
set +e
(set -e; build_binutils) > "$log" 2>&1
status=$?
set -e
if (( status != 0 )); then
    tail -n 60 "$log"
    echo "失敗しました。ログ: $log" >&2
    exit "$status"
fi
printf 'log=%s\nwork=%s\n' "$log" "$run" > build/stamps/binutils-bootstrap.success
tail -n 25 "$log"
echo "Binutils pass 1の構築・検証が完了しました。ログ: $log"
