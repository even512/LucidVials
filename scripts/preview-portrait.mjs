// Sichtvorschau der Portrait-Stile (modules/UnitFrames/Portrait.lua) auf einem echten Portrait-Ausschnitt (docs/unitframe-src/vorschau-gesicht.png,
// Spielbild), vor dem Spieltest. Die Werte (Staerke 0,6 wie Standard) kommen aus den Konstanten Portrait.PAINT/Portrait.SUB (Test-VM).
//   node scripts/preview-portrait.mjs [--out docs/unitframe-src/vorschau-portrait.png]            Lebendes Gemaelde, vorher (v1) / nachher
//   node scripts/preview-portrait.mjs --kolben [--out docs/unitframe-src/vorschau-kolben.png]     Im Kolben versunken, Pegel 100 / 60 / 25 %, vorher (Streifen) / nachher
//   --i <0..1>  Staerke (Standard 0,6)
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createVm } from "../tests/helpers/wow-vm.mjs";
import { decodePng } from "./media-lib.mjs";
import { encodePng } from "./cut-ziel-teile.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const KOLBEN = args.includes("--kolben");
const OUT = path.resolve(ROOT, opt("--out", KOLBEN ? "docs/unitframe-src/vorschau-kolben.png" : "docs/unitframe-src/vorschau-portrait.png"));
const I = Number(opt("--i", 0.6));
const N = 256, GAP = 12, SCALE = N / 60; // Vorschau-Pixel je Spiel-Pixel (Portrait ~60 px)

const vm = createVm();
const K = vm.lua("return { paint = NS.UnitPortrait.PAINT, sub = NS.UnitPortrait.SUB, tint = NS.UnitFrameSkin.TINTS.player.color }");
const C = K.paint, S = K.sub;

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const mix = (a, b, k) => a + (b - a) * k;
function evalPoints(points, x) {
  if (x <= points[0][0]) return points[0][1];
  for (let i = 1; i < points.length; i++) {
    if (x <= points[i][0]) {
      const a = points[i - 1], b = points[i];
      return b[0] === a[0] ? b[1] : a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]);
    }
  }
  return points[points.length - 1][1];
}

// Bilder als Float-RGBA (0..1), N x N bzw. frei
function readTga(name) {
  const b = readFileSync(path.join(ROOT, "addon", "LucidVials", "Media", `${name}.tga`));
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), px = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = b[18 + i * 4 + 2] / 255; px[i * 4 + 1] = b[18 + i * 4 + 1] / 255; px[i * 4 + 2] = b[18 + i * 4] / 255; px[i * 4 + 3] = b[18 + i * 4 + 3] / 255;
  }
  return { w, h, px };
}
const png = decodePng(readFileSync(path.join(ROOT, "docs", "unitframe-src", "vorschau-gesicht.png")));
const FACE = { w: png.w, h: png.h, px: Float32Array.from(png.rgba, (v) => v / 255) };

/** bilinear, wrap = Kachel */
function sample(img, u, v, wrap = false) {
  let x = u * img.w - 0.5, y = v * img.h - 0.5;
  const at = (ix, iy) => {
    if (wrap) { ix = ((ix % img.w) + img.w) % img.w; iy = ((iy % img.h) + img.h) % img.h; } else { ix = clamp(ix, 0, img.w - 1); iy = clamp(iy, 0, img.h - 1); }
    const o = (iy * img.w + ix) * 4;
    return [img.px[o], img.px[o + 1], img.px[o + 2], img.px[o + 3]];
  };
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const a = at(ix, iy), b = at(ix + 1, iy), c = at(ix, iy + 1), d = at(ix + 1, iy + 1);
  return a.map((_, k) => a[k] * (1 - fx) * (1 - fy) + b[k] * fx * (1 - fy) + c[k] * (1 - fx) * fy + d[k] * fx * fy);
}

// Portrait: Kreisausschnitt des Ringinneren, auf N x N
const faceAt = (u, v) => sample(FACE, 0.5 + (u - 0.5) * 0.88, 0.5 + (v - 0.5) * 0.88);
const newCanvas = () => {
  const px = new Float32Array(N * N * 4);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const f = faceAt((x + 0.5) / N, (y + 0.5) / N), o = (y * N + x) * 4;
    px[o] = f[0]; px[o + 1] = f[1]; px[o + 2] = f[2]; px[o + 3] = 1;
  }
  return px;
};

