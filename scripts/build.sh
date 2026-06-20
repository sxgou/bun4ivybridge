#!/bin/bash
#
# build.sh — Build bun from source on Ivy Bridge (or any x86-64) CPUs
#
# Usage:
#   ./build.sh                    # Build default commit 6ef59777b (bun v1.4.0)
#   ./build.sh --yes              # Unattended mode (no prompts)
#   BUN_COMMIT=main ./build.sh    # Build latest main branch
#
# Environment variables:
#   BUN_SOURCE      Source repo URL (default: https://github.com/oven-sh/bun.git)
#   BUN_COMMIT      Commit or branch to build (default: 6ef59777b)
#   BUILD_DIR       Build directory (default: /Volumes/bun-build)
#   INSTALL_DIR     Install target (default: ~/.bun/bin)
#   MARCH           CPU arch baseline (default: nehalem; set to other value to disable --baseline)
#   RAM_DISK_SIZE   RAM disk size in GB (default: 64)
#   BUN_BOOTSTRAP   Path to bootstrap bun binary (default: bun from PATH)
#   LLVM_PREFIX     LLVM installation prefix (default: auto-detect Homebrew llvm@21)
#   BATCH_MODE      Set to 1 to skip all interactive prompts (also set by --yes)
#
# Known issues handled automatically:
#   1. macOS baseline WebKit prebuilt may not exist for the target commit
#      → Falls back to standard WebKit automatically
#   2. build.ninja may lack LLVM lib path in ldflags
#      → Auto-detects and fixes (supports Intel and Apple Silicon)
#   3. Bootstrap bun v1.1.x lacks globSync API
#      → Patches provided (scripts/build/configure.ts + glob-sources.ts)
#
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
BUN_SOURCE="${BUN_SOURCE:-https://github.com/oven-sh/bun.git}"
BUN_COMMIT="${BUN_COMMIT:-6ef59777b}"
BUILD_DIR="${BUILD_DIR:-/Volumes/bun-build}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.bun/bin}"
MARCH="${MARCH:-nehalem}"
RAM_DISK_SIZE="${RAM_DISK_SIZE:-64}"
BUN_BOOTSTRAP="${BUN_BOOTSTRAP:-bun}"
BATCH_MODE="${BATCH_MODE:-0}"

# Auto-detect Homebrew llvm@21 path (supports Intel and Apple Silicon)
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

# Disable --baseline if MARCH is not nehalem
if [[ "$MARCH" != "nehalem" ]]; then
  BASELINE=false
fi

# Parse command-line arguments
for arg in "$@"; do
  case "$arg" in
    --yes|-y)
      BATCH_MODE=1
      ;;
    --help|-h)
      echo "build.sh — Build bun from source on Ivy Bridge CPUs"
      echo ""
      echo "Usage:"
      echo "  bash build.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --yes, -y    Unattended mode (auto-answer all prompts)"
      echo "  --help, -h   Show this help"
      echo ""
      echo "Environment variables:"
      echo "  BUN_SOURCE      Source repo URL (default: $BUN_SOURCE)"
      echo "  BUN_COMMIT      Commit to build (default: $BUN_COMMIT)"
      echo "  BUILD_DIR       Build directory (default: $BUILD_DIR)"
      echo "  INSTALL_DIR     Install target (default: $INSTALL_DIR)"
      echo "  MARCH           CPU architecture baseline (default: $MARCH)"
      echo "  RAM_DISK_SIZE   RAM disk size in GB (default: $RAM_DISK_SIZE)"
      echo "  BUN_BOOTSTRAP   Bootstrap bun path (default: from PATH)"
      echo "  LLVM_PREFIX     LLVM installation prefix (auto-detected)"
      echo "  BATCH_MODE      1 for fully unattended build"
      exit 0
      ;;
  esac
done

# ============================================================
# Helper functions
# ============================================================
info()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok()    { printf "\033[32m[OK]\033[0m   %s\n" "$*"; }
warn()  { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()   { printf "\033[31m[ERROR]\033[0m %s\n" "$*"; }
step()  { printf "\n\033[1;34m==== %s ====\033[0m\n" "$*"; }

# confirm: in batch mode, always returns 0 (yes); otherwise prompts
confirm() {
  if [[ "$BATCH_MODE" -eq 1 ]]; then
    return 0
  fi
  printf "\033[33m%s [Y/n]:\033[0m " "$1"
  read -r ans
  case "$ans" in
    n|N|no|NO) return 1 ;;
    *) return 0 ;;
  esac
}

