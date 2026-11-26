#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
python=${PYTHON:-python3}
version=$("$python" scripts/inputs.py --version)
work=$(mktemp -d "$root/out/verify.XXXXXXXX")
bin="$work/platform-tools"
export LC_ALL=C TZ=UTC HOME="$work/home" ANDROID_USER_HOME="$work/home"
export ADB_SERVER_SOCKET="localfilesystem:$work/adb.sock" ADB_MDNS=0 ADB_USB=0 ADB_EMU=0
unset ANDROID_ADB_SERVER_ADDRESS ANDROID_ADB_SERVER_PORT ADB_VENDOR_KEYS ADB_LOCAL_TRANSPORT_MAX_PORT
mkdir -p "$HOME"
trap 'if [[ -S "$work/adb.sock" ]]; then "$bin/adb" kill-server >/dev/null 2>&1 || true; fi; rm -rf -- "$work"' EXIT
unzip -q "out/dist/aosstudio-platform-tools-$version-linux-x86_64.zip" -d "$work"
grep -Fx "Pkg.Revision=$version" "$bin/source.properties"
cmp locks/inputs.json "$bin/source-inputs.json"
test -s "$bin/licenses/AOSP"
test -s "$bin/licenses/external-f2fs-tools-COPYING"
test -s "$bin/licenses/external-libusb-COPYING"
for command in adb fastboot make_f2fs make_f2fs_casefold mke2fs sqlite3 etc1tool hprof-conv; do
    test -x "$bin/$command"
done

"$bin/adb" version | grep -F "Version $version-aosstudio-android17-r1"
"$bin/fastboot" --version | grep -F "fastboot version $version-aosstudio-android17-r1"
timeout 15 "$bin/adb" start-server
timeout 10 "$bin/adb" server-status | grep -F "version: \"$version\""
timeout 10 "$bin/adb" devices > "$work/devices.txt"
grep -Fx 'List of devices attached' "$work/devices.txt"
timeout 10 "$bin/adb" kill-server

truncate -s 32M "$work/ext4.img"
MKE2FS_CONFIG="$bin/mke2fs.conf" "$bin/mke2fs" -F -t ext4 "$work/ext4.img"
test "$(blkid -p -s TYPE -o value "$work/ext4.img")" = ext4
for format in make_f2fs make_f2fs_casefold; do
    truncate -s 128M "$work/$format.img"
    "$bin/$format" -t 0 "$work/$format.img" > "$work/$format.log"
    grep -F 'format successful' "$work/$format.log"
    test "$(blkid -p -s TYPE -o value "$work/$format.img")" = f2fs
done
grep -F 'with casefolding' "$work/make_f2fs_casefold.log"
touch "$work/f2fs.sparse"
"$bin/make_f2fs" -S 134217728 -g android "$work/f2fs.sparse" > "$work/f2fs.sparse.log"
test "$(od -An -N4 -tx1 "$work/f2fs.sparse" | tr -d ' \n')" = 3aff26ed
# The first raw chunk contains the F2FS superblock, 1024 bytes into the image.
test "$(od -An -j1064 -N4 -tx1 "$work/f2fs.sparse" | tr -d ' \n')" = 1020f5f2

"$bin/sqlite3" ':memory:' 'SELECT upper(char(233));' | grep -Fx É
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGOQqDgARwzEcQAX0hUB99fHIwAAAABJRU5ErkJggg==' |
    base64 -d > "$work/input.png"
"$bin/etc1tool" "$work/input.png" -o "$work/encoded.pkm"
"$bin/etc1tool" "$work/encoded.pkm" --decode -o "$work/decoded.png"
test "$(od -An -j16 -N8 -tx1 "$work/decoded.png" | tr -d ' \n')" = 0000000400000004

printf 'JAVA PROFILE 1.0.3\0\0\0\0\x04\0\0\0\0\0\0\0\0' > "$work/sample.hprof"
printf 'JAVA PROFILE 1.0.2\0\0\0\0\x04\0\0\0\0\0\0\0\0' > "$work/expected.hprof"
"$bin/hprof-conv" "$work/sample.hprof" "$work/converted.hprof"
cmp "$work/expected.hprof" "$work/converted.hprof"
printf 'Platform Tools %s package verified\n' "$version"