/** Lage auflegen: color (Vertexfarbe), alpha (Faktor), mode "blend"|"add"; src(x, y) -> [r,g,b,a] oder Textur img; clipY = erste Zeile */
function layer(dst, src, color, alpha, mode, clipY = 0, extra = null) {
  for (let y = clipY; y < N; y++) for (let x = 0; x < N; x++) {
    const t = typeof src === "function" ? src(x, y) : sample(src, (x + 0.5) / N, (y + 0.5) / N);
    const col = extra ? extra(x, y) : color;
    const a = t[3] * (col[3] ?? 1) * alpha;
    if (a <= 0) continue;
    const o = (y * N + x) * 4;
    for (let c = 0; c < 3; c++) {
      const s = t[c] * col[c];
      dst[o + c] = mode === "add" ? Math.min(1, dst[o + c] + s * a) : dst[o + c] * (1 - a) + s * a;
    }
  }
}
const shifted = (img, dx, dy) => (x, y) => sample(img, (x + 0.5 - dx) / N, (y + 0.5 - dy) / N);

const T = Object.fromEntries(["vignette", "cracks", "cracks-heavy", "candle", "heal", "gloss"].map((n) => [n, readTga("uf-portrait-" + n)]));
const CAUSTIC = readTga("uf-caustic");
const WATERLINE = readTga("uf-portrait-waterline");

// ---- Lebendes Gemaelde ----------------------------------------------------------------------------------------------------
function paintingBefore(frac) { // v1: Vignette 0,48; Kerzenlicht ~0,2; Risse weiss, ohne Schatten
  const p = newCanvas();
  const red = evalPoints([[0, 0.85], [0.2, 0.55], [0.5, 0], [1, 0]], frac) * I;
  layer(p, T.vignette, [0.85, 0.05, 0.03], red, "blend");
  layer(p, T.vignette, [1, 1, 1], 0.8 * I, "blend");
  layer(p, T.candle, [1, 0.74, 0.4], 0.2, "add");
  layer(p, T["cracks-heavy"], [1, 1, 1], evalPoints([[0, 1], [0.06, 1], [0.18, 0], [1, 0]], frac) * I, "blend");
  layer(p, T.cracks, [1, 1, 1], evalPoints(C.cracks, frac) * I, "blend");
  layer(p, T.gloss, [1, 1, 1], C.gloss * I, "add");
  return p;
}
function paintingAfter(frac) {
  const p = newCanvas();
  const zoom = 1 + (C.breathBase + C.breathScale * I) * 0.85; // fast auf dem Hoehepunkt des Atmens
  const p2 = new Float32Array(p.length);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const f = faceAt(0.5 + ((x + 0.5) / N - 0.5) / zoom, 0.5 + ((y + 0.5) / N - 0.5) / zoom), o = (y * N + x) * 4;
    p2[o] = f[0]; p2[o + 1] = f[1]; p2[o + 2] = f[2]; p2[o + 3] = 1;
  }
  const red = evalPoints(C.blood, frac) * I;
  layer(p2, T.vignette, C.bloodColor, red, "blend");
  layer(p2, T.vignette, [0.02, 0.015, 0.01], Math.min(1, (C.vignetteBase + C.vignette * I)), "blend");
  layer(p2, T.vignette, [0.02, 0.015, 0.01], Math.min(1, (C.vignetteBase + C.vignette * I)), "blend");
  layer(p2, T.candle, C.candleColor, C.candle * (0.3 + 0.7 * 0.8) * (0.3 + 0.7 * I), "add");
  const off = SCALE * 1; // 1 Spiel-Pixel Schatten
  const ca = evalPoints(C.cracks, frac) * I * C.crackMax, ha = evalPoints(C.heavyP, frac) * I * C.heavyMax;
  layer(p2, shifted(T["cracks-heavy"], off, off), [0, 0, 0], ha * C.shadowK, "blend");
  layer(p2, T["cracks-heavy"], C.crackColor, ha, "blend");
  layer(p2, shifted(T.cracks, off, off), [0, 0, 0], ca * C.shadowK, "blend");
  layer(p2, T.cracks, C.crackColor, ca, "blend");
  layer(p2, T.gloss, [1, 1, 1], C.gloss * I, "add");
  return p2;
}