# prompt_with_options: in batch mode, returns the default choice; otherwise prompts
# Usage: prompt_with_options "message" "default" ["opt1" "opt2" ...]
prompt_with_options() {
  local msg="$1"
  local default="$2"
  shift 2
  if [[ "$BATCH_MODE" -eq 1 ]]; then
    echo "$default"
    return 0
  fi
  local options=("$@")
  echo "$msg"
  for o in "${options[@]}"; do
    if [[ "$o" == "$default" ]]; then
      echo "  [$o] (default)"
    else
      echo "  [$o]"
    fi
  done
  printf "Choose [%s]: " "${options[*]}"
  read -r action
  action="${action:-$default}"
  echo "$action"
}

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    if [[ -n "$AUTO_INSTALL" ]]; then
      warn "Auto-installing $1..."
      brew install "$2"
    else
      err "$1 not found. Install with: $2"
      exit 1
    fi
  fi
  ok "Found $1: $($1 --version 2>&1 | head -1)"
}

# extract_webkit_identity: parse WebKit identity from build.ninja
extract_webkit_identity() {
  grep 'identity =' "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null | grep webkit | awk '{print $NF}' || echo ""
}

# extract_webkit_url: parse WebKit download URL from build.ninja
extract_webkit_url() {
  grep 'url =' "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null | grep webkit | awk '{print $NF}' || echo ""
}

# skip_phase: returns 0 if the phase should run, 1 if it should be skipped
# goto_phase is the first phase to run (skip all earlier phases)
goto_phase="${goto_phase:-}"
skip_phase() {
  local phase_num="$1"
  if [[ -n "$goto_phase" && "$goto_phase" -gt "$phase_num" ]]; then
    return 1  # skip
  fi
  return 0  # run
}

# ============================================================
# Phase 1: Environment Check
# ============================================================
step "Phase 1/9: Environment Check"

echo "  Project dir:    $PROJECT_DIR"
echo "  Target commit:  $BUN_COMMIT"
echo "  CPU baseline:   $MARCH (baseline=$BASELINE)"
echo "  Build dir:      $BUILD_DIR"
echo "  Install dir:    $INSTALL_DIR"
echo "  Bootstrap bun:  $BUN_BOOTSTRAP"
echo "  Batch mode:     $BATCH_MODE"

# macOS detection
if [[ "$(uname)" != "Darwin" ]]; then
  warn "This script is designed and tested on macOS. Current OS: $(uname)"
  confirm "Continue anyway?" || exit 1
fi

# Xcode SDK
if ! xcrun --sdk macosx --show-sdk-path &>/dev/null; then
  err "Xcode SDK not found. Run: xcode-select --install"
  exit 1
fi
ok "Xcode SDK available"

# Toolchain
if [[ -z "$LLVM_PREFIX" ]]; then
  err "llvm@21 not found. Install with: brew install llvm@21"
  err "The script auto-detects the path (supports Intel and Apple Silicon)"
  exit 1
fi
check_cmd "$LLVM_PREFIX/bin/clang++" "llvm@21"
check_cmd cmake "cmake"
check_cmd ninja "ninja"
check_cmd cargo "rust"

# rustup may not be in PATH (Homebrew-installed cargo doesn't include rustup)
if ! command -v rustup &>/dev/null; then
  if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "Found rustup: $HOME/.cargo/bin/rustup"
  else
    err "rustup not found. Install with: curl https://sh.rustup.rs -sSf | sh"
    err "Or: brew install rustup-init && rustup-init"
    exit 1
  fi
fi

# Bootstrap bun version check
BUN_BOOTSTRAP_VER=$("$BUN_BOOTSTRAP" --version 2>/dev/null || echo "0.0.0")
info "Bootstrap bun version: $BUN_BOOTSTRAP_VER"

# Minimum required: 1.1.20 (older versions lack globSync needed by build.ts)
# But if patches are applied, even 1.1.20 works. Versions below 1.1.20 may fail.
MIN_BUN="1.1.20"
if [[ "$(printf '%s\n' "$MIN_BUN" "$BUN_BOOTSTRAP_VER" | sort -V | head -1)" != "$MIN_BUN" ]]; then
  warn "Bootstrap bun should be >= $MIN_BUN to run build.ts (configure step)"
  warn "Current version: $BUN_BOOTSTRAP_VER"
  warn ""
  warn "If older than $MIN_BUN, the globSync patches may not be sufficient."
  warn "Recommended: use bun v1.1.20+ as bootstrap."
  warn ""
  confirm "Continue with current bun? May fail." || exit 1
