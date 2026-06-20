# bun4ivybridge: Build Bun from Source on Ivy Bridge CPUs

在 Ivy Bridge CPU 上从源码编译 Bun。

Build Bun from source on Ivy Bridge and older x86-64 CPUs, solving SIGILL crashes caused by AVX2/BMI2 instructions in prebuilt binaries.

**Verified** / **已验证**: 2026-06-20, successfully compiled and ran bun 1.4.0 on Intel Xeon E5-2696 v2.

---

## Environment / 适用环境

- **CPU**: Intel Xeon E5-2696 v2 (Ivy Bridge, 2013) — no AVX2/BMI2/FMA support
- **OS**: macOS 12+ (Monterey, verified on 12.7.6)
- **Compiler**: LLVM/Clang 21 (`brew install llvm@21`)
- **Prebuilt binary available**: See [Releases](https://github.com/sxgou/bun4ivybridge/releases)

> ⚠️ **Compatibility / 兼容性说明**
> - `--baseline=true` → `-march=nehalem` is theoretically compatible with all x86-64 CPUs
> - **Only verified on macOS 12+** — Linux/Windows untested
> - WebKit version may vary across bun commits
> - WebKit fallback and ldflags fixes in build.sh are designed around known issues; may not be needed in other environments

## Background / 问题背景

Bun's prebuilt macOS binaries target Haswell+ (2014+) CPUs using AVX2/BMI2 instructions. On Ivy Bridge CPUs they immediately crash with SIGILL (exit code 132).

**Solution**: Build from source with `--baseline=true` (generates `-march=nehalem`), producing instructions compatible with all x86-64 CPUs.

A **prebuilt macOS x86-64 binary** (true baseline, compatible with all Intel Macs) is available for direct download — check the [Releases](https://github.com/sxgou/bun4ivybridge/releases) page.

## Directory Structure / 目录结构

```
bun4ivybridge/
├── DESIGN.md                          # Design doc / 设计文档
├── README.md                          # This file / 本文件
├── bootstrap/
│   └── GET_BOOTSTRAP_BUN.md           # Getting bootstrap bun / 获取 bootstrap
├── config/
│   └── cmake-args.sh                  # [Reference] cmake args (affects deps only)
├── patches/
│   ├── ProcessObjectInternals.ts      # Fix const enum leak at runtime
│   └── scripts/
│       ├── build/configure.ts         # globSync → readdirSync patch
│       └── glob-sources.ts            # globSync → simpleGlobSync patch
└── scripts/
    ├── build.sh                       # Semi-automated build script (recommended)
    └── compile-codegen.sh             # Manual codegen compilation (backup)
```

## Quick Start / 快速开始

```bash
cd /path/to/bun4ivybridge

# Build default commit 6ef59777b (bun v1.4.0)
bash scripts/build.sh

# Custom build directory (avoid RAM disk)
# BUILD_DIR=/tmp/bun-build bash scripts/build.sh
```

The script guides you through 9 build phases.

## Manual Build Steps / 手动编译步骤

### 1. Prepare Environment / 准备构建环境

```bash
brew install llvm@21 cmake ninja rust
curl https://sh.rustup.rs -sSf | sh
```

Ensure bun >= 1.1.20 is available (for running `build.ts` with globSync patches).

### 2. Prepare Build Directory / 准备构建目录

```bash
# Optional: RAM disk (faster, reduces SSD wear)
diskutil erasevolume APFS "bun-build" $(hdiutil attach -nomount ram://134217728)

# Or build on filesystem
mkdir -p /Volumes/bun-build
```

### 3. Clone Source / 克隆源码

```bash
cd /Volumes/bun-build
git clone https://github.com/oven-sh/bun.git
cd bun
git checkout 6ef59777b
```

### 4. Apply Patches / 应用补丁

```bash
cp /path/to/bun4ivybridge/patches/ProcessObjectInternals.ts \
  /Volumes/bun-build/bun/src/js/builtins/ProcessObjectInternals.ts

cp /path/to/bun4ivybridge/patches/scripts/build/configure.ts \
  /Volumes/bun-build/bun/scripts/build/configure.ts

cp /path/to/bun4ivybridge/patches/scripts/glob-sources.ts \
  /Volumes/bun-build/bun/scripts/glob-sources.ts
```

### 5. Generate build.ninja / 生成构建文件

```bash
cd /Volumes/bun-build/bun

# Key step: --baseline=true ensures -march=nehalem
bun scripts/build.ts --profile=release --baseline=true --configure-only
```

Verify the correct march:
```bash
grep march build/release/build.ninja | head -3
# Expected: -march=nehalem
```

### 6. Fix Known Issues / 修复已知问题

```bash
# Issue 1: macOS baseline WebKit may not exist
# If WebKit download 404s, manually download standard version:
# curl -L -o /tmp/webkit.tar.gz https://github.com/oven-sh/WebKit/releases/download/autobuild-<HASH>/bun-webkit-macos-amd64.tar.gz
# mkdir -p ~/.bun/build-cache/webkit-<HASH>-macos-baseline
# tar -xzf /tmp/webkit.tar.gz -C ~/.bun/build-cache/webkit-<HASH>-macos-baseline
# echo "<HASH>-baseline" > ~/.bun/build-cache/webkit-<HASH>-macos-baseline/.identity

# Issue 2: ldflags missing llvm@21 lib path
cd /Volumes/bun-build/bun/build/release
if ! grep -q '\-L/usr/local/opt/llvm@21/lib' build.ninja; then
  sed -i '' 's|-Wl,-ld_new |-Wl,-ld_new -L/usr/local/opt/llvm@21/lib |g' build.ninja
fi
```

### 7. Build / 编译

```bash
cd /Volumes/bun-build/bun/build/release
ninja -j$(sysctl -n hw.ncpu) bun-profile
```

### 8. Verify / 验证

```bash
./bun-profile --version
# Expected: 1.4.0

./bun-profile -e 'console.log(process.stderr.fd)'
# Expected: 2
```

### 9. Install / 安装

```bash
cp ./bun-profile ~/.bun/bin/bun
```

## Known Issues & Solutions / 遇到的问题及解决办法

### Issue 1: SIGILL — Prebuilt binary uses AVX2/BMI2

**Symptom**: Prebuilt `bun` exits immediately with code 132.

**Cause**: Bun's macOS build targets Haswell+ (2014+) using AVX2/BMI2 instructions.

**Solution**: Build from source with `--baseline=true` → `-march=nehalem`.

### Issue 2: `BunProcessStdinFdType is not defined` — const enum leak

**Symptom**: `ReferenceError: $BunProcessStdinFdType is not defined` when accessing `process.stderr`.

**Cause**: Bun's builtin transpiler doesn't fully inline TypeScript `const enum`.

**Solution**: See patch `patches/ProcessObjectInternals.ts`.

### Issue 3: macOS baseline WebKit prebuilt not found

**Symptom**: ninja gets HTTP 404 when downloading WebKit.

**Cause**: Some bun commits don't have a macOS baseline variant in GitHub Releases.

**Solution**: build.sh automatically falls back to standard WebKit (verified working on Ivy Bridge).

### Issue 4: `library not found for -ld_new` at link time

**Symptom**: Linker error `ld: library not found for -ld_new`.

**Cause**: build.ts doesn't auto-detect llvm@21's lib path.

**Solution**: Add `-L/usr/local/opt/llvm@21/lib` to ldflags (Intel) or `/opt/homebrew/opt/llvm@21/lib` (Apple Silicon). build.sh autofixes this.

### Issue 5: Bootstrap bun v1.1.20 lacks globSync API

**Symptom**: `SyntaxError: Export named 'globSync' not found in module 'fs'` when running `build.ts`.

**Cause**: v1.1.20's `node:fs` is missing `globSync` used by newer bun source.

**Solution**: Two patches (`patches/scripts/build/configure.ts`, `patches/scripts/glob-sources.ts`) replace `globSync` with `readdirSync` + `statSync`.

### Issue 6: Stale codegen .o files

**Symptom**: After patching, recompilation doesn't take effect.

**Cause**: `.o` files are older than their `.cpp` sources; ninja doesn't auto-rebuild.

**Solution**: build.sh Phase 8 auto-detects and deletes stale `.o` files.

## Patch Reference / 补丁说明

### `patches/ProcessObjectInternals.ts`

**Purpose**: Replaces `const enum BunProcessStdinFdType` with numeric literals to avoid runtime reference errors.

**Install**:
```bash
cp patches/ProcessObjectInternals.ts /Volumes/bun-build/bun/src/js/builtins/ProcessObjectInternals.ts
```

### `patches/scripts/`

Two patches that replace `globSync` with `readdirSync` + `statSync`, enabling bun v1.1.x to run the v1.4.0 build configuration:

- `patches/scripts/build/configure.ts` — simple glob for `*.ts` and `deps/*.ts`
- `patches/scripts/glob-sources.ts` — full implementation supporting `**`, `*.ext`, `{a,b,c}` brace expansion

### `scripts/compile-codegen.sh`

**Purpose**: Manual codegen recompilation when ninja's codegen rules are stubs (legacy bun configure).

**Usage**:
```bash
cd /Volumes/bun-build/bun/build/release
bash /path/to/bun4ivybridge/scripts/compile-codegen.sh
```

## Prebuilt Binary / 预编译二进制

A **true baseline** macOS x86-64 binary (compiled with `-march=nehalem`) is available on the [Releases](https://github.com/sxgou/bun4ivybridge/releases) page. It works on ALL Intel Macs from Nehalem (2008) onwards — no AVX2/BMI2 required.
