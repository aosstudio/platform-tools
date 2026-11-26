#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
python=${PYTHON:-python3}
jobs=${BUILD_JOBS:-8}
llvm=${LLVM_ROOT:-/usr}
cache="$root/out/inputs/tool"
test "$(uname -s)" = Linux
test "$(uname -m)" = x86_64
test -f "$llvm/lib/llvm-22/include/c++/v1/vector"
test -f "$llvm/lib/x86_64-linux-gnu/libc++.a"
version=$("$python" scripts/inputs.py --version)
name="aosstudio-platform-tools-$version-linux-x86_64"
work=$(mktemp -d "$root/out/build.XXXXXXXX")
trap 'if (( $? == 0 )); then rm -rf -- "$work"; else printf "Build files kept at %s\n" "$work" >&2; fi' EXIT
export LC_ALL=C TZ=UTC TMPDIR="$work/tmp"
export CC=clang-21 CXX=clang++-21
export JAVA_HOME="$work/jdk"
unset JDK_JAVA_OPTIONS JAVA_TOOL_OPTIONS _JAVA_OPTIONS CLASSPATH
source_dir="$work/source"
package="$work/platform-tools"
licenses="$package/licenses"
mkdir -p "$TMPDIR" "$JAVA_HOME" "$source_dir" "$licenses" "$work/generated" \
    "$work/runtime" "$work/tools" "$root/out/dist"

"$python" scripts/inputs.py --source "$source_dir"
tar -xzf "$cache/aosstudio-jdk-21.0.13.1-2-linux-x86_64.tar.gz" -C "$JAVA_HOME"
tar -xzf "$cache/go1.25.4.linux-amd64.tar.gz" -C "$work/tools"
for archive in "$cache"/aosstudio-aosp-host-tools-*-17.0.0_r1-linux-x86_64.tar.gz; do
    tar -xzf "$archive" -C "$work/tools"
done
bootstrap="$work/tools/aosstudio-aosp-host-tools-bootstrap-17.0.0_r1-linux-x86_64/bin"
generators="$work/tools/aosstudio-aosp-host-tools-generators-17.0.0_r1-linux-x86_64/bin"
java_tools="$work/tools/aosstudio-aosp-host-tools-java-17.0.0_r1-linux-x86_64/bin"
protoc="$work/tools/protoc"
install -m 0755 "$cache/protoc-4.33.5-linux-x86_64.exe" "$protoc"
export PATH="$work/tools/go/bin:$JAVA_HOME/bin:$PATH"
export GOCACHE="$work/go-cache" GOPATH="$work/gopath" GOPROXY=off GOTOOLCHAIN=local GOWORK=off
(
    cd "$source_dir/build/soong"
    go build -trimpath -o "$work/tools/symbol_inject" ./symbol_inject/cmd
)
mkdir "$work/release"
(
    cd "$source_dir"
    "$bootstrap/release-config" --quiet --product sdk --release cp2a --variant userdebug \
        --out_dir "$work/release" --map build/release/release_config_map.textproto
)
bash scripts/resource-flags.sh "$source_dir" "$work" "$generators/aconfig" \
    "$work/release/release_config-sdk-cp2a.varmk"
printf '#define PLATFORM_TOOLS_VERSION "%s"\n' "$version" > "$work/generated/platform_tools_version.h"
bash scripts/deployagent.sh "$source_dir" "$work" "$protoc" "$java_tools/metalava" \
    "$cache/aosstudio-r8-9.5.29-agp.jar"

for tool in rustc cargo rust-std; do
    archive="$tool-1.93.0-x86_64-unknown-linux-gnu"
    tar -xJf "$cache/$archive.tar.xz" -C "$work/tools"
    bash "$work/tools/$archive/install.sh" --prefix="$work/tools/rust" --disable-ldconfig >/dev/null
