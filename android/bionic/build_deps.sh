#!/usr/bin/env bash
# Adapted from Bloodborne-Android build_bionic_deps.sh, 2e472653.
# Third-party libraries for the Bionic (Android NDK) build, into .local-deps/android/bionic-prefix.
# Pinned Bionic dependencies; fmt 12.1.0 supports the NDK r29 C++23 toolchain.
# Sources are downloaded to .local-deps/android/bionic-src, builds go to bionic-build.
# Host-side prerequisites: curl, tar, cmake, ninja, make, python3.
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
root=$PWD/.local-deps/android
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH CMAKE_PREFIX_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
ndk=${TLOU_NDK:-${ANDROID_NDK_HOME:-$root/sdk/ndk/29.0.14206865}}
api=${TLOU_ANDROID_API:-30}
prefix=$root/bionic-prefix src=$root/bionic-src bld=$root/bionic-build
[[ -f $ndk/build/cmake/android.toolchain.cmake ]] || { echo "No NDK: $ndk" >&2; exit 1; }
. "$(dirname -- "$0")/ndk_prebuilt.sh"
prebuilt=$(ndk_prebuilt "$ndk") || { echo "No NDK host prebuilt under $ndk" >&2; exit 1; }
mkdir -p "$prefix" "$src" "$bld"
J=${TLOU_JOBS:-2}
run() { "$@"; }

download_one() { # url dest -> 0 on success, resuming a partial file when possible
    local url=$1 dest=$2
    # Resume first, so a dropped mobile link does not restart a large archive.
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --max-time 1800 \
        --speed-limit 1024 --speed-time 60 -C - -o "$dest" "$url" 2>/dev/null && return 0
    # Resume can fail outright when a mirror ignores Range; retry from scratch.
    rm -f -- "$dest"
    curl -fL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --max-time 1800 \
        --speed-limit 1024 --speed-time 60 -o "$dest" "$url" 2>/dev/null
}

fetch() { # name url [fallback-url...]
    local name=$1 dir=$src/$1 tar=$src/$1.tar
    shift
    [[ -d $dir ]] && return 0
    rm -rf -- "$dir.tmp"

    local candidates=()
    local url
    for url in "$@"; do
        candidates+=("$url")
        # GitHub releases and archives are also reachable through the documented
        # proxy endpoints when the direct route stalls. Kept opt-in via TLOU_DL_PROXY
        # first, then a short list of public mirrors, so CI keeps using the direct URL.
        case $url in
            https://github.com/*)
                [[ -n ${TLOU_DL_PROXY:-} ]] && candidates+=("${TLOU_DL_PROXY%/}/$url")
                candidates+=("https://ghfast.top/$url" "https://ghproxy.net/$url" "https://gh-proxy.com/$url")
                ;;
        esac
    done

    local candidate
    for candidate in "${candidates[@]}"; do
        echo "fetch $name <- $candidate"
        if download_one "$candidate" "$tar"; then
            # A truncated archive still passes curl's exit code on some mirrors.
            if tar -tf "$tar" >/dev/null 2>&1; then
                mkdir -p "$dir.tmp" \
                    && tar --no-same-owner -xf "$tar" -C "$dir.tmp" --strip-components=1 \
                    && mv "$dir.tmp" "$dir" && rm -f -- "$tar" && return 0
            fi
            echo "  archive from $candidate is incomplete; trying the next source" >&2
        fi
        rm -f -- "$tar"
    done
    echo "fetch $name failed from every source" >&2
    return 1
}
cm() { # name source-dir extra cmake args...
    local name=$1 sdir=$2; shift 2
    [[ -f $prefix/.done-$name ]] && return
    echo "==> configuring $name"
    cmake -S "$sdir" -B "$bld/$name" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$api -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_FIND_ROOT_PATH="$prefix" "$@" >"$bld/$name.configure.log" 2>&1 \
        || { echo "cmake configure failed for $name:" >&2; tail -30 "$bld/$name.configure.log" >&2; exit 1; }
    echo "==> building $name"
    run cmake --build "$bld/$name" -j "$J" >"$bld/$name.log" 2>&1 || { tail -30 "$bld/$name.log" >&2; exit 1; }
    cmake --install "$bld/$name" >/dev/null
    touch "$prefix/.done-$name"
    echo "==> installed $name"
}

