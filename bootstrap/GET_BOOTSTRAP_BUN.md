# Getting Bootstrap Bun (v1.1.20)

## Why Bootstrap?

Bun's build system uses bun itself to run TypeScript build scripts that generate `build.ninja`. You need a working bun binary to compile a new version of bun.

## Download

The v1.1.15 release page provides a macOS x64 baseline zip that actually contains v1.1.20. This version requires no AVX2 instructions, suitable for Ivy Bridge and older CPUs.

**bun-darwin-x64-baseline.zip (v1.1.15 release tag — contains v1.1.20 binary)**

https://github.com/oven-sh/bun/releases/tag/bun-v1.1.15

## Installation

```bash
# 1. Download
curl -L -o /tmp/bun-darwin-x64-baseline.zip \
  https://github.com/oven-sh/bun/releases/download/bun-v1.1.15/bun-darwin-x64-baseline.zip

# 2. Extract
cd /tmp
unzip bun-darwin-x64-baseline.zip

# 3. Install
cp /tmp/bun-darwin-x64-baseline/bun ~/.bun/bin/bun
chmod +x ~/.bun/bin/bun

# 4. Verify
~/.bun/bin/bun --version
# Expected: 1.1.20
```

## Compatibility with Bun 1.4.0 Source

bun v1.1.x `node:fs` lacks `globSync` API, which is required by newer bun's build scripts. This project provides two patches to solve this, enabling v1.1.20 to compile v1.4.0 directly.

**Patch files** (located in `patches/` directory):

| File | Purpose |
|------|------|
| `patches/scripts/build/configure.ts` | Replace `globSync` with `readdirSync` + `simpleGlob()` |
| `patches/scripts/glob-sources.ts` | Replace `globSync` with full `simpleGlobSync()` recursive implementation |

build.sh Phase 4 applies these patches automatically. They are compatible with both v1.1.x and v1.4.0+ bun.

**Verified**: bun v1.1.20 + patches → build.ninja → ninja compile → bun v1.4.0.
