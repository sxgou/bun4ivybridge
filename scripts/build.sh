#!/bin/bash
#
# build.sh — bun4ivybridge: 在 Ivy Bridge CPU 上编译 Bun
#
# 使用方法:
#   ./build.sh                    # 默认编译 6ef59777b (v1.4.0-canary.1)
#   BUN_COMMIT=main ./build.sh    # 编译 main 分支最新
#
# 环境变量:
#   BUN_SOURCE      源码仓库 URL (默认: https://github.com/oven-sh/bun.git)
#   BUN_COMMIT      要编译的 commit 或分支 (默认: 6ef59777b)
#   BUILD_DIR       构建目录 (默认: /Volumes/bun-build)
#   INSTALL_DIR     安装目标 (默认: ~/.bun/bin)
#   MARCH           CPU 兼容级别 (默认: nehalem, 若设置其他值则关闭 --baseline)
#   RAM_DISK_SIZE   RAM 盘大小 GB (默认: 64)
#   BUN_BOOTSTRAP   bun 编译工具路径 (默认: 使用 PATH 中的 bun)
#   LLVM_PREFIX     llvm 安装前缀 (默认: 自动检测 Homebrew llvm@21)
#   AUTO_INSTALL    如果设为此脚本的路径，自动安装缺失的工具 (默认: 否)
#
# 已知问题:
#   1. macOS baseline WebKit 预编译包可能不存在于目标 commit 的 release 中
#      → 脚本自动降级使用 standard WebKit 并写入正确的 .identity
#   2. build.ninja 可能缺少 LLVM lib 路径
#      → 脚本自动检测并修复 ldflags（支持 Intel 和 Apple Silicon）
#   3. bootstrap bun v1.1.20 太旧（缺少 globSync API），无法直接运行 build.ts
#      → 需要 bun >= 1.4.0 来执行配置步骤
#
set -euo pipefail

# ============================================================
# 配置
# ============================================================
BUN_SOURCE="${BUN_SOURCE:-https://github.com/oven-sh/bun.git}"
BUN_COMMIT="${BUN_COMMIT:-6ef59777b}"
BUILD_DIR="${BUILD_DIR:-/Volumes/bun-build}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.bun/bin}"
MARCH="${MARCH:-nehalem}"
RAM_DISK_SIZE="${RAM_DISK_SIZE:-64}"
BUN_BOOTSTRAP="${BUN_BOOTSTRAP:-bun}"
AUTO_INSTALL="${AUTO_INSTALL:-}"

# 自动检测 Homebrew llvm@21 安装前缀（支持 Intel 和 Apple Silicon）
if [[ -z "${LLVM_PREFIX:-}" ]]; then
  if [[ -x "/usr/local/opt/llvm@21/bin/clang++" ]]; then
    LLVM_PREFIX="/usr/local/opt/llvm@21"
  elif [[ -x "/opt/homebrew/opt/llvm@21/bin/clang++" ]]; then
    LLVM_PREFIX="/opt/homebrew/opt/llvm@21"
  else
    LLVM_PREFIX=""
  fi
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_BUN_DIR="$BUILD_DIR/bun"
BUILD_RELEASE_DIR="$BUILD_BUN_DIR/build/release"
BASELINE=true

# 如果 MARCH 不是 nehalem，关闭 --baseline
if [[ "$MARCH" != "nehalem" ]]; then
  BASELINE=false
fi

# ============================================================
# 辅助函数
# ============================================================
info()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[31m[ERROR]\033[0m %s\n" "$*"; }
step()  { printf "\n\033[1;34m==== %s ====\033[0m\n" "$*"; }

confirm() {
  printf "\033[33m%s [Y/n]:\033[0m " "$1"
  read -r ans
  case "$ans" in
    n|N|no|NO) return 1 ;;
    *) return 0 ;;
  esac
}

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    if [[ -n "$AUTO_INSTALL" ]]; then
      warn "正在自动安装 $1..."
      brew install "$2"
    else
      err "未找到 $1，请先安装: $2"
      exit 1
    fi
  fi
  ok "找到 $1: $($1 --version 2>&1 | head -1)"
}

