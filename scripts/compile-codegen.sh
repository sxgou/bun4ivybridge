#!/bin/bash
#
# compile-codegen.sh — 手动编译 codegen 的备用脚本
#
# 当 ninja 不自动重编译 codegen 时的应急方案。
# 注意: 这是一个辅助脚本，正常情况下 build.sh 的 Phase 8 会自动处理。
# 仅在 ninja 无法正确处理 codegen 陈旧 .o 文件时使用。
#
# 使用方法:
#   bash compile-codegen.sh [构建目录]
#
# 环境变量:
#   BUILD_DIR       构建目录 (默认: /Volumes/bun-build)
#   LLVM_PREFIX     llvm 安装前缀 (默认: 自动检测 Homebrew llvm@21)
#
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-${1:-/Volumes/bun-build}}"
BUN_SRC_DIR="$BUILD_DIR/bun"
RELEASE_DIR="$BUN_SRC_DIR/build/release"

# 自动检测 Homebrew llvm@21 路径
if [[ -z "${LLVM_PREFIX:-}" ]]; then
  if [[ -x "/usr/local/opt/llvm@21/bin/clang++" ]]; then
    LLVM_PREFIX="/usr/local/opt/llvm@21"
  elif [[ -x "/opt/homebrew/opt/llvm@21/bin/clang++" ]]; then
    LLVM_PREFIX="/opt/homebrew/opt/llvm@21"
  else
    echo "[ERROR] 未找到 llvm@21，请安装: brew install llvm@21"
    exit 1
  fi
fi

CXX="$LLVM_PREFIX/bin/clang++"

# 自动检测 Xcode SDK 路径
if ! SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null); then
  echo "[ERROR] Xcode SDK 未找到，请运行: xcode-select --install"
  exit 1
fi

