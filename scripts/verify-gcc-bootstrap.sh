#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
root=$(pwd -P)
source build/env.sh
run=$(realpath "${1:?GCC build directory required}")
[[ $root == /work && $LFS == "$root/build/rootfs" ]] || exit 1
[[ $run == "$root/build/work/gcc-bootstrap."* && -d $run/objects ]] || exit 1
source_dir=$(cat "$run/source-path")
gcc_version=$(cat "$run/gcc-version")
tools="$LFS/tools/bin/$LFS_TGT"
cd "$run/objects"
libgcc=$("$tools-gcc" -print-libgcc-file-name)
[[ $libgcc == "$LFS/tools/"* && -f $libgcc ]] || exit 1
cat "$source_dir/gcc/limitx.h" "$source_dir/gcc/glimits.h" "$source_dir/gcc/limity.h" \
    > "$(dirname "$libgcc")/include/limits.h"
for compiler in "$tools-gcc" "$tools-g++"; do
    "$compiler" --version
    [[ $("$compiler" -dumpfullversion) == "$gcc_version" ]]
    [[ $("$compiler" -dumpmachine) == "$LFS_TGT" ]]
    [[ $("$compiler" -print-sysroot) == "$LFS" ]]
    [[ $("$compiler" -print-prog-name=as) -ef $tools-as ]]
    [[ $("$compiler" -print-prog-name=ld) -ef $tools-ld ]]
done
printf 'int lightnix_probe(void) { return 0; }\n' > smoke.c
printf 'extern "C" int lightnix_cpp_probe() { return 0; }\n' > smoke.cc
"$tools-gcc" -c smoke.c -o smoke-c.o
"$tools-g++" -c smoke.cc -o smoke-cxx.o
for object in smoke-c.o smoke-cxx.o; do
    "$tools-readelf" -h "$object"
    "$tools-readelf" -h "$object" | grep -E 'Class:.*ELF64'
    "$tools-readelf" -h "$object" | grep -E 'Type:.*REL'
    "$tools-readelf" -h "$object" | grep -E 'Machine:.*X86-64'
done