// ---- Im Kolben versunken ---------------------------------------------------------------------------------------------------
const lerpCol = (a, b, k) => a.map((v, i) => mix(v, b[i], k));
function depthColors() {
  const [r, g, b] = (() => { const m = Math.max(...K.tint, 0.01), k = 0.85 / m; return K.tint.map((c) => Math.min(1, c * k)); })();
  const top = [mix(1, r, mix(S.topMix[0], S.topMix[1], I)), mix(1, g, mix(S.topMix[0], S.topMix[1], I)), mix(1, b, mix(S.topMix[0], S.topMix[1], I))];
  const dm = mix(S.deepMix[0], S.deepMix[1], I);
  let deep = [mix(1, r, dm), mix(1, g, dm), mix(1, b, dm)];
  const lum = 0.3 * deep[0] + 0.59 * deep[1] + 0.11 * deep[2];
  deep = deep.map((c) => mix(c, lum, S.desat) * mix(1, S.deepDark, I));
  return { top, deep, water: [mix(1, r, 0.45), mix(1, g, 0.45), mix(1, b, 0.45)] };
}
const circleMask = (u, v) => 1 - clamp((Math.hypot(u - 0.5, v - 0.5) * 2 - 0.97) / 0.03);

function kolbenBefore(level) { // v1: drei waagrechte Streifen, flach getoent, harte Versaetze
  const p = newCanvas(), y0 = Math.round((1 - level) * N), t = 1.7;
  const d = depthColors();
  const col = [mix(1, K.tint[0], 0.375) * 0.9, mix(1, K.tint[1], 0.375) * 0.9, mix(1, K.tint[2], 0.375) * 0.9];
  for (let k = 0; k < 3; k++) {
    const amp = 0.012 + 0.01 * I, sp = [0.9, 1.3, 1.7][k], ph = [0, 1.9, 3.6][k];
    const dx = amp * Math.sin(t * sp + ph);
    const ya = Math.round(N - (k + 1) * N / 3), yb = Math.round(N - k * N / 3);
    for (let y = Math.max(ya, y0); y < yb; y++) for (let x = 0; x < N; x++) {
      const f = faceAt(((x + 0.5) / N) + dx, (y + 0.5) / N), o = (y * N + x) * 4;
      for (let c = 0; c < 3; c++) p[o + c] = f[c] * col[c];
    }
  }
  void d;
  layer(p, () => [1, 1, 1, 1], [0.8, 0.95, 0.8], 0.5, "add", y0, (x, y) => (y < y0 + 3 ? [0.8, 0.95, 0.8, 1] : [0, 0, 0, 0]));
  return p;
}

// Ecken-UV einer Kopie (Spiegel von warp() in Portrait.lua: Mittelpunkt-Schwimmen, Zoom-Atem, Eckwellen, untere Ecken staerker)
function warpUv(g, amp, t, shift, wUp = S.wUp, wLow = S.wLow) {
  const w = g.speed, ph = g.phase, wv = (a, k) => a * Math.sin(t * w + ph + k * 1.7);
  const h = 0.5 * g.zoom * (1 + g.breath * Math.sin(t * w * 0.8 + ph + 0.9));
  const cx = 0.5 + shift + g.drift * Math.sin(t * w + ph), cy = 0.5 + g.drift * 0.8 * Math.sin(t * w * 0.7 + ph + 1.3);
  const up = amp * wUp, lo = amp * wLow;
  return [[cx - h + wv(up, 0), cy - h + wv(up, 1)], [cx - h + wv(lo, 2), cy + h + wv(lo, 3)], [cx + h + wv(up, 4), cy - h + wv(up, 5)], [cx + h + wv(lo, 6), cy + h + wv(lo, 7)]]; // UL LL UR LR
}
const OUTSIDE = [];
function drawCopy(p, uv, a, y0, gradient, tag) {
  let out = 0, tot = 0;
  for (let y = y0; y < N; y++) for (let x = 0; x < N; x++) {
    const fx = (x + 0.5) / N, fy = (y + 0.5) / N;
    const u = (1 - fy) * ((1 - fx) * uv[0][0] + fx * uv[2][0]) + fy * ((1 - fx) * uv[1][0] + fx * uv[3][0]);
    const v = (1 - fy) * ((1 - fx) * uv[0][1] + fx * uv[2][1]) + fy * ((1 - fx) * uv[1][1] + fx * uv[3][1]);
    const f = faceAt(u, v), gr = gradient(y), o = (y * N + x) * 4;
    for (let c = 0; c < 3; c++) p[o + c] = p[o + c] * (1 - a) + f[c] * gr[c] * a;
    if (circleMask(fx, fy) > 0.5) { tot++; if (u < 0 || u > 1 || v < 0 || v > 1) out++; }
  }
  OUTSIDE.push(tag + " " + (100 * out / Math.max(1, tot)).toFixed(1) + "%");
}