done
export PATH="$work/tools/rust/bin:$PATH"
export CARGO_HOME="$work/cargo" CARGO_TARGET_DIR="$work/cargo-target"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$CC"
"$python" scripts/crates.py "$work/vendor" "$licenses"
mkdir "$CARGO_HOME"
cat > "$CARGO_HOME/config.toml" <<EOF_CARGO
[source.crates-io]
replace-with = "vendor"

[source.vendor]
directory = "$work/vendor"
EOF_CARGO
mdns="$source_dir/packages/modules/adb/client/adbmdns"
cp -- locks/Cargo.toml locks/Cargo.lock "$mdns/"
cargo build --frozen --release --jobs "$jobs" --manifest-path "$mdns/Cargo.toml"

libdir="$llvm/lib/x86_64-linux-gnu"
(
    cd "$work/runtime"
    printf 'CREATE libc++.a\nADDLIB %s/libc++.a\nADDLIB %s/libc++abi.a\nADDLIB %s/libunwind.a\nSAVE\nEND\n' \
        "$libdir" "$libdir" "$libdir" | llvm-ar-21 -M
)
cmake -S native -B "$work/native" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF "-DCMAKE_MAKE_PROGRAM=$bootstrap/ninja" \
    "-DCMAKE_CXX_FLAGS=-stdlib=libc++ -nostdinc++ -isystem \"$llvm/lib/llvm-22/include/c++/v1\"" \
    "-DCMAKE_EXE_LINKER_FLAGS=-L\"$work/runtime\" -static-libstdc++" \
    -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
    "-DAOSP_SOURCE=$source_dir" "-DAOSP_WORK=$work" "-DAOSP_JDK=$JAVA_HOME" "-DAOSP_PROTOC=$protoc"
cmake --build "$work/native" --parallel "$jobs"
cmake --install "$work/native" --prefix "$package"
for tool in adb fastboot; do
    "$work/tools/symbol_inject" -s soong_build_number -from 'SOONG BUILD NUMBER PLACEHOLDER' \
        -v aosstudio-android17-r1 -i "$package/$tool" -o "$work/$tool"
    install -m 0755 "$work/$tool" "$package/$tool"
done
bash scripts/filesystems.sh "$source_dir" "$work" "$package" "$jobs"

install -m 0644 "$source_dir/build/soong/licenses/LICENSE" "$licenses/AOSP"
for project in external/{abseil-cpp,avb/libavb,boringssl,boringssl/src,brotli,e2fsprogs,f2fs-tools,fmtlib,libusb,lz4/lib,openscreen,openscreen/third_party/abseil/src,protobuf,sqlite,sqlite/android,sqlite/dist,zstd} \
    frameworks/base/libs/androidfw packages/modules/adb system/{core,incremental_delivery,libbase,libziparchive,logging}; do
    for notice in "$source_dir/$project"/{LICENSE*,NOTICE*,COPYING*,COPYRIGHT*}; do
        [[ -f "$notice" ]] || continue
        install -m 0644 "$notice" "$licenses/${project//\//-}-${notice##*/}"
    done
done
for notice in "$work/tools/rustc-1.93.0-x86_64-unknown-linux-gnu"/*LICENSE*; do
    install -m 0644 "$notice" "$licenses/Rust-${notice##*/}"
done
for library in libc++-22-dev libc++abi-22-dev libunwind-22-dev; do
    install -m 0644 "$llvm/share/doc/$library/copyright" "$licenses/$library"
done
for library in zlib1g-dev libexpat1-dev libpng-dev libicu-dev; do
    install -m 0644 "/usr/share/doc/$library/copyright" "$licenses/$library"
done
install -m 0644 locks/inputs.json "$package/source-inputs.json"
printf 'Pkg.UserSrc=false\nPkg.Revision=%s\n' "$version" > "$package/source.properties"
"$python" scripts/package.py "$work" "$work/$name.zip"
mv -- "$work/$name.zip" "$root/out/dist/$name.zip"
printf '%s\n' "$root/out/dist/$name.zip"
