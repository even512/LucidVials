// Schneidet die Teile des Einstellungsfensters aus dem freigegebenen Textur-Bogen docs/config-src/sheet-config-v1.jpg (2048 x 2048,
// reines Gruen #00FF00 als Hintergrund, Ziffern daneben werden nicht mitgenommen) und schreibt RGBA-TGA (32 bit, Zweierpotenzen)
// nach addon/LucidVials/Media/config/. Zielbild: docs/config-src/entwurf-config-v1.jpg.
//   1  corner                 Ecke oben links (Rand + Ornament, Innenflaeche durchsichtig; andere Ecken per Spiegelung)
//   edge-h / edge-v           Rand waagrecht / senkrecht, kachelbar, aus den geraden Armen der Ecke (1) geschnitten (die Leisten 2
//                             und 3 im Bogen haben ein anderes Profil und passen an der Ecke nicht)
//   4  title                  Titelschild, 3-Slice, Innenflaeche durchsichtig (darunter liegt die Flaechenkachel)
//   5  tab-off, 6 tab-on      Reiter inaktiv / aktiv, 3-Slice (mit Fuss)
//   7  inset                  Vorschau-Mulde, 9-Slice, Innenflaeche durchsichtig
//   8  slider-track, -knob    Schieberrinne (3-Slice) und Knopf
//   9  check-off, check-on    Haekchen-Box leer / gesetzt (gleiche Lage der Box, der Haken ragt rechts oben heraus)
//   10 dropdown               Dropdown, 3-Slice (rechte Kappe mit Pfeil-Knopf)
//   11 scroll-up/-down/-track/-thumb   Scrollleiste: Pfeil-Knoepfe, Rinne (senkrecht dehnbar), Daumen
//   12 divider                Trennlinie, 3-Slice (linke Kappe mit dem kleinen Ornament)
//   13 fill                   Flaechenkachel, nahtlos (Kanten-Ueberblendung, grossflaechige Helligkeit ausgeglichen)
// Freistellen: Alpha aus der Gruen-Dominanz (weiche Kante), Gruen-Saum entsaettigt (G nie ueber max(R, B)); Verkleinern als
// Flaechenmittel in vormultipliziertem Alpha (kein dunkler oder gruener Saum). Die Masse (PARTS) stehen gleich in UI/ConfigWidgets.lua
// (W.SKIN); tests/config-skin.test.mjs vergleicht beide.
// Aufruf: node scripts/cut-config.mjs   (braucht Chrome/Edge fuer JPG -> PNG, wie media-lib.mjs jpgToPng)
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng, tgaRgba } from "./media-lib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SHEET = path.join(ROOT, "docs", "config-src", "sheet-config-v1.jpg");
export const OUT_DIR = path.join(ROOT, "addon", "LucidVials", "Media", "config");

// Rand: Tiefe der Randleiste im Bogen (Quellpunkte ab der Aussenkante) und Ecken-Ausschnitt; Anzeige im Fenster BORDER x CORNER
export const RIM_DEPTH = 48; // Aussenlinie, Bronzeband, Braunband, Schattenlinie
export const RIM_FADE = [41, 46]; // innen weich ausblenden (gleich an Kanten und Ecke): Schattenlinie bleibt, Innenflaeche nicht
const EDGE_SEAM = 32; // Ueberblendung der Kanten-Kachel (Quellpunkte)
export const CORNER_SRC = 240; // Ecken-Ausschnitt (Rand + Ornament)
export const EDGE_TILE_SRC = 192; // Laenge einer Rand-Kachel im Bogen

/**
 * Teile: src = Ausschnitt im Bogen { x, y, w, h }, size = [Breite, Hoehe] der TGA; caps = 3-Slice-Kappen in Quellpunkten
 * (l, r waagrecht bzw. t, b senkrecht), slice9 = Ecke des 9-Slice in Quellpunkten.
 */