fi

# ============================================================
# Phase 2: Prepare Build Directory
# ============================================================
step "Phase 2/9: Prepare Build Directory"

goto_phase=""

if [[ -d "$BUILD_DIR" ]]; then
  # Determine reasonable defaults for batch mode
  if [[ "$BATCH_MODE" -eq 1 ]]; then
    if [[ -f "$BUILD_RELEASE_DIR/build.ninja" ]]; then
      info "Build directory exists with build.ninja — skipping to compile phase"
      goto_phase=7
    elif [[ -d "$BUILD_BUN_DIR/.git" ]]; then
      info "Build directory exists with source — reapplying patches and reconfiguring"
      goto_phase=4
    else
      info "Build directory exists but incomplete — rebuilding"
      rm -rf "$BUILD_DIR"
    fi
  else
    echo "Build directory $BUILD_DIR already exists."
    action=$(prompt_with_options \
      "Choose action:" \
      "keep" \
      "keep" "fresh" "skip")
    case "$action" in
      fresh)
        rm -rf "$BUILD_DIR"
        info "Deleted $BUILD_DIR"
        ;;
      skip)
        info "Skipping preparation — going directly to build"
        goto_phase=7
        ;;
      *) # keep
        info "Keeping existing build directory"
        goto_phase=4
        ;;
    esac
  fi
fi

