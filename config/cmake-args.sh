#!/bin/bash
# cmake-args.sh — bun4ivybridge cmake 参数参考
#
# 注意: 此文件仅作参考用途。
# bun 的主构建系统不使用 cmake —— 它使用 scripts/build.ts 生成 build.ninja。
# cmake 仅用于编译部分依赖库（如 libarchive、libuv 等）。
#
# 设置 -march 的正确方式是:
#   bun scripts/build.ts --profile=release --baseline=true --configure-only
# 这会在 build.ninja 中生成 -march=nehalem（通过 flags.ts 中的规则）。
#
# cmake 的 -DCMAKE_CXX_FLAGS 不影响主构建代码的 march。
#
# 验证环境:
#   CPU: Intel Xeon E5-2696 v2 (Ivy Bridge)
#   OS:  macOS 12+ (Monterey)
#   CXX: llvm@21 (/usr/local/opt/llvm@21/bin/clang++)

CMAKE_ARGS=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CXX_FLAGS="-march=nehalem"
  -DCMAKE_C_FLAGS="-march=nehalem"
  -DCMAKE_CXX_COMPILER="/usr/local/opt/llvm@21/bin/clang++"
  -DCMAKE_C_COMPILER="/usr/local/opt/llvm@21/bin/clang"
)

# 如果 llvm@21 路径不同，使用以下命令查找:
#   brew --prefix llvm@21  # → /usr/local/opt/llvm@21
