# Build Platform Tools

The Linux x86-64 build uses Python 3.14, GNU Make, Bash, curl, tar, unzip, xz, xxd, CMake, Clang 21, LLVM 21 and the libc++ 22 development libraries. It also uses the development libraries for zlib, libpng, Expat and ICU. Verification uses `blkid` from util-linux.

```sh
make build
make verify
```

`make fetch` prepares the locked inputs separately. Downloads, source extraction, intermediate builds and ZIP output use the repository's `out/` directory. Set `BUILD_JOBS` to adjust build parallelism. Set `LLVM_ROOT` to the `usr` directory of separately extracted libc++ 22, libc++abi 22 and libunwind 22 development packages when those packages are installed outside the system prefix.

The [input lock](../locks/inputs.json) records the public source revisions, archive digests, upstream toolchain and published AOSStudio dependencies. The build uses AOSStudio Host Tools for Ninja, the AOSP resource flag configuration and Metalava. It generates the Fast Deploy helper with the AOSStudio JDK, the pinned `android.util.Log` API signature, Protobuf and D8 from the published AOSStudio R8 release. A standalone Cargo build compiles ADB's mDNS bridge from the pinned sources and crate lock. Review new Nightly assets before updating their pinned digests.

The output is `out/dist/aosstudio-platform-tools-37.0.0-linux-x86_64.zip`. Extract it into an SDK root to put the utilities under `platform-tools/`. The ZIP carries upstream notices and exact source locations. The Linux build links libusb dynamically and locates it next to the tools under `lib64/`. The host provides glibc and the GNU C++ runtime used by SQLite's ICU dependency.

The F2FS entry points support Fastboot's `-S` mode through two separate programs in `libexec/`. The GPL formatter writes a filesystem image, then AOSP's `img2simg -s` converts its allocated ranges into Android sparse format. The scripts in this repository and the source locations in the input lock provide the build instructions and exact corresponding upstream source for F2FS, e2fsprogs and libusb.

The package verification starts and stops ADB on a fresh local socket, checks Fastboot's version, formats disposable ext4 and F2FS images, checks sparse F2FS output, exercises SQLite Unicode support and converts ETC1 and HPROF samples.
