// Schneidet die Portrait-Texturen aus dem freigegebenen Gemini-Bogen docs/unitframe-src/sheet-portrait-v1.jpg (2400 x 1792, 3 x 2
// Raster, Graustufen auf Schwarz) als Kreise aus und schreibt 256 x 256 RGBA-TGA (32 bit) nach addon/LucidVials/Media/:
//   1 uf-portrait-cracks        Glasrisse leicht   (Alpha aus Helligkeit, kaltweiss) - NICHT aus dem Bogen, sondern aus cracks-dezent-v1.jpg (cutCracks)
//   2 uf-portrait-cracks-heavy  Glasrisse stark    (sehr wenig Leben)                  - dito, zweite Stufe aus derselben Quelle
//   3 uf-portrait-vignette      Vignette           (Alpha = Helligkeit, Farbe schwarz)
//   4 uf-portrait-candle        Kerzenlicht von oben links (Alpha = Helligkeit, weiss, Farbe per Vertexfarbe, ADD)
//   5 uf-portrait-heal          Heilschein mit Lichtpunkten (Alpha = Helligkeit, weiss, ADD)
//   6 uf-portrait-gloss         Glasglanz-Bogen    (Alpha = Helligkeit, weiss, ADD)
// Je Zelle: Kreis aus den hellen Pixeln gemessen (Mittelpunkt, Radius), die Zelle wird auf Maskenradius RIM x Kreisradius
// zugeschnitten (die graue Kreislinie am Rand faellt weg) und weich ausgeblendet (FEATHER); der Kreis fuellt die ganze Textur.
// Aufruf: node scripts/cut-portrait.mjs   (braucht Chrome/Edge fuer JPG -> PNG, wie media-lib.mjs jpgToPng)
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { decodePng, jpgToPng, tgaRgba } from "./media-lib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = path.join(ROOT, "docs", "unitframe-src", "sheet-portrait-v1.jpg");
const CRACKS_SRC = path.join(ROOT, "docs", "unitframe-src", "cracks-dezent-v1.jpg");
const MEDIA =path.join(ROOT, "addon", "LucidVials", "Media");
export const SIZE = 256;
export const RIM = 0.94;       // Maskenradius / gemessener Kreisradius (die graue Kreislinie liegt aussen davon)
export const FEATHER = 0.07;   // weicher Rand: Anteil des Texturradius
export const THRESH = 14;      // Helligkeit (0..255), ab der ein Pixel zum Kreis zaehlt
export const CELLS = [
  { name: "uf-portrait-vignette", col: 2, row: 0, kind: "dark" },
  { name: "uf-portrait-candle", col: 0, row: 1, kind: "light" },
  { name: "uf-portrait-heal", col: 1, row: 1, kind: "light" },
  { name: "uf-portrait-gloss", col: 2, row: 1, kind: "light" },
];

const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

/** Kreis in der Zelle: Mittelpunkt und Radius aus der Umgebung der hellen Pixel */
export function measureCircle(img, x0, y0, w, h) {
  let minX = 1e9, maxX = -1, minY = 1e9, maxY = -1;
  for (let y = y0; y < y0 + h; y++) {
    for (let x = x0; x < x0 + w; x++) {
      if (img.rgba[(y * img.w + x) * 4] >= THRESH) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) throw new Error("kein Kreis in der Zelle");
  return { cx: (minX + maxX + 1) / 2, cy: (minY + maxY + 1) / 2, r: Math.min(maxX - minX + 1, maxY - minY + 1) / 2 };
}

function sample(img, x, y) {
  x = Math.min(img.w - 1.001, Math.max(0, x - 0.5));
  y = Math.min(img.h - 1.001, Math.max(0, y - 0.5));
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const g = (a, b) => img.rgba[((iy + b) * img.w + ix + a) * 4];
  return (g(0, 0) * (1 - fx) * (1 - fy) + g(1, 0) * fx * (1 - fy) + g(0, 1) * (1 - fx) * fy + g(1, 1) * fx * fy) / 255;
}

/** eine Zelle -> RGBA (SIZE x SIZE): Kreis, Alpha aus der Helligkeit, weicher Rand */
export function cutCell(img, cell, grid) {
  const cw = img.w / grid.cols, ch = img.h / grid.rows;
  const c = measureCircle(img, Math.round(cell.col * cw), Math.round(cell.row * ch), Math.round(cw), Math.round(ch));
  const R = c.r * RIM;
  const rgba = new Uint8Array(SIZE * SIZE * 4);
  for (let j = 0; j < SIZE; j++) {
    for (let i = 0; i < SIZE; i++) {
      const u = (i + 0.5) / SIZE * 2 - 1, v = (j + 0.5) / SIZE * 2 - 1;
      const lum = sample(img, c.cx + u * R, c.cy + v * R);
      const mask = 1 - smooth(Math.hypot(u, v), 1 - FEATHER, 1);
      let r, g, b, a;
      if (cell.kind === "cracks") {
        a = smooth(lum, 0.05, 0.6);
        const k = 0.7 + 0.3 * lum;
        [r, g, b] = [k * 0.9, k * 0.96, k];
      } else if (cell.kind === "dark") {
        a = lum;
        [r, g, b] = [0.02, 0.015, 0.01];
      } else {
        a = lum;
        [r, g, b] = [1, 1, 1];
      }
      a *= mask;
      const o = (j * SIZE + i) * 4;
      rgba[o] = Math.round(r * 255); rgba[o + 1] = Math.round(g * 255); rgba[o + 2] = Math.round(b * 255); rgba[o + 3] = Math.round(a * 255);
    }
  }
  return { w: SIZE, h: SIZE, rgba };
}

// ---- Glasrisse aus cracks-dezent-v1.jpg (2048 x 2048, weisse Sprunglinien auf Schwarz, Einschlag bei ca. x 0,78 / y 0,70) ----
export const CRACK_CROP = { cx: 1200, cy: 1250, r: 800 }; // Quellkreis (Pixel): Einschlag liegt bei ~0,53 R unten rechts, Linien laufen bis zum Rand
export const CRACK_GROW = 3;     // Dilatation (Max-Filter, Quellpixel): macht aus ~2 px Linien ~8 px, am Ende (6,25 Quellpixel je Texel) ~1-1,5 px
export const CRACK_GAIN = 1.5;   // Helligkeit -> Alpha (nach dem Verkleinern), damit die duenne Linie nicht verblasst
export const HEAVY_K = 0.6;      // Helligkeit der zweiten Kopie der starken Stufe
export const HEAVY_SHIFT = [0.42, 0.75]; // Versatz der gespiegelten Kopie (Radien): Einschlag wandert von (+0.53,+0.2) nach ca. (-0.95,-0.55)
const SS = 4;                    // Supersampling je Achse beim Verkleinern (Flaechenmittel statt Aliasing)

/** Max-Filter (Quadrat, Radius rad, separabel) der Rotkanal-Helligkeit -> Float32Array w*h (0..1) */
export function dilate(img, rad) {
  const { w, h } = img, a = new Float32Array(w * h), b = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = img.rgba[i * 4] / 255;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let m = 0;
    for (let k = -rad; k <= rad; k++) { const xx = x + k; if (xx >= 0 && xx < w && a[y * w + xx] > m) m = a[y * w + xx]; }
    b[y * w + x] = m;
  }
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let m = 0;
    for (let k = -rad; k <= rad; k++) { const yy = y + k; if (yy >= 0 && yy < h && b[yy * w + x] > m) m = b[yy * w + x]; }
    out[y * w + x] = m;
  }
  return out;
}