export const PARTS = {
  // Ziffer "1)" liegt im Ecken-Ausschnitt (rechts unten im Gruen neben dem L), wird geloescht
  corner: { src: { x: 39, y: 40, w: CORNER_SRC, h: CORNER_SRC }, size: [128, 128], kind: "corner", erase: [{ x: 225, y: 215, w: 80, h: 100 }] },
  // Kanten aus den geraden Armen der Ecke (1) statt aus 2/3: dort passen Profil, Linienlage und Farbe sicher zur Ecke
  "edge-h": { src: { x: 288, y: 40, w: EDGE_TILE_SRC + EDGE_SEAM, h: RIM_DEPTH }, size: [128, 32], kind: "edge-h" },
  "edge-v": { src: { x: 39, y: 290, w: RIM_DEPTH, h: EDGE_TILE_SRC + EDGE_SEAM }, size: [32, 128], kind: "edge-v" },
  title: { src: { x: 382, y: 312, w: 1326, h: 266 }, size: [512, 128], caps: { l: 153, r: 153 }, hollow: 0.36 },
  "tab-off": { src: { x: 108, y: 745, w: 608, h: 192 }, size: [256, 64], caps: { l: 76, r: 76 } },
  // Ziffer "6)" ragt links oben in den Ausschnitt: dort ist nur Gruen und Ziffer, wird geloescht
  "tab-on": { src: { x: 788, y: 736, w: 586, h: 202 }, size: [256, 64], caps: { l: 84, r: 81 }, erase: [{ x: 780, y: 740, w: 30, h: 105 }] },
  inset: { src: { x: 1501, y: 737, w: 508, h: 508 }, size: [256, 256], slice9: 58, hollow: 0.3 },
  "slider-track": { src: { x: 138, y: 1070, w: 956, h: 74 }, size: [512, 32], caps: { l: 39, r: 39 } },
  "slider-knob": { src: { x: 1126, y: 1046, w: 124, h: 124 }, size: [64, 64] },
  "check-off": { src: { x: 140, y: 1240, w: 216, h: 216 }, size: [64, 64], box: { x: 8, y: 44, w: 166, h: 166 } },
  "check-on": { src: { x: 400, y: 1240, w: 216, h: 216 }, size: [64, 64], box: { x: 8, y: 44, w: 166, h: 166 } },
  dropdown: { src: { x: 141, y: 1567, w: 740, h: 156 }, size: [256, 64], caps: { l: 37, r: 131 } },
  "scroll-up": { src: { x: 1052, y: 1282, w: 111, h: 108 }, size: [64, 64] },
  "scroll-down": { src: { x: 1052, y: 1894, w: 111, h: 108 }, size: [64, 64] },
  "scroll-track": { src: { x: 1052, y: 1500, w: 111, h: 380 }, size: [64, 256] },
  "scroll-thumb": { src: { x: 1070, y: 1387, w: 79, h: 84 }, size: [64, 64] },
  divider: { src: { x: 153, y: 1848, w: 851, h: 76 }, size: [512, 32], caps: { l: 503, r: 26 } },
  fill: { src: { x: 1430, y: 1430, w: 550, h: 550 }, size: [256, 256], kind: "fill" },
};

const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

// Bild als Float-Puffer: { w, h, r, g, b, a } (0..1, nicht vormultipliziert)
function blank(w, h) {
  return { w, h, r: new Float32Array(w * h), g: new Float32Array(w * h), b: new Float32Array(w * h), a: new Float32Array(w * h) };
}

/** Freistellen des ganzen Bogens: Alpha aus G - max(R, B), Gruen-Saum entfernt */
export function keySheet(img) {
  const out = blank(img.w, img.h);
  for (let i = 0; i < img.w * img.h; i++) {
    const r = img.rgba[i * 4], g = img.rgba[i * 4 + 1], b = img.rgba[i * 4 + 2];
    const k = g - Math.max(r, b);
    let a = 1 - smooth(k, 22, 105);
    if (a < 0.03) a = 0;
    out.r[i] = r / 255;
    out.g[i] = Math.min(g, Math.max(r, b) + 2) / 255; // Gruenstich weg (Bronze/Braun haben nie G ueber R)
    out.b[i] = b / 255;
    out.a[i] = a;
  }
  return out;
}

