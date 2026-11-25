// Stellt den Portraetring mit Rohraufnahmen aus dem freigegebenen Gemini-Bogen docs/unitframe-src/sheet-ring-aufnahme-v4.jpg
// (Magenta-Grund #FF00FF, Ring-Innenflaeche und die beiden Rohrfenster ebenfalls Magenta) frei und legt ihn als RGBA-PNG
// unter docs/unitframe-src/freigestellt/ring-aufnahme.png ab; die TGA (uf-ring-aufnahme) und die Lage (Deco.GEO.socket)
// macht danach scripts/gen-unitframe-media.mjs (socketImage / socketGeometry) daraus.
//   Freistellen wie scripts/cut-ziel-teile.mjs: Magenta-Key (media-lib.mjs chromaKey, wirkt je Pixel, also auch in
//   den eingeschlossenen Innenflaechen), dann die groesste zusammenhaengende Flaeche mit weichem Rand; Saum entfaerbt
//   gen-unitframe-media.mjs cleanFringe beim Erzeugen der TGA.
// Aufruf: node scripts/cut-ring-aufnahme.mjs   (braucht Chrome/Edge fuer JPG -> PNG, wie media-lib.mjs jpgToPng)
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng } from "./media-lib.mjs";
import { chromaKey } from "./media-lib.mjs";
import { components, cut, encodePng } from "./cut-ziel-teile.mjs";
import { magentaLeft } from "./cut-flansch.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = path.join(ROOT, "docs", "unitframe-src", "sheet-ring-aufnahme-v4.jpg");
const OUT = path.join(ROOT, "docs", "unitframe-src", "freigestellt", "ring-aufnahme.png");

function run() {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-ring-aufnahme-"));
  try {
    const png = path.join(tmp, "sheet.png");
    jpgToPng(SHEET, png);
    const img = chromaKey(decodePng(readFileSync(png)), "magenta");
    const { lab, comps } = components(img);
    const c = comps.sort((a, b) => b.n - a.n)[0];
    if (!c) throw new Error("Ring nicht gefunden");
    const part = cut(img, lab, c);
    writeFileSync(OUT, encodePng(part));
    console.log(`ring-aufnahme.png: ${part.w} x ${part.h} (Box ${c.x0},${c.y0} - ${c.x1},${c.y1}), Magenta-Reste ${magentaLeft(part)}`);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) run();
