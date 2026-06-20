# bun4ivybridge: Build Bun from Source on Ivy Bridge CPUs

Build Bun from source on Ivy Bridge and older x86-64 CPUs, solving SIGILL crashes caused by AVX2/BMI2 instructions in prebuilt binaries.

**Verified**: 2026-06-20, successfully compiled and ran bun 1.4.0 on Intel Xeon E5-2696 v2.

---

## Environment Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| **CPU** | Intel x86-64 (Nehalem+, e.g. Ivy Bridge) | Must support at least SSE4.2. No AVX2/BMI2 required. |
| **OS** | macOS 12+ (Monterey, verified 12.7.6) | Other OS untested. Linux may work with toolchain adjustments. |
| **Xcode CLI Tools** | Any version with macOS 12+ SDK | Install: `xcode-select --install`. Required for `xcrun`, SDK headers, and linker. |
| **Homebrew** | Latest | Required to install toolchain packages. Install: https://brew.sh |
| **LLVM/Clang** | llvm@21 | `brew install llvm@21`. Provides `clang++` for C++23 compilation. |
| **CMake** | >= 3.20 | `brew install cmake`. Used for dependency builds. |
| **Ninja** | >= 1.10 | `brew install ninja`. Build system executor. |
| **Rust** | 1.94.0 (pinned in `rust-toolchain.toml`) | `brew install rust` + `curl https://sh.rustup.rs -sSf \| sh`. Required for native extensions. |
| **Bun (bootstrap)** | >= 1.1.20, < 1.2.0 | Used to run `build.ts` configure step. See `bootstrap/GET_BOOTSTRAP_BUN.md`. |
| **Disk space** | >= 40 GB free | Build directory default is RAM disk (64 GB). Filesystem fallback requires ~15 GB. |
| **RAM** | >= 16 GB (32 GB+ recommended) | Linking is memory-intensive. |

### Quick Install All Dependencies

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Toolchain packages
brew bundle --file=config/Brewfile

# 4. Rust
curl https://sh.rustup.rs -sSf | sh

# 5. Bootstrap bun (see bootstrap/GET_BOOTSTRAP_BUN.md)
```

> ⚠️ **Compatibility Notes**
> - `--baseline=true` → `-march=nehalem` is theoretically compatible with all x86-64 CPUs
> - **Only verified on macOS 12+** — Linux/Windows untested
> - WebKit version may vary across bun commits
> - WebKit fallback and ldflags fixes in build.sh are designed around known issues; may not be needed in all environments

## Background

Bun's prebuilt macOS binaries target Haswell+ (2014+) CPUs using AVX2/BMI2 instructions. On Ivy Bridge CPUs they immediately crash with SIGILL (exit code 132).

**Solution**: Build from source with `--baseline=true` (generates `-march=nehalem`), producing instructions compatible with all x86-64 CPUs.

A **prebuilt macOS x86-64 binary** (true baseline, compatible with all Intel Macs) is available for direct download — check the [Releases](https://github.com/sxgou/bun4ivybridge/releases) page.

## Directory Structure

```
bun4ivybridge/
├── DESIGN.md                          # Design doc
├── README.md                          # This file
├── config/
│   ├── Brewfile                       # Homebrew dependency lockfile
│   └── cmake-args.sh                  # [Reference] cmake args (affects deps only)
├── patches/
│   ├── ProcessObjectInternals.ts      # Fix const enum leak at runtime
│   └── scripts/
│       ├── build/configure.ts         # globSync → readdirSync patch
│       └── glob-sources.ts            # globSync → simpleGlobSync patch
├── rust-toolchain.toml                # Rust toolchain pinning
└── scripts/
    ├── build.sh                       # Automated build script (recommended)
    └── compile-codegen.sh             # Manual codegen compilation (backup)
```

## Quick Start

```bash
# 1. Clone this project
git clone https://github.com/sxgou/bun4ivybridge.git
cd bun4ivybridge

# 2. Ensure all dependencies are installed (see Environment Requirements above)
brew bundle --file=config/Brewfile

# 3. Build default commit 6ef59777b (bun v1.4.0)
bash scripts/build.sh --yes

# Custom build directory (avoid RAM disk)
# BUILD_DIR=/tmp/bun-build bash scripts/build.sh
```

The script guides you through 9 build phases. Use `--yes` for fully unattended operation.

## Manual Build Steps

### 0. Clone This Project

```bash
git clone https://github.com/sxgou/bun4ivybridge.git
cd bun4ivybridge
```

All steps below assume you are in the `bun4ivybridge` directory.

### 1. Prepare Environment

```bash
# Install Xcode CLI tools
xcode-select --install

# Install Homebrew packages
brew bundle --file=config/Brewfile

# Install Rust
curl https://sh.rustup.rs -sSf | sh
```

Ensure bun >= 1.1.20 is available (for running `build.ts` with globSync patches).

### 2. Prepare Build Directory

```bash
# Optional: RAM disk (faster, reduces SSD wear)
diskutil erasevolume APFS "bun-build" $(hdiutil attach -nomount ram://134217728)

# Or build on filesystem
mkdir -p /Volumes/bun-build
```

### 3. Clone Source

```bash
cd /Volumes/bun-build
git clone https://github.com/oven-sh/bun.git
cd bun
git checkout 6ef59777b
```

### 4. Apply Patches

```bash
cp /path/to/bun4ivybridge/patches/ProcessObjectInternals.ts \
  /Volumes/bun-build/bun/src/js/builtins/ProcessObjectInternals.ts

cp /path/to/bun4ivybridge/patches/scripts/build/configure.ts \
  /Volumes/bun-build/bun/scripts/build/configure.ts

cp /path/to/bun4ivybridge/patches/scripts/glob-sources.ts \
  /Volumes/bun-build/bun/scripts/glob-sources.ts
```

### 5. Generate build.ninja

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

### 6. Fix Known Issues

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

### 7. Build

```bash
cd /Volumes/bun-build/bun/build/release
ninja -j$(sysctl -n hw.ncpu) bun-profile
```

### 8. Verify

```bash
./bun-profile --version
# Expected: 1.4.0

./bun-profile -e 'console.log(process.stderr.fd)'
# Expected: 2
```

### 9. Install

```bash
cp ./bun-profile ~/.bun/bin/bun
```

## Known Issues & Solutions

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

## Patch Reference

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

## Prebuilt Binary

A **true baseline** macOS x86-64 binary (compiled with `-march=nehalem`) is available on the [Releases](https://github.com/sxgou/bun4ivybridge/releases) page. It works on ALL Intel Macs from Nehalem (2008) onwards — no AVX2/BMI2 required.
