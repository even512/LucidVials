// Syntaxcheck aller .lua-Dateien (Addon und Test-Fixtures) mit luaparse als Lua 5.1 (Sprachstand des WoW-Clients).
// Dazu je Addon-Funktion die Zahl der Upvalues: Lua 5.1 erlaubt hoechstens 60, darueber laedt die Datei im Client nicht
// (die Test-VM fengari/Lua 5.3 erlaubt 255 und merkt es nicht). Ab UPVALUE_WARN eine Warnung.
// Aufruf: node scripts/check-lua.mjs   (bzw. npm run check)
// Exit-Codes: 0 = alle Dateien parsen, 1 = Syntaxfehler oder keine Dateien gefunden.

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";
import { UPVALUE_LIMIT, UPVALUE_WARN, countUpvalues } from "./lua-upvalues.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIRS = [path.join(ROOT, "addon"), path.join(ROOT, "tests")];

/** Alle .lua-Dateien unterhalb von dir (ohne Symlinks zu folgen). */
function collect(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...collect(full));
    else if (e.isFile() && e.name.toLowerCase().endsWith(".lua")) out.push(full);
  }
  return out.sort();
}

const files = DIRS.flatMap(collect);
if (files.length === 0) {
  console.error("FEHLER: Keine .lua-Dateien gefunden (erwartet unter addon/ und tests/).");
  process.exit(1);
}

let failed = 0;
for (const file of files) {
  const rel = path.relative(ROOT, file);
  try {
    const code = readFileSync(file, "utf8");
    luaparse.parse(code, { luaVersion: "5.1" });
    if (file.startsWith(path.join(ROOT, "addon"))) {
      for (const fn of countUpvalues(code)) {
        if (fn.count > UPVALUE_LIMIT) {
          failed++;
          console.error(`FEHLER ${rel}: Funktion in Zeile ${fn.line} hat ${fn.count} Upvalues (Lua 5.1: hoechstens ${UPVALUE_LIMIT})`);
        } else if (fn.count >= UPVALUE_WARN) {
          console.warn(`WARNUNG ${rel}: Funktion in Zeile ${fn.line} hat ${fn.count} Upvalues (Grenze ${UPVALUE_LIMIT})`);
        }
      }
    }
  } catch (err) {
    failed++;
    console.error(`FEHLER ${rel}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

if (failed > 0) {
  console.error(`${failed} Fehler in ${files.length} Lua-Datei(en) (Syntax oder Upvalue-Grenze).`);
  process.exit(1);
}
console.log(`Lua-Syntaxcheck (5.1): ${files.length} Datei(en) ok.`);