// Stand vor Anhang 3 (zum Vergleich): kleine Welle, Hauptkopie still, keine Drift
function kolbenV2(level, T = 1.7) {
  const p = newCanvas(), y0 = Math.round((1 - level) * N), d = depthColors();
  const amp = 0.010 + (0.018 - 0.010) * I, gradient = (y) => lerpCol(d.deep, d.top, 1 - y / (N - 1));
  drawCopy(p, warpUv({ zoom: 1, speed: 1, phase: 0, breath: 0, drift: 0 }, 0, T, 0), 1, y0, gradient, "alt-haupt");
  [{ alpha: 0.34, zoom: 0.97, speed: 0.9, phase: 0 }, { alpha: 0.26, zoom: 0.945, speed: 1.35, phase: 2.1 }].forEach((g, k) =>
    drawCopy(p, warpUv({ ...g, breath: 0, drift: 0 }, amp, T, 0, 1, 1), g.alpha * (0.5 + 0.5 * I), y0, gradient, "alt-geist" + (k + 1)));
  finishKolben(p, y0, d, T, true);
  return p;
}

function kolbenAfter(level, T = Number(opt("--t", 1.7))) {
  const p = newCanvas(), y0 = Math.round((1 - level) * N), t = T;
  const d = depthColors();
  const amp = S.wave + (S.waveMax - S.wave) * I, ampMain = S.mainWave * (0.5 + 0.5 * I);
  const gradient = () => [1, 1, 1]; // Kopien ungetoent, die Toenung liegt als Verlauf ab der Wasserlinie darueber (finishKolben)
  drawCopy(p, warpUv(S.main, ampMain, t, 0), 1, y0, gradient, "haupt"); // Hauptkopie
  S.ghost.forEach((g, k) => drawCopy(p, warpUv(g, amp, t, 0), g.alpha * (0.5 + 0.5 * I), y0, gradient, "geist" + (k + 1))); // Geisterkopien
  finishKolben(p, y0, d, t);
  return p;
}

// Stand vor dem Wasserlinien-Umbau (v3, zum Vergleich): harte Linie + Band + Randflecken
function oldWaterline(p, y0, d) {
  const lh = Math.max(1.2, 60 * 0.022) * SCALE, bandH = N * 0.12, dabW = N * 0.16, dabH = N * 0.14;
  layer(p, (x, y) => [1, 1, 1, y < y0 + lh ? 1 : 0], d.water, 0.42 * Math.min(1, I * 2), "add", y0);
  layer(p, (x, y) => [1, 1, 1, y >= y0 + lh && y < y0 + lh + bandH ? 1 - (y - y0 - lh) / bandH : 0], d.water, 0.34 * I, "add", y0);
  layer(p, (x, y) => [1, 1, 1, y < y0 + dabH && (x < dabW || x >= N - dabW) ? (1 - (y - y0) / dabH) : 0], d.water, 0.5 * I, "add", y0);
}

