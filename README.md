# bun4ivybridge: 在 Ivy Bridge CPU 上从源码编译 Bun

在 Ivy Bridge 及更早的 x86-64 CPU 上从源码编译 Bun，解决预编译二进制因使用 AVX2/BMI2 指令而 SIGILL 崩溃的问题。

**已验证**: 2026-06-20 在 Intel Xeon E5-2696 v2 上成功编译并运行 bun 1.4.0。

## 适用环境

- **CPU**: Intel Xeon E5-2696 v2 (Ivy Bridge, 2013) — 不支持 AVX2、BMI2、FMA
- **操作系统**: macOS 12+ (Monterey，已验证 12.7.6)
- **编译器**: LLVM/Clang 21（通过 Homebrew 安装 `brew install llvm@21`）

> ⚠️ **兼容性说明**
> - 本项目的编译参数（`--baseline=true` → `-march=nehalem`）理论上适用于所有 x86-64 CPU
> - **仅在 macOS 12+ 上验证**，其他操作系统（Linux、Windows）未测试
> - 不同版本的 bun 源码其依赖的 WebKit 版本可能不同，WebKit 兼容性可能有差异
> - build.sh 中的 WebKit 降级逻辑和 ldflags 修复是基于已知问题设计的，在其他环境中可能不需要

## 问题背景

Bun 预编译的 macOS 二进制默认针对 Haswell (2014+) 及以上 CPU 优化，使用 AVX2/BMI2 指令。
在 Ivy Bridge CPU 上运行会立即 SIGILL (exit code 132)。

**解决方案**: 从源码编译，用 `--baseline=true` 标志指定 `-march=nehalem`，确保生成兼容所有 x86-64 CPU 的指令。

## 目录结构

```
bun4ivybridge/
├── DESIGN.md                          # 设计文档
├── README.md                          # 本文件
├── bootstrap/
│   └── GET_BOOTSTRAP_BUN.md           # 如何获取 v1.1.20 bootstrap
├── config/
│   └── cmake-args.sh                  # [仅参考] cmake 参数（仅影响依赖库编译）
├── patches/
│   └── ProcessObjectInternals.ts      # 修复 const enum 泄漏为运行时引用的 Bug
└── scripts/
    ├── build.sh                       # 半自动化构建脚本（推荐使用）
    └── compile-codegen.sh             # 手动编译 codegen 的备用脚本
```

## 快速开始（使用 build.sh）

```bash
cd "$(dirname "$0")"  # 进入项目目录
# 或: cd /path/to/bun4ivybridge

# 默认编译 6ef59777b (bun v1.4.0)
bash scripts/build.sh

# 或指定自定义构建目录（避免 RAM 盘）
# BUILD_DIR=/tmp/bun-build bash scripts/build.sh
```

脚本会引导你完成 9 个阶段的构建过程。

## 手动编译步骤

### 1. 准备构建环境

```bash
brew install llvm@21 cmake ninja rust
curl https://sh.rustup.rs -sSf | sh
```

确保 bun >= 1.1.20 可用（用于运行 build.ts 配置步骤，需配合 globSync 补丁）。

### 2. 准备构建目录

```bash
# 可选: 创建 RAM 盘（加速编译，减少 SSD 磨损）
diskutil erasevolume APFS "bun-build" $(hdiutil attach -nomount ram://134217728)

# 或直接在文件系统上构建
mkdir -p /Volumes/bun-build
```

### 3. 克隆源码

```bash
cd /Volumes/bun-build
git clone https://github.com/oven-sh/bun.git
cd bun
git checkout 6ef59777b
```

### 4. 应用补丁

```bash
cp /path/to/bun4ivybridge/patches/ProcessObjectInternals.ts \
  /Volumes/bun-build/bun/src/js/builtins/ProcessObjectInternals.ts
```

### 5. 生成 build.ninja

```bash
cd /Volumes/bun-build/bun

# 这是关键步骤: --baseline=true 确保生成 -march=nehalem
bun scripts/build.ts --profile=release --baseline=true --configure-only
```

验证 build.ninja 包含正确的 march:
```bash
grep march build/release/build.ninja | head -3
# 应看到: -march=nehalem
```

### 6. 修复已知问题

