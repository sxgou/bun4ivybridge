#!/bin/bash
# cmake-args.sh — bun4ivybridge cmake arguments reference
#
# Note: This file is for reference only.
# bun's primary build system does NOT use cmake — it uses scripts/build.ts to
# generate build.ninja. cmake is only used for compiling some dependencies
# (libarchive, libuv, etc.).
#
# The correct way to set -march is:
#   bun scripts/build.ts --profile=release --baseline=true --configure-only
# This generates -march=nehalem in build.ninja (via flags.ts rules).
#
# cmake's -DCMAKE_CXX_FLAGS does NOT affect the main build's march.
#
# Verified environment:
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

# If llvm@21 path differs, find it with:
#   brew --prefix llvm@21  # -> /usr/local/opt/llvm@21
