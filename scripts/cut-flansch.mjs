// Stellt die Bronze-Zwingen aus dem freigegebenen Gemini-Bogen docs/unitframe-src/sheet-flansch-v3.jpg (Magenta-Grund
// #FF00FF) frei und legt sie als RGBA-PNG unter docs/unitframe-src/freigestellt/flange-*.png ab; die TGA macht danach
// scripts/gen-unitframe-media.mjs (flangeImage) daraus.
//   Teile (von oben): flange-large (Lebensroehre), flange-small (Manaroehre), flange-pair (beide, mit Stufe links).
//   Freistellen wie scripts/cut-ziel-teile.mjs: Magenta-Key (media-lib.mjs chromaKey), je Teil die
//   zusammenhaengende Flaeche mit weichem Rand.
//   Kuerzen (shorten, nur fuer den klobigen Flansch v2 noetig gewesen): eine zu lange Manschette auf SLEEVE.length x ihre
//   Aussenhoehe kuerzen; der vorhandene linke Abschluss bleibt, ein gerades Stueck wird herausgenommen, die Naht weich
//   ueberblendet (SLEEVE.blend Quell-Pixel). Die Zwingen v3 brauchen das nicht.
// Aufruf: node scripts/cut-flansch.mjs   (braucht Chrome/Edge fuer JPG -> PNG, wie media-lib.mjs jpgToPng)
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng } from "./media-lib.mjs";
import { chromaKey } from "./media-lib.mjs";
import { components, cut, encodePng } from "./cut-ziel-teile.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = path.join(ROOT, "docs", "unitframe-src", "sheet-flansch-v3.jpg");
const OUT = path.join(ROOT, "docs", "unitframe-src", "freigestellt");

// Teil -> Punkt im Teil (Bogen 2048 x 2048), Zeile durch die Mitte der Manschette, kuerzen ja/nein
export const PARTS = {
  "flange-large": { at: [1050, 400], row: null, shorten: false },
  "flange-small": { at: [1040, 1020], row: null, shorten: false },
  "flange-pair": { at: [1040, 1640], row: null, shorten: false },
};
// Manschetten-Laenge (x Aussenhoehe, ab linker Aussenkante bis Ende der Innenflaeche), behaltener linker Abschluss
// (x Aussenhoehe ab linker Aussenkante), Ueberblendung an der Naht (Quell-Pixel)
export const SLEEVE = { length: 1.5, keep: 0.45, blend: 16 };

const opaque = (img, x, y) => img.rgba[(y * img.w + x) * 4 + 3] >= 128;

/** Manschette in Zeile row vermessen: linke Aussenkante, Ende der Innenflaeche (Beginn der Platte), Aussenhoehe */
export function measureSleeve(img, row) {
  let x = 0;
  while (x < img.w && !opaque(img, x, row)) x++;
  const left = x;
  while (x < img.w && opaque(img, x, row)) x++; // linker Rand der Manschette
  while (x < img.w && !opaque(img, x, row)) x++; // Innenflaeche (durchsichtig)
  const innerEnd = x;
  if (left >= img.w || innerEnd >= img.w) throw new Error("Manschette nicht erkannt (Zeile " + row + ")");
  const col = Math.round(left + (innerEnd - left) * 0.5);
  let top = row, bottom = row;
  while (top > 0 && !opaque(img, col, top)) top--;
  while (top > 0 && opaque(img, col, top - 1)) top--;
  while (bottom < img.h - 1 && !opaque(img, col, bottom)) bottom++;
  while (bottom < img.h - 1 && opaque(img, col, bottom + 1)) bottom++;
  return { left, innerEnd, top, bottom: bottom + 1, height: bottom + 1 - top };
}

/** gerades Stueck der Manschette herausnehmen: links bleibt [0, s), dann folgt die Quelle ab s + cut (weich ueberblendet) */
export function shortenSleeve(img, m) {
  const cutLen = Math.round(m.innerEnd - m.left - SLEEVE.length * m.height);
  if (cutLen <= 0) return { img, cut: 0 };
  const s = Math.round(m.left + SLEEVE.keep * m.height), B = SLEEVE.blend;
  if (s + cutLen - B <= s) throw new Error("Manschette zu kurz zum Kuerzen");
  const w = img.w - cutLen, out = new Uint8Array(w * img.h * 4);
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      if (x < s - B) {
        out.set(img.rgba.subarray((y * img.w + x) * 4, (y * img.w + x) * 4 + 4), o);
        continue;
      }
      const b = (y * img.w + x + cutLen) * 4;
      if (x >= s) {
        out.set(img.rgba.subarray(b, b + 4), o);
        continue;
      }
      // Naht: vormultipliziert ueberblenden (links Abschluss, rechts Fortsetzung)
      const a = (y * img.w + x) * 4, t = (x - (s - B) + 0.5) / B;
      const aa = img.rgba[a + 3] * (1 - t), ab = img.rgba[b + 3] * t, al = aa + ab;
      if (al <= 0) continue;
      for (let k = 0; k < 3; k++) out[o + k] = Math.round((img.rgba[a + k] * aa + img.rgba[b + k] * ab) / al);
      out[o + 3] = Math.round(al);
    }
  }
  return { img: { w, h: img.h, rgba: out }, cut: cutLen };
}

/** Restmagenta zaehlen (deckende Pixel mit Magenta-Stich: R und B deutlich ueber G) */
export function magentaLeft(img) {
  let n = 0;
  for (let i = 0; i < img.w * img.h; i++) {
    const o = i * 4;
    if (img.rgba[o + 3] >= 32 && Math.min(img.rgba[o], img.rgba[o + 2]) - img.rgba[o + 1] > 40) n++;
  }
  return n;
}

function run() {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-flansch-"));
  try {
    const png = path.join(tmp, "sheet.png");
    jpgToPng(SHEET, png);
    const img = chromaKey(decodePng(readFileSync(png)), "magenta");
    const { lab, comps } = components(img);
    for (const [name, P] of Object.entries(PARTS)) {
      const [cx, cy] = P.at;
      const c = comps.filter((k) => k.x0 <= cx && cx < k.x1 && k.y0 <= cy && cy < k.y1).sort((a, b) => b.n - a.n)[0];
      if (!c) throw new Error("Teil nicht gefunden: " + name);
      let part = cut(img, lab, c), info = "";
      if (P.shorten) {
        const m = measureSleeve(part, P.row - Math.max(0, c.y0 - 8));
        const r = shortenSleeve(part, m);
        part = r.img;
        info = ` Manschette ${m.innerEnd - m.left} -> ${m.innerEnd - m.left - r.cut} (Hoehe ${m.height})`;
      }
      writeFileSync(path.join(OUT, name + ".png"), encodePng(part));
      console.log(`${name}.png: ${part.w} x ${part.h} (Box ${c.x0},${c.y0} - ${c.x1},${c.y1})${info}, Magenta-Reste ${magentaLeft(part)}`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) run();
