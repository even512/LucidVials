// Wasserlinie fuer "Im Kolben versunken" (modules/UnitFrames/Portrait.lua): weicher senkrechter Verlauf, 8 x 64, weiss mit Alpha (ADD, im Spiel
// in der Fluessigkeitsfarbe getoent). Oben sanft einblendend, duenne Lichtlinie (Zeile PEAK), darunter ein Glow, der in die Toenung ausklingt.
// Waagrecht gleichfoermig (die Kreismaske schneidet die Seiten); im Spiel per 8-Wert-TexCoord geneigt/gewellt.
//   node scripts/gen-portrait-waterline.mjs  ->  addon/LucidVials/Media/uf-portrait-waterline.tga
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tgaRgba } from "./media-lib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const WATERLINE = { w: 8, h: 64, peak: 13, line: 2.6, up: 4.5, glow: 0.3, glowLen: 10, fadeFrom: 44 };

const smooth = (x, a, b) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
export function waterlineImage() {
  const { w, h, peak, line, up, glow, glowLen, fadeFrom } = WATERLINE;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const d = y + 0.5 - peak;
    const core = Math.exp(-((d / line) ** 2));
    const halo = d < 0 ? glow * Math.exp(-((d / up) ** 2)) : glow * Math.exp(-d / glowLen) * (1 - smooth(y, fadeFrom, h - 1));
    const a = y === 0 || y === h - 1 ? 0 : Math.min(1, 0.9 * core + halo);
    for (let x = 0; x < w; x++) rgba.set([255, 255, 255, Math.round(a * 255)], (y * w + x) * 4);
  }
  return { w, h, rgba };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const out = path.join(ROOT, "addon", "LucidVials", "Media", "uf-portrait-waterline.tga");
  writeFileSync(out, tgaRgba(waterlineImage()));
  console.log("geschrieben:", path.relative(ROOT, out));
}
