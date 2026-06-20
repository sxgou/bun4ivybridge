# Getting Bootstrap Bun (v1.1.20)

获取编译所需的初始 Bun 二进制。

## Why Bootstrap? / 为什么需要 bootstrap？

Bun's build system uses bun itself to run TypeScript build scripts that generate `build.ninja`. You need a working bun binary to compile a new version of bun.

Bun 的构建系统使用 bun 自身来运行 TypeScript 脚本生成 `build.ninja`，因此需要一个初始的 bun 来编译新版本。

## Download / 下载地址

The v1.1.15 release page provides a macOS x64 baseline zip that actually contains v1.1.20. This version requires no AVX2 instructions, suitable for Ivy Bridge and older CPUs.

v1.1.15 的 release 页面提供的 macOS x64 baseline 压缩包实际包含的是 v1.1.20，该版本不要求 AVX2 指令。

**bun-darwin-x64-baseline.zip (v1.1.15 release tag — contains v1.1.20 binary)**

https://github.com/oven-sh/bun/releases/tag/bun-v1.1.15

## Installation / 安装步骤

```bash
# 1. Download / 下载
curl -L -o /tmp/bun-darwin-x64-baseline.zip \
  https://github.com/oven-sh/bun/releases/download/bun-v1.1.15/bun-darwin-x64-baseline.zip

# 2. Extract / 解压
cd /tmp
unzip bun-darwin-x64-baseline.zip

# 3. Install / 安装
cp /tmp/bun-darwin-x64-baseline/bun ~/.bun/bin/bun
chmod +x ~/.bun/bin/bun

# 4. Verify / 验证
~/.bun/bin/bun --version
# Expected / 期望输出: 1.1.20
```

## Compatibility with Bun 1.4.0 Source / 与源码的兼容性

bun v1.1.x `node:fs` lacks `globSync` API, which is required by newer bun's build scripts. This project provides two patches to solve this, enabling v1.1.20 to compile v1.4.0 directly.

bun v1.1.x 的 `node:fs` 模块缺少 `globSync` API，而新版 bun 源码的构建脚本依赖它。本项目提供了两个补丁来解决此问题，使 v1.1.20 能直接编译 v1.4.0 源码。

**Patch files / 补丁文件** (located in `patches/` directory):

| File / 文件 | Purpose / 作用 |
|------|------|
| `patches/scripts/build/configure.ts` | Replace `globSync` with `readdirSync` + `simpleGlob()` |
| `patches/scripts/glob-sources.ts` | Replace `globSync` with full `simpleGlobSync()` recursive implementation |

build.sh Phase 4 applies these patches automatically. They are compatible with both v1.1.x and v1.4.0+ bun.

build.sh 的 Phase 4 会自动应用这些补丁。补丁同时兼容旧版和新版 bun。

**Verified / 验证结果**: bun v1.1.20 + patches → build.ninja → ninja compile → bun v1.4.0.