# ============================================================
# Phase 1: 环境检查
# ============================================================
step "Phase 1/9: 环境检查"

echo "项目目录: $PROJECT_DIR"
echo "目标 commit: $BUN_COMMIT"
echo "CPU 兼容级别: $MARCH (baseline=$BASELINE)"
echo "构建目录: $BUILD_DIR"
echo "安装目录: $INSTALL_DIR"
echo "bun 编译工具: $BUN_BOOTSTRAP"

# macOS 检测
if [[ "$(uname)" != "Darwin" ]]; then
  warn "本脚本在 macOS 上开发验证。当前系统为 $(uname)，可能需要调整。"
  confirm "是否继续？" || exit 1
fi

# Xcode SDK
if ! xcrun --sdk macosx --show-sdk-path &>/dev/null; then
  err "Xcode SDK 未找到，请运行: xcode-select --install"
  exit 1
fi
ok "Xcode SDK 可用"

# 工具链
if [[ -z "$LLVM_PREFIX" ]]; then
  err "未找到 llvm@21。请先安装: brew install llvm@21"
  err "安装后脚本会自动检测路径（支持 Intel 和 Apple Silicon）"
  exit 1
fi
check_cmd "$LLVM_PREFIX/bin/clang++" "llvm@21"
check_cmd cmake "cmake"
check_cmd ninja "ninja"
check_cmd cargo "rust"

# rustup 可能不在 PATH 中（Homebrew 安装的 cargo 不带 rustup）
if ! command -v rustup &>/dev/null; then
  if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "找到 rustup: $HOME/.cargo/bin/rustup"
  else
    err "未找到 rustup。请先安装: curl https://sh.rustup.rs -sSf | sh"
    err "或: brew install rustup-init && rustup-init"
    exit 1
  fi
fi

# Bootstrap bun 检查
BUN_BOOTSTRAP_VER=$("$BUN_BOOTSTRAP" --version 2>/dev/null || echo "0.0.0")
info "bun 编译工具版本: $BUN_BOOTSTRAP_VER"
if [[ "$(printf '%s\n' "1.4.0" "$BUN_BOOTSTRAP_VER" | sort -V | head -1)" != "1.4.0" ]]; then
  warn "bun 编译工具需要 >= 1.4.0 才能运行 build.ts（配置步骤）"
  warn "当前版本: $BUN_BOOTSTRAP_VER"
  warn ""
  warn "bun v1.1.20 太旧（缺少 globSync API），无法直接运行 build.ts"
  warn "建议: 使用已经可用的 bun v1.4.0+ 作为编译工具"
  warn ""
  confirm "使用当前 bun 继续？可能失败。"
fi

# ============================================================
# Phase 2: 准备构建目录
# ============================================================
step "Phase 2/9: 准备构建目录"

if [[ -d "$BUILD_DIR" ]]; then
  echo "构建目录 $BUILD_DIR 已存在。"
  echo "  [keep]   保留现有目录，跳过 clone 和配置（直接 ninja）"
  echo "  [fresh]  完整重建（删除并重来）"
  echo "  [skip]   跳过准备工作"
  printf "请选择 [keep/fresh/skip]: "
  read -r action
  case "$action" in
    fresh)
      rm -rf "$BUILD_DIR"
      info "已删除 $BUILD_DIR"
      ;;
    skip)
      info "跳过准备工作"
      goto_phase=5
      ;;
    *) # keep 或 回车
      info "保留现有构建目录"
      goto_phase=4
      ;;
  esac
fi

