/**
 * Source list globbing.
 *
 * `globAllSources()` is called on every configure — new/deleted files are
 * picked up automatically. All patterns expand in a single pass so there's
 * one consistent filesystem snapshot; callers receive a plain struct, no
 * filesystem reads thereafter.
 *
 * Also runnable as a CLI to print a single list (for run-clang-format.sh,
 * ad-hoc inspection):
 *
 *   bun scripts/glob-sources.ts cxx    # one .cpp path per line
 *   bun scripts/glob-sources.ts        # list available fields
 */

import { readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { assert } from "./build/error.ts";

/** Minimal globSync replacement — handles patterns used in this file. */
function simpleGlobSync(pattern: string, opts: { cwd: string }): string[] {
  const expandBraces = (s: string): string[] => {
    const m = s.match(/\{([^}]+)\}/);
    if (!m) return [s];
    return m[1].split(",").flatMap(alt => expandBraces(s.replace(m![0], alt)));
  };

  const parts = pattern.split("/");
  const baseParts: string[] = [];
  const globParts: string[] = [];
  let inGlob = false;
  for (const p of parts) {
    if (!inGlob && !p.includes("*") && !p.includes("{")) {
      baseParts.push(p);
    } else {
      inGlob = true;
      globParts.push(p);
    }
  }
  const baseDir = resolve(opts.cwd, ...baseParts);
  if (globParts.length === 0) {
    try { statSync(baseDir); return [relative(opts.cwd, baseDir)]; } catch { return []; }
  }
  const results: string[] = [];
  const base = baseParts.join("/");

  function walk(dir: string, idx: number, relPath: string) {
    if (idx >= globParts.length) { results.push(relPath); return; }
    const part = globParts[idx];
    if (part === "**") {
      walk(dir, idx + 1, relPath);
      try {
        for (const entry of readdirSync(dir)) {
          if (entry.startsWith(".")) continue;
          const full = join(dir, entry);
          try { if (statSync(full).isDirectory()) walk(full, idx, `${relPath}/${entry}`); } catch {}
        }
      } catch {}
      return;
    }
    const variants = expandBraces(part);
    for (const v of variants) {
      const isAll = v === "*";
      const extFilter = v.startsWith("*.") ? v.slice(1) : null;
      try {
        for (const entry of readdirSync(dir)) {
          if (entry.startsWith(".")) continue;
          const matches = isAll || entry === v || (extFilter && entry.endsWith(extFilter));
          if (!matches) continue;
          const full = join(dir, entry);
          const rel = relPath ? `${relPath}/${entry}` : entry;
          if (idx === globParts.length - 1) {
            try { statSync(full); results.push(rel); } catch {}
          } else {
            try { if (statSync(full).isDirectory()) walk(full, idx + 1, rel); } catch {}
          }
        }
      } catch {}
    }
  }

  walk(baseDir, 0, base);
  return results.sort();
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

interface SourcePattern {
  paths: string[];
  exclude?: string[];
}

/**
 * Source patterns. Field name → glob patterns (relative to repo root).
 *
 * To add a new source list: add an entry here. The `Sources` type and
 * `globAllSources()` pick it up automatically.
 */
const patterns = {
  /** `packages/bun-error/*` — error overlay page */
  bunError: {
    paths: ["packages/bun-error/*.{json,ts,tsx,css}", "packages/bun-error/img/*"],
  },
  /** `*.string-map.ts` — input to generate-string-map codegen */
  stringMaps: {
    paths: ["src/**/*.string-map.ts"],
  },
  /** `src/node-fallbacks/*.js` */
  nodeFallbacks: {
    paths: ["src/node-fallbacks/*.js"],
  },
  /** `*.classes.ts` — input to generate-classes codegen */
  zigGeneratedClasses: {
    paths: ["src/**/*.classes.ts"],
  },
  /** built-in modules bundled at build time */
  js: {
    paths: ["src/js/**/*.{js,ts}", "src/install/PackageManager/scanner-entry.ts"],
  },
  /** the codegen scripts themselves */
  jsCodegen: {
    paths: ["src/codegen/*.ts"],
  },
  /** server-rendering runtime bundled into binary */
  bakeRuntime: {
    paths: ["src/runtime/bake/*.ts", "src/runtime/bake/*/*.{ts,css}"],
    exclude: ["src/runtime/bake/generated.ts"],
  },
  /** legacy bindgen input */
  bindgen: {
    paths: ["src/**/*.bind.ts"],
  },
  /** v2 bindgen input */
  bindgenV2: {
    paths: ["src/**/*.bindv2.ts"],
  },
  /** bindgen v2 generator code */
  bindgenV2Internal: {
    paths: ["src/codegen/bindgenv2/**/*.ts"],
  },
  /**
   * NOT filtered; includes codegen-written files (see bun.ts).
   *
   * `src/cli/**` is excluded: it is a committed symlink → `runtime/cli`
   * which `simpleGlobSync` follows on POSIX (double-counts every file)
   * but cannot traverse on Windows agents where git materialises the link
   * as a text file. Excluding the alias keeps the file set platform-stable
   * for ban-words count pinning.
   */
  zig: {
    paths: ["src/**/*.zig"],
    exclude: ["src/cli/**"],
  },
  /**
   * all `*.rs` + workspace manifests — implicit inputs to the cargo step.
   * `rust-toolchain.toml` is included so a nightly bump invalidates the
   * staticlib (cargo's own fingerprinting then forces a full rebuild).
   */
  rust: {
    paths: ["src/**/*.rs", "src/**/Cargo.toml", "Cargo.toml", "Cargo.lock", "rust-toolchain.toml"],
  },
  /** all `*.cpp` compiled into bun (bindings, webcore, v8 shim, usockets) */
  cxx: {
    paths: [
      "src/io/*.cpp",
      "src/jsc/modules/*.cpp",
      "src/jsc/bindings/*.cpp",
      "src/jsc/bindings/webcore/*.cpp",
      "src/jsc/bindings/sqlite/*.cpp",
      "src/jsc/bindings/webcrypto/*.cpp",
      "src/jsc/bindings/webcrypto/*/*.cpp",
      "src/jsc/bindings/node/*.cpp",
      "src/jsc/bindings/node/crypto/*.cpp",
      "src/jsc/bindings/node/http/*.cpp",
      "src/jsc/bindings/v8/*.cpp",
      "src/jsc/bindings/v8/shim/*.cpp",
      "src/runtime/webview/*.cpp",
      "src/runtime/bake/*.cpp",
      "src/uws_sys/*.cpp",
      "src/simdutf_sys/*.cpp",
      "src/jsc/bindings/vm/*.cpp",
      "packages/bun-usockets/src/crypto/*.cpp",
    ],
  },
  /** all `*.c` compiled into bun (usockets, llhttp, uv polyfills) */
  c: {
    paths: [
      "packages/bun-usockets/src/*.c",
      "packages/bun-usockets/src/eventing/*.c",
      "packages/bun-usockets/src/internal/*.c",
      "packages/bun-usockets/src/crypto/*.c",
      "src/jsc/bindings/uv-posix-polyfills.c",
      "src/jsc/bindings/uv-posix-stubs.c",
      "src/*.c",
      "src/jsc/bindings/node/http/llhttp/*.c",
    ],
  },
} satisfies Record<string, SourcePattern>;

/**
 * All globbed source lists. Each field is absolute paths, sorted.
 * Derived from `patterns` — add a pattern there and it appears here.
 */
export type Sources = { [K in keyof typeof patterns]: string[] };

/**
 * Glob all source lists. Called once per configure.
 */
export function globAllSources(): Sources {
  const result = {} as Sources;

  for (const [field, spec] of Object.entries(patterns) as [keyof Sources, SourcePattern][]) {
    const excludeExact = new Set<string>();
    const excludePrefix: string[] = [];
    for (const ex of (spec.exclude ?? []).map(normalize)) {
      if (ex.endsWith("/**"))
        excludePrefix.push(ex.slice(0, -2)); // keep trailing '/'
      else excludeExact.add(ex);
    }
    const files: string[] = [];
    for (const pt of spec.paths) {
      for (const rel of simpleGlobSync(pt, { cwd: root })) {
        const normalized = normalize(rel);
        if (excludeExact.has(normalized)) continue;
        if (excludePrefix.some(p => normalized.startsWith(p))) continue;
        files.push(resolve(root, normalized));
      }
    }

    files.sort((a, b) => a.localeCompare(b));
    assert(files.length > 0, `Source list '${field}' matched nothing`, {
      file: import.meta.url,
      hint: `Patterns: ${spec.paths.join(", ")}`,
    });

    result[field] = files;
  }

  return result;
}

/** Forward slashes, no leading ./ — for exclude-set comparisons. */
function normalize(p: string): string {
  return p.replace(/\\/g, "/").replace(/^\.\//, "");
}

// ───────────────────────────────────────────────────────────────────────────
// CLI — print one source list to stdout.
// ───────────────────────────────────────────────────────────────────────────

if (process.argv[1] === import.meta.filename) {
  const arg = process.argv[2];
  const sources = globAllSources();
  const print = (list: string[]) => {
    for (const abs of list) console.log(relative(root, abs).replaceAll("\\", "/"));
  };

  if (arg === "--all") {
    for (const list of Object.values(sources)) print(list);
  } else if (arg && arg in sources) {
    print(sources[arg as keyof Sources]);
  } else {
    const msg = arg ? `unknown field '${arg}'` : "usage: bun scripts/glob-sources.ts <field>|--all";
    console.error(`${msg}\nfields: ${Object.keys(sources).join(", ")}`);
    process.exit(1);
  }
}