function crop(img, { x, y, w, h }) {
  const out = blank(w, h);
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const sx = x + i, sy = y + j, o = j * w + i;
      if (sx < 0 || sy < 0 || sx >= img.w || sy >= img.h) continue;
      const s = sy * img.w + sx;
      out.r[o] = img.r[s]; out.g[o] = img.g[s]; out.b[o] = img.b[s]; out.a[o] = img.a[s];
    }
  }
  return out;
}

/** Verkleinern/Vergroessern als Flaechenmittel (Box-Filter mit Teilpunkten) in vormultipliziertem Alpha */
export function resample(img, W, H) {
  const out = blank(W, H);
  const sx = img.w / W, sy = img.h / H;
  const nx = Math.max(2, Math.ceil(sx) * 2), ny = Math.max(2, Math.ceil(sy) * 2);
  const at = (x, y) => {
    // bilineare Abtastung (vormultipliziert)
    x = Math.min(img.w - 1, Math.max(0, x - 0.5));
    y = Math.min(img.h - 1, Math.max(0, y - 0.5));
    const x0 = Math.floor(x), y0 = Math.floor(y), x1 = Math.min(img.w - 1, x0 + 1), y1 = Math.min(img.h - 1, y0 + 1);
    const fx = x - x0, fy = y - y0;
    const res = [0, 0, 0, 0];
    for (const [xx, yy, wgt] of [[x0, y0, (1 - fx) * (1 - fy)], [x1, y0, fx * (1 - fy)], [x0, y1, (1 - fx) * fy], [x1, y1, fx * fy]]) {
      const s = yy * img.w + xx, a = img.a[s] * wgt;
      res[0] += img.r[s] * a; res[1] += img.g[s] * a; res[2] += img.b[s] * a; res[3] += a;
    }
    return res;
  };
  for (let j = 0; j < H; j++) {
    for (let i = 0; i < W; i++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let v = 0; v < ny; v++) {
        for (let u = 0; u < nx; u++) {
          const p = at((i + (u + 0.5) / nx) * sx, (j + (v + 0.5) / ny) * sy);
          r += p[0]; g += p[1]; b += p[2]; a += p[3];
        }
      }
      const n = nx * ny, o = j * W + i;
      out.a[o] = a / n;
      if (a > 0) { out.r[o] = r / a; out.g[o] = g / a; out.b[o] = b / a; }
    }
  }
  return out;
}

/** nahtlos kachelbar in x und/oder y: Quelle ist um m laenger, Anfang wird mit dem Ueberstand ueberblendet */
function seamless(img, m, axis) {
  const W = axis === "x" ? img.w - m : img.w, H = axis === "y" ? img.h - m : img.h;
  const out = blank(W, H);
  for (let j = 0; j < H; j++) {
    for (let i = 0; i < W; i++) {
      const o = j * W + i, s = j * img.w + i;
      const t = axis === "x" ? i : j;
      const s2 = axis === "x" ? j * img.w + i + W : (j + H) * img.w + i;
      if (t >= m) {
        for (const c of ["r", "g", "b", "a"]) out[c][o] = img[c][s];
        continue;
      }
      const k = smooth(t, 0, m); // bei t = 0 ganz der Ueberstand (schliesst ans Ende an)
      for (const c of ["r", "g", "b", "a"]) out[c][o] = img[c][s] * k + img[c][s2] * (1 - k);
    }
  }
  return out;
}

/** Flaechenkachel: grossflaechige Helligkeitsverlaeufe herausrechnen (Mittelwert bleibt), dann nahtlos in x und y */
function flattenFill(img) {
  const R = 60, w = img.w, h = img.h;
  const mean = { r: 0, g: 0, b: 0 };
  for (let i = 0; i < w * h; i++) { mean.r += img.r[i]; mean.g += img.g[i]; mean.b += img.b[i]; }
  for (const c of ["r", "g", "b"]) mean[c] /= w * h;
  // Kastenunschaerfe als Integralbild je Kanal
  const out = blank(w, h);
  for (const c of ["r", "g", "b"]) {
    const I = new Float64Array((w + 1) * (h + 1));
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) I[(j + 1) * (w + 1) + i + 1] = img[c][j * w + i] + I[j * (w + 1) + i + 1] + I[(j + 1) * (w + 1) + i] - I[j * (w + 1) + i];
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        const x0 = Math.max(0, i - R), x1 = Math.min(w, i + R + 1), y0 = Math.max(0, j - R), y1 = Math.min(h, j + R + 1);
        const sum = I[y1 * (w + 1) + x1] - I[y0 * (w + 1) + x1] - I[y1 * (w + 1) + x0] + I[y0 * (w + 1) + x0];
        const blur = sum / ((x1 - x0) * (y1 - y0));
        out[c][j * w + i] = Math.max(0, Math.min(1, img[c][j * w + i] - blur + mean[c]));
      }
    }
  }
  out.a.fill(1);
  return out;
}