/** Riss-Texturen: heavy=false -> leichte Stufe (die Quelle), heavy=true -> starke Stufe (Quelle + gespiegelte, zum Rand versetzte Kopie, mehr Brueche) */
export function cutCracks(img, { heavy = false } = {}) {
  const dil = dilate(img, CRACK_GROW), { cx, cy, r } = CRACK_CROP;
  const at = (x, y) => {
    const ix = Math.min(img.w - 1, Math.max(0, Math.floor(x))), iy = Math.min(img.h - 1, Math.max(0, Math.floor(y)));
    return dil[iy * img.w + ix];
  };
  const rgba = new Uint8Array(SIZE * SIZE * 4);
  for (let j = 0; j < SIZE; j++) {
    for (let i = 0; i < SIZE; i++) {
      let sum = 0;
      for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
        const u = (i + (sx + 0.5) / SS) / SIZE * 2 - 1, v = (j + (sy + 0.5) / SS) / SIZE * 2 - 1;
        let l = at(cx + u * r, cy + v * r);
        if (heavy) l = Math.max(l, HEAVY_K * at(cx - (u + HEAVY_SHIFT[0]) * r, cy + (v + HEAVY_SHIFT[1]) * r)); // zweite Kopie: gespiegelt, Einschlag zum Rand oben links versetzt
        sum += l;
      }
      const lum = Math.min(1, sum / (SS * SS) * CRACK_GAIN);
      const u = (i + 0.5) / SIZE * 2 - 1, v = (j + 0.5) / SIZE * 2 - 1;
      const a = smooth(lum, 0.04, 0.55) * (1 - smooth(Math.hypot(u, v), 1 - FEATHER, 1));
      const k = 0.7 + 0.3 * lum, o = (j * SIZE + i) * 4;
      rgba[o] = Math.round(k * 0.9 * 255); rgba[o + 1] = Math.round(k * 0.96 * 255); rgba[o + 2] = Math.round(k * 255); rgba[o + 3] = Math.round(a * 255);
    }
  }
  return { w: SIZE, h: SIZE, rgba };
}

export function cutAll(sheetPng) {
  const img = decodePng(readFileSync(sheetPng));
  const grid = { cols: 3, rows: 2 };
  return CELLS.map((cell) => ({ cell, tex: cutCell(img, cell, grid) }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "portrait-"));
  try {
    const png = path.join(tmp, "sheet.png");
    jpgToPng(SHEET, png);
    for (const { cell, tex } of cutAll(png)) {
      writeFileSync(path.join(MEDIA, cell.name + ".tga"), tgaRgba(tex));
      console.log("geschrieben:", cell.name, `${SIZE}x${SIZE}`);
    }
    const crackPng = path.join(tmp, "cracks.png");
    jpgToPng(CRACKS_SRC, crackPng);
    const crackImg = decodePng(readFileSync(crackPng));
    for (const [name, heavy] of [["uf-portrait-cracks", false], ["uf-portrait-cracks-heavy", true]]) {
      writeFileSync(path.join(MEDIA, name + ".tga"), tgaRgba(cutCracks(crackImg, { heavy })));
      console.log("geschrieben:", name, `${SIZE}x${SIZE}`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