CXXFLAGS=(
  -march=nehalem
  -mmacosx-version-min=12
  -isysroot "$SDK_PATH"
  -DNDEBUG
  -O3
  -gdwarf-4
  -g1
  -glldb
  -fno-exceptions
  -fno-c++-static-destructors
  -fno-rtti
  -fno-omit-frame-pointer
  -mno-omit-leaf-frame-pointer
  -fvisibility=hidden
  -fvisibility-inlines-hidden
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
  -Wno-c23-extensions
  -ffunction-sections
  -fdata-sections
  -faddrsig
  -fdiagnostics-color=always
  -ferror-limit=100
  -std=c++23
  -fconstexpr-steps=6000000
  -fconstexpr-depth=54
  -fno-pic
  -fno-pie
  -Werror=return-type
  -Werror=return-stack-address
  -Werror=implicit-function-declaration
  -Werror=uninitialized
  -Werror=conditional-uninitialized
  -Werror=suspicious-memaccess
  -Werror=int-conversion
  -Werror=nonnull
  -Werror=move
  -Werror=sometimes-uninitialized
  -Wno-c++23-lambda-attributes
  -Wno-nullability-completeness
  -Wno-character-conversion
  -Werror
  -I"$BUN_SRC_DIR/packages"
  -I"$BUN_SRC_DIR/packages/bun-usockets"
  -I"$BUN_SRC_DIR/packages/bun-usockets/src"
  -I"$BUN_SRC_DIR/src/jsc/bindings"
  -I"$BUN_SRC_DIR/src/jsc/bindings/webcore"
  -I"$BUN_SRC_DIR/src/jsc/bindings/webcrypto"
  -I"$BUN_SRC_DIR/src/jsc/bindings/node/crypto"
  -I"$BUN_SRC_DIR/src/jsc/bindings/node/http"
  -I"$BUN_SRC_DIR/src/jsc/bindings/sqlite"
  -I"$BUN_SRC_DIR/src/jsc/bindings/v8"
  -I"$BUN_SRC_DIR/src/jsc/modules"
  -I"$BUN_SRC_DIR/src/js/builtins"
  -I"$BUN_SRC_DIR/src/runtime/napi"
  -I"$BUN_SRC_DIR/src/uws_sys"
  -I"$RELEASE_DIR/codegen"
  -I"$BUN_SRC_DIR/vendor"
  -I"$BUN_SRC_DIR/vendor/picohttpparser"
  -I"$BUN_SRC_DIR/vendor/zlib"
  -I"$BUN_SRC_DIR/src/jsc/bindings/libuv"
  -I"$RELEASE_DIR"
  -I"$BUN_SRC_DIR/vendor/picohttpparser"
  -I"$HOME/.bun/build-cache/nodejs-headers-26.3.0/include"
  -I"$HOME/.bun/build-cache/nodejs-headers-26.3.0/include/node"
  -I"$RELEASE_DIR/deps/zlib"
  -I"$BUN_SRC_DIR/vendor/zstd/lib"
  -I"$BUN_SRC_DIR/vendor/brotli/c/include"
  -I"$BUN_SRC_DIR/vendor/libdeflate"
  -I"$BUN_SRC_DIR/vendor/libarchive/libarchive"
  -I"$BUN_SRC_DIR/vendor/libjpeg-turbo/src"
  -I"$RELEASE_DIR/deps/libjpeg-turbo"
  -I"$BUN_SRC_DIR/vendor/libspng/spng"
  -I"$BUN_SRC_DIR/vendor/libwebp/src"
  -I"$BUN_SRC_DIR/vendor/cares/include"
  -I"$RELEASE_DIR/deps/cares"
  -I"$BUN_SRC_DIR/vendor/hdrhistogram/include"
  -I"$BUN_SRC_DIR/vendor/highway"
  -I"$BUN_SRC_DIR/vendor/highway/hwy"
  -I"$BUN_SRC_DIR/vendor/lshpack"
  -I"$BUN_SRC_DIR/vendor/lsqpack"
  -I"$BUN_SRC_DIR/vendor/mimalloc/include"
  -I"$BUN_SRC_DIR/vendor/boringssl/include"
  -I"$BUN_SRC_DIR/vendor/lsquic/include"
  -I"$HOME/.bun/build-cache/webkit-cd821fecca0d39c8-macos-baseline/include"
  -D_HAS_EXCEPTIONS=0
  -DLIBUS_USE_OPENSSL=1
  -DLIBUS_USE_BORINGSSL=1
  -DWITH_BORINGSSL=1
  -DSTATICALLY_LINKED_WITH_JavaScriptCore=1
  -DSTATICALLY_LINKED_WITH_BMALLOC=1
  -DBUILDING_WITH_CMAKE=1
  -DJSC_OBJC_API_ENABLED=0
  -DBUN_SINGLE_THREADED_PER_VM_ENTRY_SCOPE=1
  -DNAPI_EXPERIMENTAL=ON
  -DNOMINMAX
  -DIS_BUILD
  -DBUILDING_JSCONLY__
  -DREPORTED_NODEJS_VERSION=\"26.3.0\"
  -DREPORTED_NODEJS_ABI_VERSION=147
  -DREPORTED_NODEJS_V8_VERSION=\"14.6.202.34-node.20\"
  -DUSE_BUN_MIMALLOC=1
  -DNDEBUG
  -D_DARWIN_NON_CANCELABLE=1
  -DU_DISABLE_RENAMING=1
  -DLAZY_LOAD_SQLITE=1
  -Winvalid-pch
  -Xclang -include-pch -Xclang pch/root-pch.h.hxx.pch
  -Xclang -include -Xclang pch/root-pch.h.hxx
)

cd "$RELEASE_DIR"

SRC_DIR="codegen"
OUT_DIR="obj/codegen"

for src in GeneratedBindings.cpp GeneratedFakeTimersConfig.cpp GeneratedSSLConfig.cpp GeneratedSocketConfig.cpp GeneratedSocketConfigBinaryType.cpp GeneratedSocketConfigHandlers.cpp; do
  out="$OUT_DIR/${src%.cpp}.o"
  echo "Compiling $src -> $out"
  "$CXX" "${CXXFLAGS[@]}" -MMD -MT "$out" -MF "${out}.d" -c "$SRC_DIR/$src" -o "$out"
  echo "  OK"
done

echo "=== All codegen files compiled ==="