fetch fmt-12.1.0 https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz
fetch zycore-1.5.2 https://github.com/zyantific/zycore-c/archive/refs/tags/v1.5.2.tar.gz
fetch zydis-4.1.1 https://github.com/zyantific/zydis/archive/refs/tags/v4.1.1.tar.gz
fetch xxhash-0.8.3 https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz
fetch miniz-3.1.2 https://github.com/richgel999/miniz/archive/refs/tags/3.1.2.tar.gz
fetch Vulkan-Headers-1.4.363 https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.363.tar.gz
fetch SPIRV-Headers-1.4.309 https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-1.4.309.0.tar.gz
# ffmpeg.org and the GitHub mirror were both reachable from the device; either may
# stall, so hand fetch both instead of preferring one.
fetch ffmpeg-7.1.5 https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n7.1.5.tar.gz

# Header-only: vulkan-hpp (the NDK ships Vulkan 1.3.275 C headers without it) and SPIR-V.
cm vulkan-headers "$src/Vulkan-Headers-1.4.363"
cm spirv-headers "$src/SPIRV-Headers-1.4.309"
cm fmt-12.1.0 "$src/fmt-12.1.0" -DFMT_TEST=OFF -DFMT_DOC=OFF
cm zycore "$src/zycore-1.5.2" -DBUILD_SHARED_LIBS=OFF
# The release tarball lacks the zycore submodule: build against the same Zycore source tree.
[[ -f $src/zydis-4.1.1/dependencies/zycore/CMakeLists.txt ]] || cp -a "$src/zycore-1.5.2/." "$src/zydis-4.1.1/dependencies/zycore/"
cm zydis "$src/zydis-4.1.1" -DBUILD_SHARED_LIBS=OFF -DZYDIS_BUILD_EXAMPLES=OFF -DZYDIS_BUILD_TOOLS=OFF \
    -DZYDIS_BUILD_DOXYGEN=OFF
cm xxhash "$src/xxhash-0.8.3/cmake_unofficial" -DBUILD_SHARED_LIBS=OFF -DXXHASH_BUILD_XXHSUM=OFF
cm miniz "$src/miniz-3.1.2" -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DINSTALL_PROJECT=ON
# FFmpeg (avplayer/videodec): static, PIC, no programs, only built-in codecs/demuxers.
if [[ ! -f $prefix/.done-ffmpeg ]]; then
    tc=$prebuilt
    cc="$tc/bin/aarch64-linux-android$api-clang"
    [[ -x $cc ]] || { echo "ffmpeg: missing cross compiler $cc" >&2; exit 1; }
    [[ -x $src/ffmpeg-7.1.5/configure ]] || { echo "ffmpeg: missing configure script" >&2; exit 1; }
    echo "==> configuring ffmpeg (cc=$(basename "$cc"))"
    mkdir -p "$bld/ffmpeg" && pushd "$bld/ffmpeg" >/dev/null
    if ! "$src/ffmpeg-7.1.5/configure" --prefix="$prefix" --enable-cross-compile --target-os=android --arch=aarch64 \
        --cc="$cc" --cxx="$tc/bin/aarch64-linux-android$api-clang++" \
        --ar="$tc/bin/llvm-ar" --ranlib="$tc/bin/llvm-ranlib" --strip="$tc/bin/llvm-strip" --nm="$tc/bin/llvm-nm" \
        --enable-static --disable-shared --enable-pic --disable-programs --disable-doc --disable-debug \
        --disable-avdevice --disable-avfilter --disable-network --disable-autodetect --disable-mediacodec --disable-jni \
        >"$bld/ffmpeg-configure.log" 2>&1; then
        echo "ffmpeg configure exited non-zero; last lines of $bld/ffmpeg-configure.log:" >&2
        tail -40 "$bld/ffmpeg-configure.log" >&2
        # configure creates the log lazily; an empty log with a fast failure means it
        # never started, so say so instead of printing nothing.
        [[ -s $bld/ffmpeg-configure.log ]] || echo "(configure produced no output at all)" >&2
        exit 1
    fi
    echo "==> building ffmpeg"
    run make -j"$J" >"$bld/ffmpeg.log" 2>&1 || { tail -40 "$bld/ffmpeg.log" >&2; exit 1; }
    make install >/dev/null
    # configure's Android target links libandroid/libmediandk for MediaCodec/JNI, both disabled here.
    sed -i 's/ -landroid -lmediandk//' "$prefix"/lib/pkgconfig/libavutil.pc
    popd >/dev/null
    touch "$prefix/.done-ffmpeg"
    echo "==> installed ffmpeg"
fi
echo "Bionic deps in $prefix"