if [[ ! -d "$BUILD_DIR" ]]; then
  info "创建 RAM 盘 (${RAM_DISK_SIZE}GB)..."
  RAM_DEV=$(hdiutil attach -nomount ram://$((RAM_DISK_SIZE * 1024 * 1024 * 2)) 2>/dev/null | grep '/dev/disk' | awk '{print $1}')
  if [[ -z "$RAM_DEV" ]]; then
    warn "RAM 盘创建失败。在文件系统上创建目录。"
    mkdir -p "$BUILD_DIR"
  else
    diskutil erasevolume APFS "bun-build" "$RAM_DEV" &>/dev/null
    ok "RAM 盘已挂载到 $BUILD_DIR"
  fi
fi

# ============================================================
# Phase 3: 获取源码
# ============================================================
if [[ "${goto_phase:-}" -lt 4 ]] 2>/dev/null || [[ -z "${goto_phase:-}" ]]; then
  step "Phase 3/9: 获取源码"

  if [[ ! -d "$BUILD_BUN_DIR/.git" ]]; then
    info "克隆 bun 仓库..."
    git clone --depth=1 "$BUN_SOURCE" "$BUILD_BUN_DIR"
  else
    info "仓库已存在，更新..."
  fi

  cd "$BUILD_BUN_DIR"
  info "检出 $BUN_COMMIT ..."
  git fetch --depth=1 origin "$BUN_COMMIT" 2>/dev/null || \
    git fetch origin "$BUN_COMMIT" 2>/dev/null || \
    { err "无法获取 commit $BUN_COMMIT，请检查 BUN_COMMIT 是否正确"; exit 1; }
  git checkout "$BUN_COMMIT"
  ok "已检出: $(git log --oneline -1)"

  # ============================================================
  # Phase 4: 应用补丁
  # ============================================================
  step "Phase 4/9: 应用补丁"

  if [[ -f "$PROJECT_DIR/patches/ProcessObjectInternals.ts" ]]; then
    cp "$PROJECT_DIR/patches/ProcessObjectInternals.ts" \
      "$BUILD_BUN_DIR/src/js/builtins/ProcessObjectInternals.ts"
    ok "已应用补丁: ProcessObjectInternals.ts"
  fi

  # 补丁: 替换 globSync 为 readdirSync（bun v1.1.x 兼容）
  # bun v1.1.x 的 fs 模块没有 globSync, 但 build.ts 的配置阶段需要它
  # 这两个补丁用 readdirSync + statSync 实现了等价的 glob 功能
  if [[ -f "$PROJECT_DIR/patches/scripts/build/configure.ts" ]]; then
    cp "$PROJECT_DIR/patches/scripts/build/configure.ts" \
      "$BUILD_BUN_DIR/scripts/build/configure.ts"
    ok "已应用补丁: scripts/build/configure.ts (globSync → readdirSync)"
  fi

  if [[ -f "$PROJECT_DIR/patches/scripts/glob-sources.ts" ]]; then
    cp "$PROJECT_DIR/patches/scripts/glob-sources.ts" \
      "$BUILD_BUN_DIR/scripts/glob-sources.ts"
    ok "已应用补丁: scripts/glob-sources.ts (globSync → simpleGlobSync)"
  fi

  # ============================================================
  # Phase 5: 生成 build.ninja（配置）
  # ============================================================
  step "Phase 5/9: 生成 build.ninja（bun configure）"

  cd "$BUILD_BUN_DIR"

  info "运行 bun scripts/build.ts --profile=release --baseline=$BASELINE --configure-only ..."
  info "使用 bun 编译工具: $BUN_BOOTSTRAP"

  if ! "$BUN_BOOTSTRAP" scripts/build.ts \
    --profile=release \
    --baseline="$BASELINE" \
    --configure-only; then
    err "configure 失败。常见原因:"
    err "  1. bun 编译工具版本太旧 — 已应用 globSync 补丁仍失败"
    err "  2. 缺少依赖（检查网络连接）"
    exit 1
  fi
  ok "build.ninja 已生成"

  # 验证 -march 正确
  if grep -q "march=$MARCH" "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    ok "build.ninja 包含 -march=$MARCH"
  else
    warn "build.ninja 中未找到 -march=$MARCH，请检查 --baseline 参数"
    confirm "继续编译？" || exit 1
  fi

  # ============================================================
  # Phase 6: 修复 build.ninja（已知问题解决）
  # ============================================================
  step "Phase 6/9: 修复 build.ninja 已知问题"

  # 问题 1: macOS baseline WebKit 可能不存在
  # 某些 bun commit 的 GitHub Release 中没有 macOS baseline 预编译包
  # 如果 WebKit 下载会 404，使用已缓存的或 standard WebKit
  WEBKIT_DIR="$HOME/.bun/build-cache/webkit-cd821fecca0d39c8-macos-baseline"
  if [[ -d "$WEBKIT_DIR/lib" ]] && [[ -f "$WEBKIT_DIR/lib/libJavaScriptCore.a" ]]; then
    # WebKit 缓存已存在，确保 .identity 文件正确
    WEBKIT_IDENTITY_EXPECTED=$(grep 'identity =' "$BUILD_RELEASE_DIR/build.ninja" | grep webkit | awk '{print $NF}' 2>/dev/null || echo "")
    if [[ -n "$WEBKIT_IDENTITY_EXPECTED" ]]; then
      echo "$WEBKIT_IDENTITY_EXPECTED" > "$WEBKIT_DIR/.identity"
      ok "WebKit .identity 已更新: $WEBKIT_IDENTITY_EXPECTED"
    fi
  else
    warn "WebKit 缓存不存在，ninja 将在编译时自动下载"
    warn "如果下载返回 404，请手动下载 standard WebKit:"
    warn "  https://github.com/oven-sh/WebKit/releases/download/autobuild-<HASH>/bun-webkit-macos-amd64.tar.gz"
    warn "  解压到: $WEBKIT_DIR"
    warn "  写入 .identity: <HASH>-baseline"
    echo ""
    info "尝试自动下载 standard WebKit（降级方案）..."
    # 从 build.ninja 提取 URL
    WEBKIT_URL=$(grep 'url =' "$BUILD_RELEASE_DIR/build.ninja" | grep webkit | awk '{print $NF}' 2>/dev/null || echo "")
    if [[ -n "$WEBKIT_URL" ]]; then
      # 将 baseline URL 改为 standard URL
      STANDARD_URL="${WEBKIT_URL/-baseline/}"
      info "下载: $STANDARD_URL"
      mkdir -p "$WEBKIT_DIR"
      if curl -L -o /tmp/bun-webkit-macos-amd64.tar.gz "$STANDARD_URL"; then
        tar -xzf /tmp/bun-webkit-macos-amd64.tar.gz -C "$WEBKIT_DIR"
        WEBKIT_IDENTITY_EXPECTED=$(grep 'identity =' "$BUILD_RELEASE_DIR/build.ninja" | grep webkit | awk '{print $NF}' 2>/dev/null || echo "")
        if [[ -n "$WEBKIT_IDENTITY_EXPECTED" ]]; then
          echo "$WEBKIT_IDENTITY_EXPECTED" > "$WEBKIT_DIR/.identity"
        fi
        ok "WebKit standard 已下载并配置"
      else
        warn "自动下载失败，ninja 运行时将重试"
      fi
    fi
  fi

  # 问题 2: ldflags 缺少 LLVM lib 路径
  # bun 的 build.ts 可能没有自动检测 llvm@21 的 lib 路径
  LLVM_LIB="$LLVM_PREFIX/lib"
  if ! grep -q "\-L$LLVM_LIB" "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    info "ldflags 缺少 -L$LLVM_LIB，正在修复..."
    sed -i '' 's|-Wl,-ld_new |-Wl,-ld_new -L'"$LLVM_LIB"' |g' \
      "$BUILD_RELEASE_DIR/build.ninja"
    ok "ldflags 已修复 (-L$LLVM_LIB)"
  else
    ok "ldflags 包含 -L$LLVM_LIB"
  fi

  # 问题 3: 确认 codegen 规则是真实的（非桩）
  if grep -q 'echo "SKIP.*codegen' "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    warn "codegen 规则是桩（stub），需要手动处理"
    warn "使用较新的 bun 编译工具可避免此问题"
  else
    ok "codegen 规则是真实的"
  fi
fi

# ============================================================
# Phase 7: 编译 (ninja bun-profile)
# ============================================================
step "Phase 7/9: 编译 (ninja bun-profile)"

cd "$BUILD_RELEASE_DIR"

NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
info "使用 $NPROC 并行任务"
info "编译日志输出较大，请耐心等待..."

if ! ninja -j"$NPROC" bun-profile 2>&1 | tee /tmp/bun-ninja-output.log | tail -20; then
  err "ninja 编译失败。检查输出日志: /tmp/bun-ninja-output.log"
  err ""
  err "常见问题:"
  err "  1. WebKit 下载失败 → 运行 Phase 6 的降级方案"
  err "  2. ldflags 缺少 LLVM lib 路径 → 运行 Phase 6 修复"
  err "  3. 内存不足 → 减少 RAM_DISK_SIZE 或关闭其他程序"
  err "  4. 磁盘空间不足 → 清理磁盘"
  exit 1
fi
ok "编译完成"

# ============================================================
# Phase 8: 处理 codegen 陈旧 .o
# ============================================================
step "Phase 8/9: 检查 codegen 产物"

cd "$BUILD_RELEASE_DIR"

STALE_O=0
for o_file in obj/codegen/*.cpp.o; do
  [[ -f "$o_file" ]] || continue
  cpp_file="codegen/$(basename "$o_file" .o)"
  if [[ -f "$cpp_file" && "$o_file" -ot "$cpp_file" ]]; then
    warn "陈旧 .o: $o_file (比 .cpp 旧)"
    rm -f "$o_file"
    STALE_O=1
  fi
done

if [[ "$STALE_O" -eq 1 ]]; then
  info "发现陈旧 .o 文件，重新编译..."
  ninja -j"$NPROC" bun-profile 2>&1 | tail -10 || {
    warn "ninja 未自动重编译 codegen，使用 compile-codegen.sh ..."
    bash "$PROJECT_DIR/scripts/compile-codegen.sh"
    ninja -j"$NPROC" bun-profile 2>&1 | tail -10
  }
  ok "codegen 已更新"
fi

# ============================================================
# Phase 9: 验证 & 安装
# ============================================================
step "Phase 9/9: 验证 & 安装"

cd "$BUILD_RELEASE_DIR"

# 验证版本
info "运行 bun-profile --version ..."
if ! OUTPUT=$(./bun-profile --version 2>&1); then
  EXIT_CODE=$?
  if [[ "$EXIT_CODE" -eq 132 ]]; then
    err "SIGILL! CPU 不兼容。"
    err "可能原因:"
    err "  1. --baseline=true 未正确应用 — 检查 build.ninja 中的 cflags"
    err "  2. WebKit 预编译包使用了 AVX2 指令 — 需要从源码编译 WebKit"
  else
    err "bun 运行失败，exit code: $EXIT_CODE"
    err "输出: $OUTPUT"
  fi
  exit 1
fi
ok "bun 版本: $OUTPUT"

# 验证 stdio 修复
info "验证 process.stderr.fd ..."
STDERR_FD=$(./bun-profile -e 'console.log(process.stderr.fd)' 2>&1)
if [[ "$STDERR_FD" != "2" ]]; then
  warn "process.stderr.fd = $STDERR_FD (期望 2)"
  warn "补丁 ProcessObjectInternals.ts 可能未正确应用，请检查"
  confirm "继续安装？" || exit 1
fi
ok "process.stderr.fd = $STDERR_FD"

# 验证基本功能
info "验证基本 JS 执行..."
if ! ./bun-profile -e 'console.log(typeof fetch, Bun.version)' &>/dev/null; then
  warn "基本 JS 执行失败，编译产物可能有问题"
  confirm "继续安装？" || exit 1
fi
ok "基本功能正常"

# 安装
mkdir -p "$INSTALL_DIR"
cp ./bun-profile "$INSTALL_DIR/bun"
ok "已安装到 $INSTALL_DIR/bun"

echo ""
info "==========================================="
info "bun 编译安装完成!"
info "  版本: $OUTPUT"
info "  路径: $INSTALL_DIR/bun"
info "  本机 Ivy Bridge CPU: 已验证通过"
info "==========================================="
echo ""
info "如需配置 opencode，请运行:"
info "  bash $PROJECT_DIR/../opencode4ivybridge/scripts/setup.sh"