/** Randleiste: Tiefe d (Quellpunkte ab der Aussenkante) -> Deckkraft */
const rimAlpha = (d) => 1 - smooth(d, RIM_FADE[0], RIM_FADE[1]);


/**
 * Flutfuellung ab seeds ueber dunkle Punkte (Helligkeit < thr; mit throughClear auch ueber durchsichtige) -> weiche Behalte-Maske
 * (1 = bleibt): nicht Geflutetes, um grow px erweitert (dunkle Konturen bleiben als Saum), dann 1 px weich
 */
function keepMask(img, seeds, thr, throughClear, grow = 2, largestOnly = false) {
  const { w, h } = img;
  const lum = (o) => (img.r[o] + img.g[o] + img.b[o]) / 3;
  const flood = new Uint8Array(w * h);
  const stack = [];
  for (const [x, y] of seeds) { const o = y * w + x; flood[o] = 1; stack.push(o); }
  while (stack.length) {
    const o = stack.pop(), x = o % w, y = (o / w) | 0;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      const q = ny * w + nx;
      if (flood[q]) continue;
      if ((throughClear && img.a[q] < 0.5) || (img.a[q] >= 0.5 && lum(q) < thr)) { flood[q] = 1; stack.push(q); }
    }
  }
  let keep = new Float32Array(w * h);
  for (let o = 0; o < w * h; o++) keep[o] = flood[o] ? 0 : 1;
  if (largestOnly) {
    // nur das groesste zusammenhaengende Stueck (der Rahmen) bleibt; Inseln in der Innenflaeche (Glanzlinien, Flecken) fallen weg
    const lab = new Int32Array(w * h);
    let best = 0, bestN = 0, n = 0;
    for (let s0 = 0; s0 < w * h; s0++) {
      if (!keep[s0] || img.a[s0] < 0.5 || lab[s0]) continue;
      n++;
      let cnt = 0;
      const st = [s0];
      lab[s0] = n;
      while (st.length) {
        const o = st.pop(), x = o % w;
        cnt++;
        for (const q of [o - 1, o + 1, o - w, o + w]) {
          if (q < 0 || q >= w * h || Math.abs((q % w) - x) > 1) continue;
          if (keep[q] && img.a[q] >= 0.5 && !lab[q]) { lab[q] = n; st.push(q); }
        }
      }
      if (cnt > bestN) { bestN = cnt; best = n; }
    }
    for (let o = 0; o < w * h; o++) if (lab[o] !== best && img.a[o] >= 0.5) keep[o] = 0;
  }
  const dilate = (src) => {
    const dst = new Float32Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      let m = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < w && ny < h && src[ny * w + nx] > m) m = src[ny * w + nx];
      }
      dst[y * w + x] = m;
    }
    return dst;
  };
  for (let i = 0; i < grow; i++) keep = dilate(keep);
  const soft = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let sum = 0, n = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const nx = x + dx, ny = y + dy;
      if (nx >= 0 && ny >= 0 && nx < w && ny < h) { sum += keep[ny * w + nx]; n++; }
    }
    soft[y * w + x] = sum / n;
  }
  return soft;
}

/**
 * Ecke: Randprofil (Tiefe < RIM_DEPTH, gleiche Ausblendung wie die Kanten, die aus den geraden Armen derselben Ecke stammen) plus
 * Ornament; die dunkle Innenflaeche wird per Flutfuellung von der Innenseite her durchsichtig, damit ueberall dieselbe
 * Flaechenkachel durchscheint (dunkle Konturen des Ornaments bleiben als 2-px-Saum).
 */
