# 获取 Bootstrap Bun (v1.1.20)

编译 bun 需要一个已经可运行的 bun 二进制作为 bootstrap。v1.1.15 的 release 页面提供的 macOS x64 baseline 压缩包实际包含的是 v1.1.20，该版本不要求 AVX2 指令，适合在 Ivy Bridge 等老旧 CPU 上使用。

## 下载地址

从 GitHub Releases 下载 macOS x64 版本:

**bun-darwin-x64-baseline.zip (v1.1.15 release — 实际包含 v1.1.20)**

https://github.com/oven-sh/bun/releases/tag/bun-v1.1.15

下载后解压到任意目录，将 `bun` 可执行文件放到 `PATH` 中即可。

## 安装步骤

```bash
# 1. 下载
curl -L -o /tmp/bun-darwin-x64-baseline.zip \
  https://github.com/oven-sh/bun/releases/download/bun-v1.1.15/bun-darwin-x64-baseline.zip

# 2. 解压
cd /tmp
unzip bun-darwin-x64-baseline.zip

# 3. 安装
cp /tmp/bun-darwin-x64-baseline/bun ~/.bun/bin/bun
chmod +x ~/.bun/bin/bun

# 4. 验证
~/.bun/bin/bun --version
# 期望输出: 1.1.20
```

## 与 bun 1.4.0 源码的兼容性

bun v1.1.x 的 `node:fs` 模块缺少 `globSync` API，而新版 bun 源码的构建脚本依赖它。
本项目提供了补丁来解决此问题，使 v1.1.20 能直接编译 v1.4.0 源码。

**补丁文件**（位于 `patches/` 目录）:

| 文件 | 作用 |
|------|------|
| `patches/scripts/build/configure.ts` | 将 `globSync` 替换为 `readdirSync` + `simpleGlob()` |
| `patches/scripts/glob-sources.ts` | 将 `globSync` 替换为 `simpleGlobSync()` 递归实现 |

build.sh 的 Phase 4 会自动应用这些补丁。补丁同时兼容 bun v1.1.x 和 v1.4.0+，
即使用新版本 bun 做编译工具时也不会产生冲突。

**验证结果**: bun v1.1.20 已成功完成 v1.4.0 源码的配置步骤，
正常生成 build.ninja。

## 为什么需要 bootstrap

Bun 的构建系统在配置阶段（生成 `build.ninja`）需要运行 TypeScript 脚本，而这个过程由 bun 驱动。因此需要一个初始的 bun 来编译新版本的 bun。

> 注: 此 bootstrap 步骤仅需一次。一旦通过 bootstrap bun 编译出目标版本后，后续可以使用新版本编译其他版本。