function finishKolben(p, y0, d, t, old = false) {
  if (!old) { // Tiefen-Toenung (BLEND) ab der Wasserlinie: oben fast klar, am Boden tief (Spiegel von tintSubmerged)
    const bot = d.deep.map((c) => c * S.tintDeepK), ba = mix(S.tintDeepA[0], S.tintDeepA[1], I), ta = S.tintTopA * I;
    for (let y = y0; y < N; y++) {
      const k = (y - y0 + 0.5) / Math.max(1, N - y0), a = mix(ta, ba, k);
      for (let x = 0; x < N; x++) {
        const o = (y * N + x) * 4;
        for (let c = 0; c < 3; c++) p[o + c] = p[o + c] * (1 - a) + bot[c] * a;
      }
    }
  }
  // Kaustik (ADD, schwach, zwei Netze gegenlaeufig)
  const ca = S.caustic * (0.4 + 0.6 * I);
  S.causticMove.forEach((m) => {
    const u0 = (t * m[0]) % 1, v0 = (t * m[1]) % 1;
    layer(p, (x, y) => sample(CAUSTIC, u0 + (x + 0.5) / N * S.causticTile, v0 + (y + 0.5) / N * S.causticTile * 0.7, true), d.water, ca, y0, null);
  });
  // Wasserlinie (Spiegel von surfWave() in Portrait.lua, ohne Neigung): zwei Haelften, Verlauf aus uf-portrait-waterline, senkrecht verschoben
  if (old) oldWaterline(p, y0, d);
  else {
    const sw = S.surfSway * (0.4 + 0.6 * I), dL = sw * Math.sin(t * 0.9), dM = sw * 0.8 * Math.sin(t * 1.3 + 1.0), dR = sw * Math.sin(t * 0.8 + 2.3);
    const hPx = Math.max(4, 60 * S.surfHeight) * SCALE, va = S.surfAlpha * Math.min(1, I * 2);
    layer(p, (x, y) => {
      const fx = (x + 0.5) / N, fy = (y - y0 + 0.5) / hPx;
      if (fy < 0 || fy > 1) return [1, 1, 1, 0];
      const d = fx < 0.5 ? mix(dL, dM, fx * 2) : mix(dM, dR, (fx - 0.5) * 2);
      return [1, 1, 1, sample(WATERLINE, 0.5, fy + d)[3]];
    }, d.water, va, "add", y0);
  }
  layer(p, T.gloss, [1, 1, 1], C.gloss * I, "add");
}

// ---- Ausgabe ---------------------------------------------------------------------------------------------------------------
const PAINT_FRACS = opt("--fracs", "1,0.1,0.04").split(",").map(Number); // Lebensanteile des Gemaelde-Bogens (z. B. --fracs 0.6,0.3,0.08)
const cases = KOLBEN
  ? [["vorher", kolbenV2, [1, 0.6, 0.25]], ["nachher", kolbenAfter, [1, 0.6, 0.25]], ["nachher t2", (l) => kolbenAfter(l, 4.4), [1, 0.6, 0.25]]]
  : [["vorher", paintingBefore, PAINT_FRACS], ["nachher", paintingAfter, PAINT_FRACS]];
const cols = cases[0][2].length, rows = cases.length;
const W = cols * N + (cols + 1) * GAP, H = rows * N + (rows + 1) * GAP;
const out = new Uint8Array(W * H * 4);
for (let i = 0; i < W * H; i++) { out[i * 4] = 34; out[i * 4 + 1] = 36; out[i * 4 + 2] = 44; out[i * 4 + 3] = 255; }
cases.forEach(([, fn, values], r) => values.forEach((val, c) => {
  const px = fn(val), ox = GAP + c * (N + GAP), oy = GAP + r * (N + GAP);
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const m = circleMask((x + 0.5) / N, (y + 0.5) / N), o = (y * N + x) * 4, d = ((oy + y) * W + ox + x) * 4;
    for (let k = 0; k < 3; k++) out[d + k] = Math.round(mix(out[d + k] / 255, clamp(px[o + k]), m) * 255);
  }
}));
if (KOLBEN) console.log("Anteil Kreisflaeche ausserhalb des Bildes (t=" + opt("--t", 1.7) + ", Pegel 100/60/25 gesamt):", OUTSIDE.join(" | "));
writeFileSync(OUT, encodePng({ w: W, h: H, rgba: out }));
console.log("geschrieben:", path.relative(ROOT, OUT));
