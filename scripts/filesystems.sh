#!/usr/bin/env bash
set -euo pipefail

source_dir=$1
work=$2
package=$3
jobs=$4
scripts=$(cd -- "$(dirname -- "$0")" && pwd)
e2fs="$work/e2fs"
mkdir "$e2fs" "$work/f2fs"
(
    cd "$e2fs"
    "$source_dir/external/e2fsprogs/configure" \
        --enable-libblkid --enable-libuuid --disable-nls --disable-uuidd \
        --disable-e2initrd-helper --disable-defrag --disable-fuse2fs
    make -j"$jobs" libs
    make -j"$jobs" -C misc mke2fs
)
install -m 0755 "$e2fs/misc/mke2fs" "$package/mke2fs"
install -m 0644 "$source_dir/system/extras/ext4_utils/mke2fs.conf" "$package/mke2fs.conf"

f2fs="$source_dir/external/f2fs-tools"
cd "$work/f2fs"
printf '#include "%s"\n#undef HAVE_SPARSE_SPARSE_H\n' "$f2fs/include/android_config.h" > android_config.h
common=(-O2 -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -DWITH_ANDROID
    -DF2FS_MAJOR_VERSION=1 -DF2FS_MINOR_VERSION=16
    -DF2FS_TOOLS_DATE='"2023-04-11"' -DF2FS_TOOLS_VERSION='"1.16.0"'
    -I"$work/f2fs" -I"$f2fs/include" -I"$f2fs/fsck" -I"$f2fs/mkfs" -I"$e2fs/lib"
    -I"$source_dir/external/e2fsprogs/lib")
for file in lib/libf2fs.c lib/libf2fs_zoned.c lib/nls_utf8.c mkfs/f2fs_format.c mkfs/f2fs_format_utils.c; do
    "$CC" "${common[@]}" -DWITH_BLKDISCARD -c "$f2fs/$file" -o "${file##*/}.o"
done
"$CC" "${common[@]}" -c "$f2fs/lib/libf2fs_io.c" -o libf2fs_io.c.o
for variant in make_f2fs make_f2fs_casefold; do
    variant_flags=()
    if [[ $variant == make_f2fs_casefold ]]; then
        variant_flags=(-DCONF_CASEFOLD -DCONF_PROJID)
    fi
    "$CC" "${common[@]}" "${variant_flags[@]}" -c "$f2fs/mkfs/f2fs_format_main.c" -o "$variant-main.o"
    "$CC" ./*.c.o "$variant-main.o" "$e2fs/lib/libuuid.a" -o "$package/libexec/$variant"
    install -m 0755 "$scripts/make-f2fs.sh" "$package/$variant"
done
