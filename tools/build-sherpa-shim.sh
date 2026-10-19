#!/bin/bash
# Cross-compile the sherpa-onnx napi shim for OpenHarmony armeabi-v7a (softfp).
#
# Runs only under Linux (WSL): the Windows OHOS SDK ships clang.exe, which
# cannot produce ELF for the OHOS target. Requires the Linux "native" package of
# the OHOS SDK (apiVersion 12 / 5.0.0.71 on this project) at $OHOS_NATIVE.
#
# Usage (from the repository root, inside WSL):
#   bash tools/build-sherpa-shim.sh
set -euo pipefail

OHOS_NATIVE=${OHOS_NATIVE:-/root/ohos-native/native}
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO/src/main/cpp/sherpa_tts_napi.cpp"
OUT_DIR="$REPO/libs/armeabi-v7a"
OUT="$OUT_DIR/libsherpa_onnx.so"

CC="$OHOS_NATIVE/llvm/bin/armv7-unknown-linux-ohos-clang++"
SYSROOT="$OHOS_NATIVE/sysroot"
INC="$SYSROOT/usr/include"
LIB="$SYSROOT/usr/lib/arm-linux-ohos"

for path in "$CC" "$SRC" "$INC/napi/native_api.h" "$INC/hilog/log.h" \
            "$LIB/libace_napi.z.so" "$LIB/libhilog_ndk.z.so"; do
  if [ ! -e "$path" ]; then
    echo "missing: $path" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"
BACKUP=""
if [ -f "$OUT" ]; then
  BACKUP="$OUT.before-$(date +%Y%m%d-%H%M%S)"
  cp "$OUT" "$BACKUP"
  echo "previous artifact kept at $BACKUP"
fi

# Link libc++ the way the shipped artifact does: DT_NEEDED libc++_shared.so is
# resolved from the system copy, which is what lets the 16 mangled std:: symbols
# (including the non-lazy _ZTI/_ZTV relocations) bind at load time. Do NOT add
# -nostdlib++ here: the shim's constructor dlopen runs after relocation, so
# typeinfo/vtable symbols would fail to resolve and the module would not load.
"$CC" \
  --target=armv7-unknown-linux-ohos \
  -mfloat-abi=softfp -mfpu=neon-vfpv4 \
  --sysroot="$SYSROOT" \
  -std=c++17 -Os -DNDEBUG -fPIC -shared \
  -I "$INC" \
  -L "$LIB" \
  -Wl,-soname,libsherpa_onnx.so \
  -o "$OUT" \
  "$SRC" \
  -lace_napi.z -lhilog_ndk.z -lc -ldl

echo "=== built ==="
ls -l "$OUT"
sha256sum "$OUT"
file "$OUT"
echo "=== ABI checks ==="
"$OHOS_NATIVE/llvm/bin/llvm-readelf" -d "$OUT" | grep -E "NEEDED|SONAME" || true
"$OHOS_NATIVE/llvm/bin/llvm-readelf" -l "$OUT" | grep -E "INTERP" || true