if [[ ! -d "$BUILD_DIR" ]]; then
  info "Creating RAM disk (${RAM_DISK_SIZE}GB)..."
  RAM_DEV=$(hdiutil attach -nomount ram://$((RAM_DISK_SIZE * 1024 * 1024 * 2)) 2>/dev/null | grep '/dev/disk' | awk '{print $1}')
  if [[ -z "$RAM_DEV" ]]; then
    warn "RAM disk creation failed. Creating directory on filesystem instead."
    mkdir -p "$BUILD_DIR"
  else
    diskutil erasevolume APFS "bun-build" "$RAM_DEV" &>/dev/null
    ok "RAM disk mounted at $BUILD_DIR"
  fi
fi

# ============================================================
# Phase 3: Fetch Source
# ============================================================
if skip_phase 3; then
  step "Phase 3/9: Fetch Source"

  if [[ ! -d "$BUILD_BUN_DIR/.git" ]]; then
    info "Cloning bun repository..."
    git clone --depth=1 "$BUN_SOURCE" "$BUILD_BUN_DIR"
  else
    info "Repository already exists, updating..."
  fi

  cd "$BUILD_BUN_DIR"
  info "Checking out $BUN_COMMIT ..."
  git fetch --depth=1 origin "$BUN_COMMIT" 2>/dev/null || \
    git fetch origin "$BUN_COMMIT" 2>/dev/null || \
    { err "Cannot fetch commit $BUN_COMMIT. Check BUN_COMMIT."; exit 1; }
  git checkout "$BUN_COMMIT"
  ok "Checked out: $(git log --oneline -1)"

  # ============================================================
  # Phase 4: Apply Patches
  # ============================================================
  step "Phase 4/9: Apply Patches"

  if [[ -f "$PROJECT_DIR/patches/ProcessObjectInternals.ts" ]]; then
    cp "$PROJECT_DIR/patches/ProcessObjectInternals.ts" \
      "$BUILD_BUN_DIR/src/js/builtins/ProcessObjectInternals.ts"
    ok "Applied patch: ProcessObjectInternals.ts (const enum leak fix)"
  fi

  # Patches: replace globSync with readdirSync (bun v1.1.x compatibility)
  # bun v1.1.x node:fs lacks globSync, but the build configuration step needs it
  # These two patches implement equivalent glob functionality using readdirSync + statSync
  if [[ -f "$PROJECT_DIR/patches/scripts/build/configure.ts" ]]; then
    cp "$PROJECT_DIR/patches/scripts/build/configure.ts" \
      "$BUILD_BUN_DIR/scripts/build/configure.ts"
    ok "Applied patch: scripts/build/configure.ts (globSync -> readdirSync)"
  fi

  if [[ -f "$PROJECT_DIR/patches/scripts/glob-sources.ts" ]]; then
    cp "$PROJECT_DIR/patches/scripts/glob-sources.ts" \
      "$BUILD_BUN_DIR/scripts/glob-sources.ts"
    ok "Applied patch: scripts/glob-sources.ts (globSync -> simpleGlobSync)"
  fi

  # ============================================================
  # Phase 5: Generate build.ninja
  # ============================================================
  step "Phase 5/9: Generate build.ninja (bun configure)"

  cd "$BUILD_BUN_DIR"

  info "Running: bun scripts/build.ts --profile=release --baseline=$BASELINE --configure-only"
  info "Using bootstrap bun: $BUN_BOOTSTRAP"

  if ! "$BUN_BOOTSTRAP" scripts/build.ts \
    --profile=release \
    --baseline="$BASELINE" \
    --configure-only; then
    err "Configure failed. Common causes:"
    err "  1. Bootstrap bun too old — globSync patches may not be sufficient"
    err "  2. Missing dependencies (check network connectivity)"
    exit 1
  fi
  ok "build.ninja generated"

  # Verify correct march flag
  if grep -q "march=$MARCH" "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    ok "build.ninja contains -march=$MARCH"
  else
    warn "build.ninja does not contain -march=$MARCH. Check --baseline parameter."
    confirm "Continue building?" || exit 1
  fi

  # ============================================================
  # Phase 6: Fix Known Issues in build.ninja
  # ============================================================
  step "Phase 6/9: Fix Known Issues in build.ninja"

  # Issue 1: macOS baseline WebKit may not exist in GitHub Releases
  # Some bun commits don't have a macOS baseline prebuilt variant.
  # We try to download the standard variant as a fallback.
  WEBKIT_IDENTITY=$(extract_webkit_identity)
  if [[ -n "$WEBKIT_IDENTITY" ]]; then
    WEBKIT_DIR="$HOME/.bun/build-cache/$WEBKIT_IDENTITY"
    if [[ -d "$WEBKIT_DIR/lib" ]] && [[ -f "$WEBKIT_DIR/lib/libJavaScriptCore.a" ]]; then
      # WebKit cache exists, ensure .identity matches build.ninja
      echo "$WEBKIT_IDENTITY" > "$WEBKIT_DIR/.identity"
      ok "WebKit .identity updated: $WEBKIT_IDENTITY"
    else
      warn "WebKit cache not found for: $WEBKIT_IDENTITY"
      warn "ninja will attempt to download during build."
      echo ""
      info "Attempting automatic standard WebKit download (fallback)..."
      WEBKIT_URL=$(extract_webkit_url)
      if [[ -n "$WEBKIT_URL" ]]; then
        # Replace -baseline with standard variant
        STANDARD_URL="${WEBKIT_URL/-baseline/}"
        info "Downloading: $STANDARD_URL"
        mkdir -p "$WEBKIT_DIR"
        if curl -L -o /tmp/bun-webkit-macos-amd64.tar.gz "$STANDARD_URL"; then
          tar -xzf /tmp/bun-webkit-macos-amd64.tar.gz -C "$WEBKIT_DIR"
          echo "$WEBKIT_IDENTITY" > "$WEBKIT_DIR/.identity"
          ok "Standard WebKit downloaded and configured"
        else
          warn "Auto-download failed; ninja will retry at build time"
        fi
      fi
    fi
  else
    warn "Could not detect WebKit identity from build.ninja"
    warn "WebKit will be downloaded during ninja build"
  fi

  # Issue 2: ldflags may be missing LLVM lib path
  # bun's build.ts may not auto-detect llvm@21's lib directory
  LLVM_LIB="$LLVM_PREFIX/lib"
  if ! grep -q "\-L$LLVM_LIB" "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    info "ldflags missing -L$LLVM_LIB — fixing..."
    sed -i '' 's|-Wl,-ld_new |-Wl,-ld_new -L'"$LLVM_LIB"' |g' \
      "$BUILD_RELEASE_DIR/build.ninja"
    ok "ldflags fixed (-L$LLVM_LIB)"
  else
    ok "ldflags include -L$LLVM_LIB"
  fi

  # Issue 3: Verify codegen rules are real (not stubs)
  if grep -q 'echo "SKIP.*codegen' "$BUILD_RELEASE_DIR/build.ninja" 2>/dev/null; then
    warn "Codegen rules are stubs — manual handling may be needed"
    warn "Using a newer bootstrap bun can avoid this issue"
  else
    ok "Codegen rules are real"
  fi
fi

# ============================================================
# Phase 7: Build (ninja bun-profile)
# ============================================================
step "Phase 7/9: Build (ninja bun-profile)"

cd "$BUILD_RELEASE_DIR"

NPROC=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
info "Using $NPROC parallel jobs"
info "Build log is large — tailing last 20 lines..."
info "Full log: /tmp/bun-ninja-output.log"

if ! ninja -j"$NPROC" bun-profile 2>&1 | tee /tmp/bun-ninja-output.log | tail -20; then
  err "ninja build failed. See: /tmp/bun-ninja-output.log"
  err ""
  err "Common issues:"
  err "  1. WebKit download failed -> re-run with Phase 6 fallback"
  err "  2. ldflags missing LLVM lib path -> re-run with Phase 6 fix"
  err "  3. Out of memory -> reduce RAM_DISK_SIZE or close other programs"
  err "  4. Disk full -> free up space"
  exit 1
fi
ok "Build complete"

# ============================================================
# Phase 8: Handle Stale Codegen .o Files
# ============================================================
step "Phase 8/9: Check Codegen Artifacts"

cd "$BUILD_RELEASE_DIR"

STALE_O=0
for o_file in obj/codegen/*.cpp.o; do
  [[ -f "$o_file" ]] || continue
  cpp_file="codegen/$(basename "$o_file" .o)"
  if [[ -f "$cpp_file" && "$o_file" -ot "$cpp_file" ]]; then
    warn "Stale .o: $o_file (older than .cpp source)"
    rm -f "$o_file"
    STALE_O=1
  fi
done

if [[ "$STALE_O" -eq 1 ]]; then
  info "Found stale .o files — recompiling..."
  ninja -j"$NPROC" bun-profile 2>&1 | tail -10 || {
    warn "ninja did not auto-recompile codegen; running compile-codegen.sh..."
    bash "$PROJECT_DIR/scripts/compile-codegen.sh"
    ninja -j"$NPROC" bun-profile 2>&1 | tail -10
  }
  ok "Codegen updated"
fi

# ============================================================
# Phase 9: Verify & Install
# ============================================================
step "Phase 9/9: Verify & Install"

cd "$BUILD_RELEASE_DIR"

# Verify version
info "Running bun-profile --version ..."
if ! OUTPUT=$(./bun-profile --version 2>&1); then
  EXIT_CODE=$?
  if [[ "$EXIT_CODE" -eq 132 ]]; then
    err "SIGILL! CPU incompatible."
    err "Possible causes:"
    err "  1. --baseline=true was not applied correctly — check build.ninja cflags"
    err "  2. WebKit prebuilt uses AVX2 instructions — need to build WebKit from source"
  else
    err "bun failed with exit code: $EXIT_CODE"
    err "Output: $OUTPUT"
  fi
  exit 1
fi
ok "bun version: $OUTPUT"

# Verify process.stderr.fd fix
info "Verifying process.stderr.fd ..."
STDERR_FD=$(./bun-profile -e 'console.log(process.stderr.fd)' 2>&1)
if [[ "$STDERR_FD" != "2" ]]; then
  warn "process.stderr.fd = $STDERR_FD (expected 2)"
  warn "Patch ProcessObjectInternals.ts may not be applied correctly"
  confirm "Continue installation?" || exit 1
fi
ok "process.stderr.fd = $STDERR_FD"

# Verify basic JS execution
info "Verifying basic JS execution..."
if ! ./bun-profile -e 'console.log(typeof fetch, Bun.version)' &>/dev/null; then
  warn "Basic JS execution failed — build may be broken"
  confirm "Continue installation?" || exit 1
fi
ok "Basic functionality verified"

# Install
mkdir -p "$INSTALL_DIR"
cp ./bun-profile "$INSTALL_DIR/bun"
ok "Installed to $INSTALL_DIR/bun"

echo ""
info "=========================================="
info "bun built and installed successfully!"
info "  Version: $OUTPUT"
info "  Path:    $INSTALL_DIR/bun"
info "  Baseline march: $MARCH"
info "=========================================="
echo ""
info "To set up opencode, run:"
info "  bash $PROJECT_DIR/../opencode4ivybridge/scripts/setup.sh"