```bash
# 问题 1: macOS baseline WebKit 可能不存在
# 如 WebKit 下载失败，手动下载 standard 版本:
# curl -L -o /tmp/webkit.tar.gz https://github.com/oven-sh/WebKit/releases/download/autobuild-<HASH>/bun-webkit-macos-amd64.tar.gz
# mkdir -p ~/.bun/build-cache/webkit-<HASH>-macos-baseline
# tar -xzf /tmp/webkit.tar.gz -C ~/.bun/build-cache/webkit-<HASH>-macos-baseline
# echo "<HASH>-baseline" > ~/.bun/build-cache/webkit-<HASH>-macos-baseline/.identity

# 问题 2: ldflags 缺少 llvm@21 lib 路径
cd /Volumes/bun-build/bun/build/release
if ! grep -q '\-L/usr/local/opt/llvm@21/lib' build.ninja; then
  sed -i '' 's|-Wl,-ld_new |-Wl,-ld_new -L/usr/local/opt/llvm@21/lib |g' build.ninja
fi
```

### 7. 编译

```bash
cd /Volumes/bun-build/bun/build/release
ninja -j$(sysctl -n hw.ncpu) bun-profile
```

### 8. 验证

```bash
./bun-profile --version
# 期望: 1.4.0

./bun-profile -e 'console.log(process.stderr.fd)'
# 期望: 2
```

### 9. 安装

```bash
cp ./bun-profile ~/.bun/bin/bun
```

## 遇到的问题及解决办法

### 问题 1: SIGILL — 预编译二进制使用 AVX2/BMI2 指令

**现象**: 运行预编译的 `bun` 二进制立即退出，exit code 132。

**原因**: Bun 的 macOS 构建面向 Haswell (2014+) CPU，使用 AVX2/BMI2 指令。

**解决**: 从源码编译，使用 `--baseline=true` 标志指定 `-march=nehalem`。

### 问题 2: `BunProcessStdinFdType is not defined` — const enum 泄漏

**现象**: 访问 `process.stderr` 时报错 `ReferenceError: $BunProcessStdinFdType is not defined`。

**原因**: Bun 的 builtin 转译器在处理 TypeScript `const enum` 时没有完全内联。

**解决**: 见补丁 `patches/ProcessObjectInternals.ts`。

### 问题 3: macOS baseline WebKit 预编译包不存在

**现象**: ninja 构建时 WebKit 下载返回 HTTP 404。

**原因**: 某些 bun commit 的 GitHub Release 中没有 macOS baseline 变体。

**解决**: build.sh 自动降级下载 standard WebKit。已验证 standard WebKit 在 Ivy Bridge 上工作正常。

### 问题 4: 链接时 `library not found for -ld_new`

**现象**: 链接阶段报错 `ld: library not found for -ld_new`。

**原因**: bun 的 build.ts 未自动检测 llvm@21 的 lib path。

**解决**: 在 ldflags 中添加 `-L/usr/local/opt/llvm@21/lib`。

### 问题 5: bootstrap bun v1.1.20 太旧（缺少 globSync API）

**现象**: 运行 `bun scripts/build.ts` 时报 `SyntaxError: Export named 'globSync' not found in module 'fs'`。

**原因**: v1.1.20 的 `node:fs` 模块缺少新版 bun 源码 build.ts 所需的 `globSync` API。

**解决**: 本项目提供了两个补丁（`patches/scripts/build/configure.ts`、`patches/scripts/glob-sources.ts`），将 `globSync` 替换为 `readdirSync` + `statSync` 实现，使 v1.1.20 能直接运行配置步骤。

### 问题 6: Codegen 陈旧 .o 文件

**现象**: 修改了补丁文件后，重新编译但问题仍然存在。

**原因**: .o 文件比 .cpp 源文件旧，ninja 未自动重新编译。

**解决**: build.sh 自动检查并删除陈旧 .o 文件。

## 补丁说明

### `patches/ProcessObjectInternals.ts`

**作用**: 将 `const enum BunProcessStdinFdType` 替换为数值字面量，避免运行时引用错误。

**安装方式**: 复制到 Bun 源码目录的对应位置：
```bash
cp patches/ProcessObjectInternals.ts /Volumes/bun-build/bun/src/js/builtins/ProcessObjectInternals.ts
```

### `scripts/compile-codegen.sh`

**作用**: 当 ninja 不自动重编译 codegen 时的手动备用方案。适用于旧版 bun 配置生成的 build.ninja 中 codegen 规则是桩（stub）的情况。

**使用方法**:
```bash
cd /Volumes/bun-build/bun/build/release
bash /path/to/bun4ivybridge/scripts/compile-codegen.sh
```
