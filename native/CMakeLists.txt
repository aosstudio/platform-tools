cmake_minimum_required(VERSION 3.22)
project(aosstudio_platform_tools LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(sources.cmake)

find_package(Threads REQUIRED)
set(ZLIB_USE_STATIC_LIBS ON)
set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
find_package(ZLIB REQUIRED)
find_package(PNG REQUIRED)
find_package(EXPAT REQUIRED)
find_package(ICU REQUIRED COMPONENTS i18n uc data)
unset(CMAKE_FIND_LIBRARY_SUFFIXES)

set(framework "${AOSP_SOURCE}/frameworks/base")
set(system "${AOSP_SOURCE}/system")
set(external "${AOSP_SOURCE}/external")
set(soong "${AOSP_SOURCE}/build/soong")
set(incremental "${system}/incremental_delivery/incfs")
set(adb_source "${AOSP_SOURCE}/packages/modules/adb")
set(openscreen "${external}/openscreen")
set(libusb "${external}/libusb")
set(lz4 "${external}/lz4/lib")
set(ssl_source "${external}/boringssl/src")
set(generated "${AOSP_WORK}/generated")

include_directories(
    "${system}/libbase/include"
    "${system}/logging/liblog/include"
    "${system}/core/libutils/include"
    "${system}/core/libutils/binder/include"
    "${system}/core/libcutils/include"
    "${system}/core/libprocessgroup/include"
    "${system}/core/libsystem/include"
    "${system}/libziparchive/include"
    "${system}/libziparchive/incfs_support/include"
    "${incremental}/util/include"
    "${framework}/libs/androidfw/include"
    "${framework}/libs/androidfw/include_pathutils"
    "${framework}/cmds/idmap2/libidmap2_policies/include"
    "${soong}/cc/libbuildversion/include"
    "${external}/fmtlib/include"
    "${external}/googletest/googletest/include"
    "${AOSP_SOURCE}/frameworks/native/include"
    "${AOSP_JDK}/include" "${AOSP_JDK}/include/linux"
    "${generated}" "${generated}/include"
)
add_compile_options(-ffunction-sections -fdata-sections)

add_library(android_host STATIC
    ${ANDROID_BASE} ${ANDROID_LOG} ${ANDROID_UTILS} ${ANDROID_UTILS_BINDER}
    ${ANDROID_CUTILS} ${ANDROID_ZIP}
    "${incremental}/util/map_ptr.cpp"
    "${soong}/cc/libbuildversion/libbuildversion.cpp"
)
target_compile_definitions(android_host PRIVATE
    _FILE_OFFSET_BITS=64 _GNU_SOURCE FMT_HEADER_ONLY STATIC_ANDROIDFW_FOR_TOOLS
    INCFS_SUPPORT_DISABLED=1 ZLIB_CONST LIBLOG_LOG_TAG=1006 SNET_EVENT_LOG_TAG=1397638484
    ANDROID_DEBUGGABLE=0
)
target_link_libraries(android_host PUBLIC Threads::Threads ZLIB::ZLIB)

file(GLOB resource_flags CONFIGURE_DEPENDS "${generated}/*.cc")
add_library(androidfw STATIC ${ANDROIDFW} ${resource_flags})
target_compile_definitions(androidfw PRIVATE FMT_HEADER_ONLY STATIC_ANDROIDFW_FOR_TOOLS ZLIB_CONST)
target_compile_options(androidfw PRIVATE
    "SHELL:-include cstdint" "SHELL:-include cstring" "SHELL:-include variant"
    -fno-exceptions -fno-rtti -Wno-deprecated-declarations
)
target_link_libraries(androidfw PUBLIC android_host PNG::PNG EXPAT::EXPAT)

set(ABSL_BUILD_TESTING OFF)
set(ABSL_PROPAGATE_CXX_STD ON)
set(ABSL_USE_GOOGLETEST_HEAD OFF)
add_subdirectory("${external}/abseil-cpp" absl-build EXCLUDE_FROM_ALL)
set(protobuf_BUILD_TESTS OFF)
set(protobuf_BUILD_EXAMPLES OFF)
set(protobuf_BUILD_LIBUPB OFF)
set(protobuf_BUILD_PROTOC_BINARIES OFF)
set(protobuf_LOCAL_DEPENDENCIES_ONLY ON)
set(protobuf_INSTALL OFF)
set(protobuf_WITH_ZLIB OFF)
add_subdirectory("${external}/protobuf" protobuf-build EXCLUDE_FROM_ALL)

add_subdirectory("${ssl_source}" boringssl-build EXCLUDE_FROM_ALL)
foreach(target IN ITEMS crypto ssl fipsmodule)
    target_compile_options(${target} PRIVATE -Wno-unused-command-line-argument)
endforeach()
add_executable(host_protoc IMPORTED)
set_target_properties(host_protoc PROPERTIES IMPORTED_LOCATION "${AOSP_PROTOC}")
add_library(adb_mdns_rust STATIC IMPORTED)
set_target_properties(adb_mdns_rust PROPERTIES
    IMPORTED_LOCATION "${AOSP_WORK}/cargo-target/release/libadbmdns_bridge.a")

add_library(adb_openscreen STATIC ${OPENSCREEN_SOURCES} ${OPENSCREEN_ABSEIL_SOURCES})
target_include_directories(adb_openscreen PRIVATE "${openscreen}" "${openscreen}/third_party/abseil/src")
target_compile_options(adb_openscreen PRIVATE -fno-strict-aliasing -fno-exceptions)
target_compile_definitions(adb_openscreen PRIVATE _DEBUG)

add_library(adb_usb SHARED
    "${libusb}/libusb/core.c"
    "${libusb}/libusb/descriptor.c"
    "${libusb}/libusb/hotplug.c"
    "${libusb}/libusb/io.c"
    "${libusb}/libusb/sync.c"
    "${libusb}/libusb/strerror.c"
    "${libusb}/libusb/os/events_posix.c"
    "${libusb}/libusb/os/linux_usbfs.c"
    "${libusb}/libusb/os/threads_posix.c"
    "${libusb}/libusb/os/linux_netlink.c"
)
set_target_properties(adb_usb PROPERTIES OUTPUT_NAME usb-1.0 SOVERSION 0)
target_include_directories(adb_usb PRIVATE "${libusb}/linux" "${libusb}/libusb" "${libusb}/libusb/os")
target_include_directories(adb_usb PUBLIC "${libusb}/include")
target_compile_definitions(adb_usb PRIVATE ENABLE_LOGGING=1)
target_link_libraries(adb_usb PRIVATE Threads::Threads)

file(GLOB brotli CONFIGURE_DEPENDS
    "${external}/brotli/c/common/*.c" "${external}/brotli/c/dec/*.c" "${external}/brotli/c/enc/*.c")
add_library(adb_brotli STATIC ${brotli})
target_include_directories(adb_brotli PUBLIC "${external}/brotli/c/include")
file(GLOB zstd CONFIGURE_DEPENDS "${external}/zstd/lib/*/*.c")
add_library(adb_zstd STATIC ${zstd})
target_include_directories(adb_zstd PUBLIC "${external}/zstd/lib" PRIVATE "${external}/zstd/lib/common")
target_compile_definitions(adb_zstd PRIVATE ZSTD_DISABLE_ASM ZSTD_HAVE_WEAK_SYMBOLS=0 ZSTD_TRACE=0)
add_library(adb_lz4 STATIC "${lz4}/lz4.c" "${lz4}/lz4hc.c" "${lz4}/lz4frame.c" "${lz4}/xxhash.c")
target_include_directories(adb_lz4 PUBLIC "${lz4}")

set(proto_out "${CMAKE_CURRENT_BINARY_DIR}/adb-protos")
file(MAKE_DIRECTORY "${proto_out}")
foreach(proto IN ITEMS adb_host adb_known_hosts app_processes key_type pairing fastdeploy/proto/ApkEntry)
    set(proto_root "${adb_source}/proto")
    if(proto MATCHES "^fastdeploy/")
        set(proto_root "${adb_source}")
    endif()
    set(proto_format "")
    if(proto MATCHES "^(key_type|pairing|fastdeploy/)")
        set(proto_format "lite:")
    endif()
    add_custom_command(
        OUTPUT "${proto_out}/${proto}.pb.cc" "${proto_out}/${proto}.pb.h"
        COMMAND host_protoc "--proto_path=${proto_root}" "--cpp_out=${proto_format}${proto_out}"
            "${proto_root}/${proto}.proto"
        DEPENDS "${proto_root}/${proto}.proto"
        VERBATIM
    )
    list(APPEND proto_sources "${proto_out}/${proto}.pb.cc")
endforeach()
add_library(adb_protos STATIC ${proto_sources})
target_include_directories(adb_protos PUBLIC "${proto_out}")
target_link_libraries(adb_protos PUBLIC protobuf::libprotobuf)
add_executable(adb ${ADB_SOURCES}
    "${system}/core/diagnose_usb/diagnose_usb.cpp"
    "${system}/core/libcrypto_utils/android_pubkey.cpp")
target_include_directories(adb PRIVATE
    "${adb_source}"
    "${adb_source}/crypto/include"
    "${adb_source}/pairing_auth/include"
    "${adb_source}/pairing_connection/include"
    "${adb_source}/tls/include"
    "${openscreen}"
    "${system}/core/diagnose_usb/include"
    "${system}/core/libcrypto_utils/include"
)
target_compile_definitions(adb PRIVATE
    ADB_HOST=1 ANDROID_BASE_UNIQUE_FD_DISABLE_IMPLICIT_CONVERSION=1
    _FILE_OFFSET_BITS=64 _GNU_SOURCE FMT_HEADER_ONLY STATIC_ANDROIDFW_FOR_TOOLS
    INCFS_SUPPORT_DISABLED=1 ZLIB_CONST LIBLOG_LOG_TAG=1006 SNET_EVENT_LOG_TAG=1397638484
    ANDROID_DEBUGGABLE=0
)
target_compile_options(adb PRIVATE -fno-exceptions)
target_link_options(adb PRIVATE -Wl,--gc-sections)
target_link_libraries(adb PRIVATE
    adb_protos adb_openscreen adb_mdns_rust adb_usb adb_brotli adb_zstd adb_lz4
    androidfw ssl crypto Threads::Threads dl m resolv
)
set_target_properties(adb PROPERTIES INSTALL_RPATH "$ORIGIN/lib64")

set(sparse_root "${system}/core/libsparse")
add_library(sparse STATIC
    "${sparse_root}/backed_block.cpp"
    "${sparse_root}/output_file.cpp"
    "${sparse_root}/sparse.cpp"
    "${sparse_root}/sparse_crc32.cpp"
    "${sparse_root}/sparse_err.cpp"
    "${sparse_root}/sparse_read.cpp"
)
target_include_directories(sparse PUBLIC "${sparse_root}/include")
target_link_libraries(sparse PUBLIC android_host)
add_executable(img2simg "${sparse_root}/img2simg.cpp")
target_link_libraries(img2simg PRIVATE sparse)
add_executable(fastboot ${FASTBOOT_SOURCES})
target_include_directories(fastboot PRIVATE
    "${system}/core/fastboot"
    "${system}/core/diagnose_usb/include"
    "${system}/core/libcrypto_utils/include"
    "${system}/fs/fs_mgr/liblp/include"
    "${system}/fs/fs_mgr/libstorage_literals"
    "${system}/extras/ext4_utils/include"
    "${system}/tools/mkbootimg/include"
    "${system}/tools/mkbootimg/include/bootimg"
    "${external}/avb"
)
target_compile_definitions(fastboot PRIVATE _FILE_OFFSET_BITS=64 _GNU_SOURCE FMT_HEADER_ONLY ZLIB_CONST)
foreach(source IN LISTS FASTBOOT_SOURCES)
    if(source MATCHES "/system/core/fastboot/")
        set_property(SOURCE "${source}" APPEND PROPERTY COMPILE_DEFINITIONS
            ANDROID_BASE_UNIQUE_FD_DISABLE_IMPLICIT_CONVERSION)
    endif()
endforeach()
target_compile_options(fastboot PRIVATE -fno-strict-aliasing)
target_link_options(fastboot PRIVATE -Wl,--gc-sections)
target_link_libraries(fastboot PRIVATE sparse adb_lz4 crypto dl)

add_executable(etc1tool
    "${AOSP_SOURCE}/development/tools/etc1tool/etc1tool.cpp"
    "${AOSP_SOURCE}/frameworks/native/opengl/libs/ETC1/etc1.cpp"
)
target_include_directories(etc1tool PRIVATE "${AOSP_SOURCE}/frameworks/native/opengl/include")
target_link_libraries(etc1tool PRIVATE PNG::PNG EXPAT::EXPAT ZLIB::ZLIB)
add_executable(hprof-conv "${AOSP_SOURCE}/dalvik/tools/hprof-conv/HprofConv.c")

set(sqlite_dist "${external}/sqlite/dist/sqlite-autoconf-3500600")
set(sqlite_android "${external}/sqlite/android")
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/sqlite-flags.txt" sqlite_flags)
add_executable(sqlite3
    "${sqlite_dist}/sqlite3.c" "${sqlite_dist}/shell.c"
    "${sqlite_android}/PhoneNumberUtils.cpp"
    "${sqlite_android}/OldPhoneNumberUtils.cpp"
    "${sqlite_android}/sqlite3_android.cpp"
)
set_source_files_properties("${sqlite_dist}/shell.c" PROPERTIES COMPILE_DEFINITIONS NO_ANDROID_FUNCS=1)
set_source_files_properties("${sqlite_dist}/sqlite3.c" PROPERTIES
    COMPILE_OPTIONS -Wno-error=incompatible-pointer-types-discards-qualifiers)
target_compile_options(sqlite3 PRIVATE ${sqlite_flags} -Qunused-arguments)
target_compile_definitions(sqlite3 PRIVATE SQLITE_ENABLE_ICU)
target_include_directories(sqlite3 PRIVATE "${sqlite_dist}" "${sqlite_android}")
target_link_libraries(sqlite3 PRIVATE android_host ICU::i18n ICU::uc ICU::data "-Wl,-lstdc++" dl m)
install(TARGETS adb fastboot etc1tool hprof-conv sqlite3 RUNTIME DESTINATION .)
install(TARGETS img2simg RUNTIME DESTINATION libexec)
install(TARGETS adb_usb LIBRARY DESTINATION lib64 NAMELINK_SKIP)
