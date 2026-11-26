#!/usr/bin/env bash
# Builds a self-contained FFmpeg (audio only + LAME MP3) for Android arm64 and
# installs it as android/app/src/main/jniLibs/arm64-v8a/libffmpeg.so.
# The APK then carries FFmpeg inside it: nothing to download or install on the
# phone. Android extracts it to nativeLibraryDir (useLegacyPackaging = true),
# the only app folder Android 10+ allows executing programs from.
#
# Usage: android_native/build_ffmpeg_android.sh [output.so]
# Needs: ANDROID_NDK_HOME or ANDROID_NDK_LATEST_HOME (GitHub runners have it).
set -euo pipefail

FFMPEG_VER="${FFMPEG_VER:-7.1.1}"
LAME_VER="3.100"
API=24
OUT="${1:-android/app/src/main/jniLibs/arm64-v8a/libffmpeg.so}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT";; esac
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:-}}}"
if [ -z "$NDK" ] || [ ! -d "$NDK/toolchains/llvm/prebuilt" ]; then
  echo "::error::Android NDK not found (set ANDROID_NDK_HOME)"; exit 1
fi
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TC/bin/aarch64-linux-android${API}-clang"
WORK="${FFMPEG_WORK:-${RUNNER_TEMP:-/tmp}/ffmpeg-android}"
PREFIX="$WORK/prefix"
JOBS="$(nproc 2>/dev/null || echo 2)"
mkdir -p "$WORK" "$PREFIX"
cd "$WORK"

fetch() { # fetch <file> <url...>
  local f="$1"; shift
  [ -s "$f" ] && return 0
  for u in "$@"; do
    echo "Downloading $u"
    if curl -fL --retry 4 --retry-delay 3 --connect-timeout 30 -o "$f.part" "$u"; then
      mv "$f.part" "$f"; return 0
    fi
  done
  echo "::error::could not download $f"; exit 1
}

# ---- LAME (MP3 encoder), static
fetch "lame-$LAME_VER.tar.gz" \
  "https://deb.debian.org/debian/pool/main/l/lame/lame_$LAME_VER.orig.tar.gz" \
  "https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz"
if [ ! -f "$PREFIX/lib/libmp3lame.a" ]; then
  rm -rf "lame-$LAME_VER"; tar xzf "lame-$LAME_VER.tar.gz"
  cd "lame-$LAME_VER"
  # 3.100 lists a symbol that does not exist; harmless for static, fix anyway
  sed -i '/lame_init_old/d' include/libmp3lame.sym || true
  ./configure --host=aarch64-linux-android --prefix="$PREFIX" \
    --enable-static --disable-shared --disable-frontend --disable-decoder \
    --with-pic CC="$CC" AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib" \
    CFLAGS="-O2 -fPIC" >/dev/null
  make -j"$JOBS" >/dev/null
  make install >/dev/null
  cd "$WORK"
fi

# ---- FFmpeg, only system libs (libc/libm/libdl) linked dynamically
fetch "ffmpeg-$FFMPEG_VER.tar.xz" \
  "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" \
  "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$FFMPEG_VER.tar.gz"
rm -rf "ffmpeg-$FFMPEG_VER"; mkdir "ffmpeg-$FFMPEG_VER"
tar xf "ffmpeg-$FFMPEG_VER.tar.xz" -C "ffmpeg-$FFMPEG_VER" --strip-components=1
cd "ffmpeg-$FFMPEG_VER"
./configure \
  --prefix="$PREFIX" --enable-cross-compile --target-os=android \
  --arch=aarch64 --cpu=armv8-a --cc="$CC" --cxx="${CC}++" \
  --nm="$TC/bin/llvm-nm" --ar="$TC/bin/llvm-ar" --ranlib="$TC/bin/llvm-ranlib" \
  --strip="$TC/bin/llvm-strip" --sysroot="$TC/sysroot" \
  --extra-cflags="-O2 -fPIC -I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
  --enable-pic --enable-static --disable-shared --pkg-config=false \
  --disable-autodetect --disable-doc --disable-debug --disable-network \
  --disable-ffplay --disable-ffprobe --disable-avdevice --disable-postproc \
  --disable-everything \
  --enable-libmp3lame \
  --enable-protocol=file,pipe \
  --enable-demuxer=wav,mp3,aac,mov,ogg,flac,matroska,w64,aiff,pcm_s16le \
  --enable-decoder=pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,pcm_f64le,pcm_u8,mp3,mp3float,aac,flac,vorbis,opus,alac \
  --enable-encoder=libmp3lame,pcm_s16le,pcm_s24le,aac,flac \
  --enable-muxer=mp3,wav,null,ipod,mp4,adts,flac,ogg \
  --enable-parser=mpegaudio,aac,flac,vorbis,opus \
  --enable-filter=silenceremove,areverse,atrim,asetpts,afade,volume,alimiter,volumedetect,aresample,aformat,anull,loudnorm,acompressor,highpass,lowpass,equalizer,dynaudnorm,apad,amix,acrossfade,null,format,copy,abuffer,abuffersink \
  --enable-swresample \
  >/dev/null
make -j"$JOBS" ffmpeg >/dev/null
"$TC/bin/llvm-strip" --strip-unneeded ffmpeg
mkdir -p "$(dirname "$OUT")"
cp -f ffmpeg "$OUT"
chmod 755 "$OUT"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
"$TC/bin/llvm-readelf" -d "$OUT" | grep NEEDED || true
