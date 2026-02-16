import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, "..", "..");

/**
 * Resolve a preset file argument to an absolute path.
 * Handles bare names like "api-design", relative paths, and full paths.
 * Returns null if not found.
 */
export function resolvePresetPath(file) {
  let filePath = resolve(PROJECT_ROOT, file);
  if (existsSync(filePath)) return filePath;
  const candidates = [
    resolve(PROJECT_ROOT, "presets", file),
    resolve(PROJECT_ROOT, "presets", `${file}.json`),
    resolve(PROJECT_ROOT, `${file}.json`),
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return null;
}

/**
 * Extract all ${VAR} and ${VAR:-default} placeholders from a preset file.
 * Returns deduplicated list in order of first appearance.
 *
 * @param {string} filePath - Absolute path to preset JSON
 * @returns {{ name: string, defaultValue: string|null }[]}
 */
export function extractPresetVars(filePath) {
  const raw = readFileSync(filePath, "utf-8");
  const pattern = /\$\{([A-Z_][A-Z0-9_]*)(?::-([^}]*))?\}/g;
  const seen = new Set();
  const vars = [];
  let match;
  while ((match = pattern.exec(raw)) !== null) {
    const name = match[1];
    if (seen.has(name)) continue;
    seen.add(name);
    const defaultValue = match[2] !== undefined ? match[2] : null;
    vars.push({ name, defaultValue });
  }
  return vars;
}

/**
 * Parse inline KEY=VALUE pairs from command args.
 * Returns { envOverrides, remainingArgs } where envOverrides has the KEY=VALUE
 * pairs and remainingArgs has everything else (file paths, flags).
 */
export function parseInlineVars(args) {
  const envOverrides = {};
  const remainingArgs = [];
  for (const arg of args) {
    const m = arg.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (m) {
      envOverrides[m[1]] = m[2];
    } else {
      remainingArgs.push(arg);
    }
  }
  return { envOverrides, remainingArgs };
}
