// Stellt die Bauteile des Ziel-Portraets aus dem freigegebenen Gemini-Bogen docs/unitframe-src/sheet-ziel-teile-v1.jpg
// (Magenta-Grund #FF00FF) frei und legt sie als RGBA-PNG unter docs/unitframe-src/freigestellt/ziel-*.png ab; die TGAs
// macht danach scripts/gen-unitframe-media.mjs daraus.
//   Freistellen: Magenta-Key wie scripts/media-lib.mjs chromaKey (Alpha aus min(R, B) - G, weiche Kante ueber
//   smoothstep, Magenta-Saum durch Abziehen der Dominanz entfaerbt), dann je Bauteil die zusammenhaengende Flaeche
//   (Alpha >= 64) mit ihrem weichen Rand, zugeschnitten auf die Bounding-Box + Rand.
//   Die beiden Quest-Siegel mit "!" werden bewusst NICHT verwendet (Quest-Symbole wie an den Plaketten).
// Aufruf: node scripts/cut-ziel-teile.mjs   (braucht Chrome/Edge fuer JPG -> PNG, wie media-lib.mjs jpgToPng)
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng } from "./media-lib.mjs";
import { chromaKey } from "./media-lib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = path.join(ROOT, "docs", "unitframe-src", "sheet-ziel-teile-v1.jpg");
const OUT = path.join(ROOT, "docs", "unitframe-src", "freigestellt");
const PAD = 8; // Rand um die Bounding-Box (Quell-Pixel)

// Bauteil -> ungefaehre Mitte im Bogen (2048 x 2048); zugeordnet wird die groesste Flaeche, deren Box die Mitte enthaelt
export const PARTS = {
  "ziel-elite": [550, 520], "ziel-rare": [1560, 520], "ziel-rareelite": [560, 1510], "ziel-boss": [1490, 1350],
  "ziel-marker": [1857, 1203], "ziel-marker-small": [1857, 1522], "ziel-level": [1105, 1850], "ziel-gem": [1362, 1847],
  "ziel-aura": [1608, 1848],
};

function chunk(type, data) {
  const t = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}
export function encodePng({ w, h, rgba }) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

/** zusammenhaengende Flaechen (Alpha >= thr, 4er-Nachbarschaft): Label je Pixel und Boxen */
export function components({ w, h, rgba }, thr = 64) {
  const lab = new Int32Array(w * h).fill(-1);
  const comps = [];
  for (let i = 0; i < w * h; i++) {
    if (lab[i] >= 0 || rgba[i * 4 + 3] < thr) continue;
    const id = comps.length, st = [i];
    lab[i] = id;
    let x0 = w, y0 = h, x1 = 0, y1 = 0, n = 0;
    while (st.length) {
      const j = st.pop(), x = j % w, y = (j / w) | 0;
      n++;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      for (const k of [j - 1, j + 1, j - w, j + w]) {
        if (k < 0 || k >= w * h || lab[k] >= 0 || Math.abs((k % w) - x) > 1) continue;
        if (rgba[k * 4 + 3] >= thr) { lab[k] = id; st.push(k); }
      }
    }
    comps.push({ id, n, x0, y0, x1: x1 + 1, y1: y1 + 1 });
  }
  return { lab, comps };
}

/** Bauteil zuschneiden: eigene Flaeche + weicher Rand (Pixel ohne Label im Rand), fremde Flaechen weg */
export function cut(img, lab, c) {
  const x0 = Math.max(0, c.x0 - PAD), y0 = Math.max(0, c.y0 - PAD);
  const x1 = Math.min(img.w, c.x1 + PAD), y1 = Math.min(img.h, c.y1 + PAD);
  const w = x1 - x0, h = y1 - y0, out = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y + y0) * img.w + x + x0, o = (y * w + x) * 4;
      if (lab[i] !== c.id && lab[i] !== -1) continue;
      for (let k = 0; k < 4; k++) out[o + k] = img.rgba[i * 4 + k];
    }
  }
  return { w, h, rgba: out };
}

function run() {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-ziel-"));
  try {
    const png = path.join(tmp, "sheet.png");
    jpgToPng(SHEET, png);
    const img = chromaKey(decodePng(readFileSync(png)), "magenta");
    const { lab, comps } = components(img);
    for (const [name, [cx, cy]] of Object.entries(PARTS)) {
      const c = comps.filter((k) => k.x0 <= cx && cx < k.x1 && k.y0 <= cy && cy < k.y1).sort((a, b) => b.n - a.n)[0];
      if (!c) throw new Error("Bauteil nicht gefunden: " + name);
      const part = cut(img, lab, c);
      writeFileSync(path.join(OUT, name + ".png"), encodePng(part));
      console.log(`${name}.png: ${part.w} x ${part.h} (Box ${c.x0},${c.y0} - ${c.x1},${c.y1})`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) run();