function cutCorner(sheet) {
  const img = crop(sheet, PARTS.corner.src);
  const { w, h } = img;
  const keep = keepMask(img, [[w - 1, h - 1]], 0.25, true);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = y * w + x;
    img.a[o] = Math.max(rimAlpha(Math.min(x, y)), keep[o]) * img.a[o];
  }
  return img;
}

/** Innenflaeche eines Teils durchsichtig (Titelschild, Mulde): Flutfuellung ab der Mitte ueber dunkle, deckende Punkte */
function hollow(img, thr) {
  const keep = keepMask(img, [[img.w >> 1, img.h >> 1]], thr, false, 1, true);
  for (let o = 0; o < img.w * img.h; o++) img.a[o] *= keep[o];
  return img;
}

// Kanten aus den geraden Armen der Ecke (gleiches Profil, gleiche Farbe, gleiche Tiefe ab der Aussenkante)
function cutEdgeH(sheet) {
  const img = seamless(crop(sheet, PARTS["edge-h"].src), EDGE_SEAM, "x");
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) img.a[y * img.w + x] *= rimAlpha(y);
  return img;
}

function cutEdgeV(sheet) {
  const img = seamless(crop(sheet, PARTS["edge-v"].src), EDGE_SEAM, "y");
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) img.a[y * img.w + x] *= rimAlpha(x);
  return img;
}

/** Float-Bild -> { w, h, rgba } (8 bit); volltransparente Punkte schwarz */
export function toRgba(img) {
  const rgba = new Uint8Array(img.w * img.h * 4);
  for (let i = 0; i < img.w * img.h; i++) {
    const a = img.a[i];
    if (a <= 0.004) continue;
    rgba[i * 4] = Math.round(Math.min(1, img.r[i]) * 255);
    rgba[i * 4 + 1] = Math.round(Math.min(1, img.g[i]) * 255);
    rgba[i * 4 + 2] = Math.round(Math.min(1, img.b[i]) * 255);
    rgba[i * 4 + 3] = Math.round(Math.min(1, a) * 255);
  }
  return { w: img.w, h: img.h, rgba };
}

/** alle Teile -> Map name -> { w, h, rgba } */
export function cutAll(sheetRgba) {
  const sheet = keySheet(sheetRgba);
  // Ziffern, die in einen Ausschnitt ragen, loeschen (dort liegt sonst nur Gruen)
  for (const part of Object.values(PARTS)) {
    for (const e of part.erase || []) {
      for (let y = e.y; y < e.y + e.h; y++) for (let x = e.x; x < e.x + e.w; x++) sheet.a[y * sheet.w + x] = 0;
    }
  }
  const out = new Map();
  const edgeH = cutEdgeH(sheet), edgeV = cutEdgeV(sheet);
  for (const [name, part] of Object.entries(PARTS)) {
    let img;
    if (part.kind === "corner") img = cutCorner(sheet);
    else if (part.kind === "edge-h") img = edgeH;
    else if (part.kind === "edge-v") img = edgeV;
    else if (part.kind === "fill") img = seamless(seamless(flattenFill(crop(sheet, { ...part.src, w: part.src.w, h: part.src.h })), 60, "x"), 60, "y");
    else if (part.hollow) img = hollow(crop(sheet, part.src), part.hollow);
    else img = crop(sheet, part.src);
    out.set(name, toRgba(resample(img, part.size[0], part.size[1])));
  }
  return out;
}

function main() {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-cfg-cut-"));
  try {
    const png = path.join(tmp, "sheet.png");
    jpgToPng(SHEET, png);
    const sheet = decodePng(readFileSync(png));
    if (sheet.w !== 2048 || sheet.h !== 2048) throw new Error(`Bogen hat ${sheet.w} x ${sheet.h}, erwartet 2048 x 2048`);
    mkdirSync(OUT_DIR, { recursive: true });
    for (const [name, img] of cutAll(sheet)) {
      writeFileSync(path.join(OUT_DIR, name + ".tga"), tgaRgba(img));
      console.log(`${name}.tga  ${img.w} x ${img.h}`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
