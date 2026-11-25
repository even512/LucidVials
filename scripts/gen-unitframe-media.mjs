// Erzeugt die Texturen der Einheitenrahmen (Delta "Fluessiges Leben") als unkomprimierte 32-bit-TGA (Format wie
// scripts/media-lib.mjs, tgaRgba) aus den freigegebenen Gemini-Vorlagen. Quellen: die freigestellten
// RGBA-PNGs in docs/unitframe-src/freigestellt/ (Boegen sheet-rahmen-v1.jpg und sheet-fluessigkeit-v1.jpg; Kolben-Kammer:
// v2-*.png aus sheet-fluessigkeit-v2.jpg und sheet-kolben-v2.jpg).
//
//   uf-ring.tga           256 x 256  Bronze-Portraetring (ring.png), Innen durchsichtig; Innenradius RING.inner
//   uf-level-square.tga   128 x 128  Stufen-Plaettchen Spieler (plate-square.png), Zahl kommt als Text darauf
//   uf-level-round.tga    128 x 128  Stufen-Scheibe Ziel/ToT (plate-round.png)
//   uf-frame-health.tga  1024 x 128  Bronze-Kapselrahmen Lebensbalken (health.png, Zierkappe rechts), Glas durchsichtig
//   uf-frame-power.tga   1024 x 128  Bronze-Kapselrahmen Ressourcenbalken (power.png, Zierkappen beidseitig)
//                                    -> Glasoeffnung und 3-Slice-Schnitte (Quell-Pixel) in FRAMES, gleich in Liquid.lua
//   uf-mask-capsule.tga   256 x 64   Kapsel-Maske aus der Glasoeffnung von health.png (Enden unverzerrt fuer 6,5:1)
//   uf-mask-thin.tga      256 x 32   Kapsel-Maske aus der Glasoeffnung von power.png (fuer 12:1)
//   uf-mask-xp.tga       1024 x 16   Kapsel-Maske aus der Glasoeffnung von power.png (fuer 80:1, Erfahrungsleiste)
//   uf-fill.tga           512 x 128  Fluessigkeit (liquid-fill.png, grau, per Vertexfarbe getoent): waagrecht nahtlos
//                                    ueberblendet; obere Haelfte Lage A, untere Lage B (halbe Breite versetzt) wie
//                                    np-liquid (Style.ANIM vA/vB/vSpan)
//   uf-edge-cover.tga     128 x 64   Fluessigkeitskante, prozedural (EDGE): Luft-Abdeckung rechts der Meniskus-Grenze
//   uf-edge-rim.tga       128 x 64   Randlicht genau auf derselben Grenze (Gemini-Kanten liquid-edge*.png nur Referenz)
//   uf-mask-endright.tga   64 x 4    Endblende rechts (Abdeckung laeuft bei voller Roehre in die Kappe)
//   uf-mask-endfade.tga    64 x 4    Endblende beidseitig (Randlicht bei 0 % / 100 % unsichtbar)
//   uf-mask-fadein.tga     64 x 4    Einlauf-Rampe der Glut am Fuellungsende
//   uf-piston.tga          32 x 256  Kolben der Kolben-Kammer (v2-piston.png, ein Dichtring), ungleichmaessig schmal gestaucht
//   uf-body.tga           512 x 128  Kolben-Kammer: Fluessigkeitskoerper mit Rauchschwaden (v2-body.png), waagrecht nahtlos
//   uf-air.tga             32 x 256  Kolben-Kammer: Luft/klares Glas ueber weicher Oberflaeche (AIR, Farbe wie uf-glassback)
//   uf-glassback.tga       16 x 64   Kolben-Kammer: Leerglas hinter dem Kolben (weiche Spiegelung)
//   uf-surfglow.tga        64 x 256  Kolben-Kammer: Lichtlinie, Oberflaechenband, Glow (v2-surface.png, Lage wie uf-air), kachelbar
//   uf-wet.tga             64 x 256  Kolben-Kammer: Naessefilm am Glas (Rinnspuren aus v2-wet.png, Lage wie uf-air), kachelbar
//   uf-caustic.tga        256 x 128  Kolben-Kammer: Kaustik-Linien (v2-caustic.png), kachelbar
//   uf-drop.tga           128 x 32   Kolben-Kammer: Atlas aus 4 Spritzer-Tropfen (v2-drops.png)
//   uf-bubbles.tga        256 x 64   Blaeschen (liquid-bubbles.png): Ausschnitt mit leeren Randspalten (nahtlos)
//   uf-glass.tga          512 x 64   Glasglanz der Roehre (liquid-glass.png), weiss, 3-Slice mit GLASS.cap
//   uf-ember.tga          512 x 128  Glut der Schadensspur: weicher Schein + Funken (liquid-ember.png), beidseitig auslaufend
//   uf-glint.tga          256 x 64   wandernde Spiegelung (GLINT, prozedural, weiss): links Glasreflex (schraeger weicher
//                                    Doppelstreifen), rechts Oberflaechenglanz (weicher Fleck); nur Alpha-Verlaeufe
//   uf-ziel-<art>.tga     256 x 512  Ziel-Zier (elite, rare, rareelite, boss) aus ziel-*.png: Hinterlage (unter uf-ring)
//   uf-ziel-<art>-front   256 x 256  Vorderlage (ueber uf-ring, eigener Ring des Teils radial entfernt), Ringmitte = Mitte
//   uf-ziel-marker(-small), -gem, -aura 64 x 64, uf-ziel-level 128 x 128 (Kleinteile des Bogens)
//   uf-ring-aufnahme.tga  512 x 512  Portraetring mit Rohraufnahmen (ring-aufnahme.png aus sheet-ring-aufnahme-v4.jpg,
//                                    scripts/cut-ring-aufnahme.mjs) fuer Spieler/Ziel; Lage in Deco.GEO.socket
//   uf-fx-*.tga                      Effekte (FX, aus fx-*.png des Bogens sheet-effekte-v1.jpg, Luminanz -> Alpha):
//                                    sweep 512x64 Heillicht-Band, burst 128x128 Heilstern, sparkles 256x64 Funkeln,
//                                    splash 256x128 Spritzkrone, flash 512x64 Trefferblitz, ink 512x128 Schlieren (waagrecht
//                                    nahtlos), mana 512x128 Blaeschen + Lichtfaeden (waagrecht und senkrecht nahtlos)
//
// Aufbereitung: Farbsaum der Freisteller (Gruen/Magenta-Reste) wird auf Bronze-Ton zurueckgefuehrt; Verkleinern per
// Box-Filter in linearem Licht auf vormultiplizierten Farben; danach wird die Farbe in volltransparente Texel
// hineingezogen (kein Schwarzsaum beim bilinearen Filtern im Spiel). Weisse Overlays tragen RGB = 255 ueberall.
// Deterministisch. Aufruf: node scripts/gen-unitframe-media.mjs
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tgaRgba } from "./media-lib.mjs";
import { decodePng } from "./media-lib.mjs";
import { components } from "./cut-ziel-teile.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MEDIA = path.join(ROOT, "addon", "LucidVials", "Media");
export const SRC = path.join(ROOT, "docs", "unitframe-src", "freigestellt");

const clamp = (v, lo = 0, hi = 255) => Math.max(lo, Math.min(hi, v));
const smooth = (x, a, b) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

export const loadSource = (name) => decodePng(readFileSync(path.join(SRC, name + ".png")));
const blank = (w, h) => ({ w, h, rgba: new Uint8Array(w * h * 4) });
const alphaAt = (img, x, y) => img.rgba[(y * img.w + x) * 4 + 3];

// Farbe -----------------------------------------------------------------------------------------------------------------
const LIN = new Float64Array(256);
for (let i = 0; i < 256; i++) {
  const c = i / 255;
  LIN[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}
const toSrgb = (l) => {
  const c = l <= 0.0031308 ? l * 12.92 : 1.055 * Math.pow(l, 1 / 2.4) - 0.055;
  return clamp(Math.round(c * 255));
};

/** Freisteller-Saum: Bronze hat R >= G >= B. Pixel mit Gruen- oder Magenta-Stich (Key-Reste) -> Bronze-Ton gleicher Helligkeit */
export function cleanFringe(img) {
  const { w, h, rgba } = img;
  const out = new Uint8Array(rgba);
  let fixed = 0;
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    if (out[o + 3] === 0) continue;
    const r = out[o], g = out[o + 1], b = out[o + 2];
    if (g > r + 2 || b > g + 6) {
      const l = 0.299 * r + 0.587 * g + 0.114 * b;
      out[o] = clamp(Math.round(l * 1.22));
      out[o + 1] = clamp(Math.round(l * 0.96));
      out[o + 2] = clamp(Math.round(l * 0.74));
      fixed++;
    }
  }
  return { w, h, rgba: out, fixed };
}

/** Box-Filter in linearem Licht auf vormultiplizierten Farben: Ausschnitt (x0, y0, cw, ch) -> ow x oh; flipX spiegelt */
export function resampleLinear(img, x0, y0, cw, ch, ow, oh, { flipX = false } = {}) {
  const { w, h, rgba } = img;
  const out = new Uint8Array(ow * oh * 4), sx = cw / ow, sy = ch / oh;
  for (let oy = 0; oy < oh; oy++) {
    const ya = y0 + oy * sy, yb = ya + sy;
    for (let ox = 0; ox < ow; ox++) {
      const xa = x0 + ox * sx, xb = xa + sx;
      let r = 0, g = 0, b = 0, a = 0, wt = 0;
      for (let y = Math.floor(ya); y < Math.ceil(yb); y++) {
        const wy = Math.min(yb, y + 1) - Math.max(ya, y);
        for (let x = Math.floor(xa); x < Math.ceil(xb); x++) {
          const wgt = wy * (Math.min(xb, x + 1) - Math.max(xa, x));
          wt += wgt;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          const o = (y * w + x) * 4, al = (rgba[o + 3] / 255) * wgt;
          r += LIN[rgba[o]] * al; g += LIN[rgba[o + 1]] * al; b += LIN[rgba[o + 2]] * al; a += al;
        }
      }
      const p = (oy * ow + (flipX ? ow - 1 - ox : ox)) * 4;
      if (a > 0) {
        out[p] = toSrgb(r / a); out[p + 1] = toSrgb(g / a); out[p + 2] = toSrgb(b / a);
        out[p + 3] = clamp(Math.round((a / wt) * 255));
      }
    }
  }
  return { w: ow, h: oh, rgba: out };
}

/** Farbe in volltransparente Texel ziehen (Mittel der gefaerbten Nachbarn, wiederholt), Rest = Mittel aller Farben */
export function bleed(img, passes = 8) {
  const { w, h, rgba } = img;
  const has = new Uint8Array(w * h);
  let sr = 0, sg = 0, sb = 0, n = 0;
  for (let i = 0; i < w * h; i++) {
    if (rgba[i * 4 + 3] > 0) {
      has[i] = 1;
      sr += rgba[i * 4]; sg += rgba[i * 4 + 1]; sb += rgba[i * 4 + 2]; n++;
    }
  }
  for (let pass = 0; pass < passes; pass++) {
    const add = [];
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        if (has[i]) continue;
        let r = 0, g = 0, b = 0, k = 0;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            const j = yy * w + xx;
            if (has[j]) { r += rgba[j * 4]; g += rgba[j * 4 + 1]; b += rgba[j * 4 + 2]; k++; }
          }
        }
        if (k) add.push([i, r / k, g / k, b / k]);
      }
    }
    if (!add.length) break;
    for (const [i, r, g, b] of add) {
      rgba[i * 4] = Math.round(r); rgba[i * 4 + 1] = Math.round(g); rgba[i * 4 + 2] = Math.round(b);
      has[i] = 1;
    }
  }
  if (n) {
    for (let i = 0; i < w * h; i++) {
      if (!has[i]) { rgba[i * 4] = Math.round(sr / n); rgba[i * 4 + 1] = Math.round(sg / n); rgba[i * 4 + 2] = Math.round(sb / n); }
    }
  }
  return img;
}

/** weisses Overlay: RGB 255 ueberall, Alpha bleibt */
function whiten(img) {
  for (let i = 0; i < img.w * img.h; i++) { img.rgba[i * 4] = 255; img.rgba[i * 4 + 1] = 255; img.rgba[i * 4 + 2] = 255; }
  return img;
}

/** Alpha-Bounding-Box (Alpha > thr) */
export function alphaBox(img, thr = 8) {
  const { w, h } = img;
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (alphaAt(img, x, y) > thr) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  return { x0, y0, x1: x1 + 1, y1: y1 + 1 };
}

// Rahmen ----------------------------------------------------------------------------------------------------------------
/**
 * Glasoeffnung eines Kapselrahmens (Alpha <= 128, vom Mittelpunkt aus zusammenhaengend) und 3-Slice-Schnitte.
 * Liefert Quell-Pixel: srcW/srcH, open = { l, t, r, b } (Bounding-Box, exklusive Obergrenze), slice = { l, r }: ab slice.l
 * bzw. bis slice.r ist jede Spalte gleichfoermig (die Rundung der Oeffnung liegt ganz in der Kappe).
 */
export function measureFrame(img) {
  const { w, h } = img;
  const inside = new Uint8Array(w * h);
  const stack = [(h >> 1) * w + (w >> 1)];
  if (alphaAt(img, w >> 1, h >> 1) > 128) throw new Error("Mitte des Rahmens ist nicht durchsichtig");
  inside[stack[0]] = 1;
  let l = w, t = h, r = -1, b = -1;
  while (stack.length) {
    const i = stack.pop(), x = i % w, y = (i / w) | 0;
    if (x < l) l = x;
    if (x > r) r = x;
    if (y < t) t = y;
    if (y > b) b = y;
    for (const j of [i - 1, i + 1, i - w, i + w]) {
      if (j < 0 || j >= w * h || inside[j]) continue;
      if ((j % w) - x > 1 || x - (j % w) > 1) continue;
      if (img.rgba[j * 4 + 3] <= 128) { inside[j] = 1; stack.push(j); }
    }
  }
  const open = { l, t, r: r + 1, b: b + 1 };
  // oberste Oeffnungszeile je Spalte: die Rundung endet, wo sie die Oberkante (t + 1) erreicht
  const topOf = (x) => { let y = t; while (y < open.b && !inside[y * w + x]) y++; return y; };
  let sl = l;
  while (sl < w >> 1 && topOf(sl) > t + 1) sl++;
  let sr = r;
  while (sr > w >> 1 && topOf(sr) > t + 1) sr--;
  const margin = Math.round((open.b - open.t) * 0.04);
  return { srcW: w, srcH: h, open, slice: { l: sl + margin, r: sr + 1 - margin }, inside };
}

export const FRAME_OUT = { w: 1024, h: 128 };
export const FRAME_SRC = { health: "health", power: "power" };

export function frameImage(src) {
  const img = cleanFringe(src);
  return bleed(resampleLinear(img, 0, 0, img.w, img.h, FRAME_OUT.w, FRAME_OUT.h));
}

/**
 * Maske aus der Glasoeffnung: Durchsicht (1 - Alpha) in der Oeffnung, um dilate Quell-Pixel geweitet (die Kante liegt unter
 * dem Bronze-Rand, kein Spalt), Enden unverzerrt fuer das Seitenverhaeltnis ratio, die Mitte gleichfoermig gedehnt.
 */
export function maskFromOpening(src, m, ow, oh, ratio, dilate, openSide = null) {
  const { w } = src;
  const { open } = m;
  const oH = open.b - open.t + 2 * dilate, oW = open.r - open.l + 2 * dilate;
  const y0 = open.t - dilate, x0 = open.l - dilate;
  // Durchsichtsfeld im Ausschnitt, geweitet (Maximum ueber Radius dilate, getrennt waagrecht/senkrecht)
  const field = new Float32Array(oW * oH);
  for (let y = 0; y < oH; y++) {
    for (let x = 0; x < oW; x++) {
      const sx = x0 + x, sy = y0 + y;
      const ins = sx >= open.l && sx < open.r && sy >= open.t && sy < open.b;
      field[y * oW + x] = ins ? 1 - src.rgba[(sy * w + sx) * 4 + 3] / 255 : 0;
    }
  }
  // nur der zusammenhaengende Innenraum zaehlt (aussen liegende durchsichtige Pixel nicht)
  for (let y = 0; y < oH; y++) {
    for (let x = 0; x < oW; x++) {
      const sx = x0 + x, sy = y0 + y;
      const ins = sx >= 0 && sy >= 0 && sx < w && sy < src.h && m.inside[sy * w + sx];
      if (!ins) {
        // Randpixel der Oeffnung (teiltransparente Kante) behalten, wenn ein Nachbar innen liegt
        let near = false;
        for (let d = -2; d <= 2 && !near; d++) {
          for (let e = -2; e <= 2 && !near; e++) {
            const xx = sx + d, yy = sy + e;
            if (xx >= 0 && yy >= 0 && xx < w && yy < src.h && m.inside[yy * w + xx]) near = true;
          }
        }
        if (!near) field[y * oW + x] = 0;
      }
    }
  }
  const tmp = new Float32Array(oW * oH), dil = new Float32Array(oW * oH);
  for (let y = 0; y < oH; y++) {
    for (let x = 0; x < oW; x++) {
      let v = 0;
      for (let d = -dilate; d <= dilate; d++) { const xx = x + d; if (xx >= 0 && xx < oW) v = Math.max(v, field[y * oW + xx]); }
      tmp[y * oW + x] = v;
    }
  }
  for (let y = 0; y < oH; y++) {
    for (let x = 0; x < oW; x++) {
      let v = 0;
      for (let d = -dilate; d <= dilate; d++) { const yy = y + d; if (yy >= 0 && yy < oH) v = Math.max(v, tmp[yy * oW + x]); }
      dil[y * oW + x] = v;
    }
  }
  // Enden: links bis slice.l, rechts ab slice.r (Quelle), symmetrisch gemittelt; Mitte = Profil der Mittelspalte
  const endL = m.slice.l - x0, endR = x0 + oW - m.slice.r;
  const end = Math.max(endL, endR);
  const sample = (x, y) => {
    const xi = clamp(Math.floor(x), 0, oW - 1), yi = clamp(Math.floor(y), 0, oH - 1);
    return dil[yi * oW + xi];
  };
  const k = oH / oh;                       // Quell-Pixel je Masken-Zeile
  const endPx = end / (oH * ratio) * ow;   // Endbreite in Masken-Spalten fuer das Ziel-Seitenverhaeltnis
  const out = blank(ow, oh);
  const SS = 4;
  for (let y = 0; y < oh; y++) {
    for (let x = 0; x < ow; x++) {
      let acc = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px = x + (sx + 0.5) / SS, py = (y + (sy + 0.5) / SS) * k;
          let v;
          if ((openSide === "l" && px < endPx) || (openSide === "r" && px > ow - endPx)) {
            v = sample(oW >> 1, py); // offenes Ende (ringseitig): gerade, ohne Kapsel-Rundung
          } else if (px < endPx) {
            v = sample((px / endPx) * end, py);
            const vr = sample(oW - 1 - (px / endPx) * end, py);
            v = (v + vr) / 2;
          } else if (px > ow - endPx) {
            const q = (ow - px) / endPx * end;
            v = (sample(q, py) + sample(oW - 1 - q, py)) / 2;
          } else {
            v = sample(oW >> 1, py);
          }
          acc += v;
        }
      }
      const o = (y * ow + x) * 4;
      out.rgba.set([255, 255, 255, clamp(Math.round((acc / (SS * SS)) * 255))], o);
    }
  }
  return out;
}

export const MASKS = {
  capsule: { file: "uf-mask-capsule.tga", src: "health", w: 256, h: 64, ratio: 6.5 },
  thin: { file: "uf-mask-thin.tga", src: "power", w: 256, h: 32, ratio: 12 },
  // Erfahrungsleiste (modules/UnitFrames/XP.lua): Retail ~57:1, Forever ~99:1 - Enden fuer 80:1, Mitte gleichfoermig
  xp: { file: "uf-mask-xp.tga", src: "power", w: 1024, h: 16, ratio: 80 },
};
// Masken mit einem offenen (geraden) Ende: ringseitig laeuft die Roehre gerade unter den Portraetring (Liquid.SetOpenEnd)
export const OPEN_MASKS = { capsule: true, thin: true }, OPEN_SIDES = ["l", "r"];
const MASK_DILATE = 0.03; // Anteil der Oeffnungshoehe

// Ring und Plaettchen ---------------------------------------------------------------------------------------------------
export const RING = { size: 256 };
/** quadratischer Zuschnitt um die Alpha-Box (Mitte), Rand pad (Anteil) */
function squareCrop(img, size, pad = 0.004) {
  const c = cleanFringe(img);
  const bx = alphaBox(c);
  const side = Math.max(bx.x1 - bx.x0, bx.y1 - bx.y0) * (1 + 2 * pad);
  const cx = (bx.x0 + bx.x1) / 2, cy = (bx.y0 + bx.y1) / 2;
  return bleed(resampleLinear(c, cx - side / 2, cy - side / 2, side, side, size, size));
}
/** Innenradius (Anteil des halben Durchmessers) eines Rings: Mittel ueber 36 Strahlen bis Alpha > 128 */
export function ringInner(img) {
  const n = img.w, c = n / 2;
  let sum = 0;
  for (let k = 0; k < 36; k++) {
    const an = (k * Math.PI) / 18;
    let r = 1;
    while (r < c && alphaAt(img, Math.floor(c + r * Math.cos(an)), Math.floor(c + r * Math.sin(an))) <= 128) r++;
    sum += r;
  }
  return sum / 36 / c;
}
export const ringImage = () => squareCrop(loadSource("ring"), RING.size);
/** Aussenradius des Rings (Anteil des halben Durchmessers): Median ueber 36 Strahlen von aussen bis Alpha > 128 */
export function ringOuter(img) {
  const n = img.w, c = n / 2, rs = [];
  for (let k = 0; k < 36; k++) {
    const an = (k * Math.PI) / 18;
    let r = c - 1;
    while (r > 0 && alphaAt(img, Math.floor(c + r * Math.cos(an)), Math.floor(c + r * Math.sin(an))) <= 128) r--;
    rs.push(r / c);
  }
  return rs.sort((a, b) => a - b)[18];
}
export const PLATE = { size: 128 };
export const plateImage = (name) => squareCrop(loadSource(name), PLATE.size, 0.01);

// Fluessigkeit ----------------------------------------------------------------------------------------------------------
export const FILL = { w: 512, h: 128, overlap: 0.25, lane: 0.75 };
/** Grauwert-Bild waagrecht nahtlos: Periode = Breite - Ueberlappung, links in das Ende ueberblendet */
export function seamless(img, overlap) {
  const { w, h, rgba } = img;
  const ov = Math.round(w * overlap), P = w - ov;
  const out = blank(P, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < P; x++) {
      const o = (y * P + x) * 4;
      let t = 1;
      if (x < ov) t = smooth(x, 0, ov);
      for (let k = 0; k < 4; k++) {
        const a = rgba[(y * w + x) * 4 + k];
        const b = x < ov ? rgba[(y * w + x + P) * 4 + k] : a;
        out.rgba[o + k] = Math.round(b + (a - b) * t);
      }
    }
  }
  return out;
}
export function fillImage() {
  const src = loadSource("liquid-fill");
  const seam = seamless(src, FILL.overlap);
  const half = FILL.h / 2, body = Math.round(half * FILL.lane), pad = (half - body) / 2;
  const lane = resampleLinear(seam, 0, 0, seam.w, seam.h, FILL.w, body);
  const out = blank(FILL.w, FILL.h);
  for (let L = 0; L < 2; L++) {
    const shift = L ? FILL.w >> 1 : 0;
    for (let y = 0; y < half; y++) {
      const sy = clamp(Math.floor(y - pad), 0, body - 1);
      for (let x = 0; x < FILL.w; x++) {
        const s = (sy * FILL.w + ((x + shift) % FILL.w)) * 4;
        const v = lane.rgba[s];
        out.rgba.set([v, v, v, 255], ((L * half + y) * FILL.w + x) * 4);
      }
    }
  }
  return out;
}

/**
 * Fluessigkeitskante (prozedural, eine gemeinsame Form): Textur ueber [X - R, X + R] um das Fuellungsende X (R = Roehrenhoehe,
 * u = 0,5 liegt auf X). Grenze b(v) = 0,5 + depth x ((2v - 1)^2 - 1/3): leichter Meniskus (Mitte zurueck, Raender vor), Mittel
 * genau auf X. uf-edge-cover: Alpha = Luft (rechts der Grenze), deckt im Spiel die ueber X hinaus gezeichnete Fuellung in
 * Leerglas-Farbe ab; uf-edge-rim: Randlicht genau auf der Grenze (duenne Linie, zarter Schein in die Fluessigkeit).
 * Neigung/Welle entstehen im Spiel per SetVertexOffset an beiden Lagen gleich (Oberflaeche und Rand bleiben eine Linie).
 */
export const EDGE = { w: 128, h: 64, depth: 0.022, soft: 0.012, rim: 0.008, glow: 0.035, glowA: 0.1 };
const edgeB = (v) => 0.5 + EDGE.depth * ((2 * v - 1) ** 2 - 1 / 3);
export function edgeCoverImage() {
  const { w, h, soft } = EDGE;
  const out = blank(w, h);
  for (let y = 0; y < h; y++) {
    const v = (y + 0.5) / h, bnd = edgeB(v);
    for (let x = 0; x < w; x++) {
      let acc = 0;
      for (let k = 0; k < 4; k++) acc += smooth((x + (k + 0.5) / 4) / w - bnd, -soft, soft);
      out.rgba.set([255, 255, 255, Math.round((acc / 4) * 255)], (y * w + x) * 4);
    }
  }
  return out;
}
export function edgeRimImage() {
  const { w, h, rim, glow, glowA } = EDGE;
  const out = blank(w, h);
  for (let y = 0; y < h; y++) {
    const v = (y + 0.5) / h, bnd = edgeB(v);
    const ends = smooth(v, 0, 0.12) * smooth(1 - v, 0, 0.12); // oben/unten unter dem Glasrand auslaufen
    for (let x = 0; x < w; x++) {
      const d = (x + 0.5) / w - bnd;
      const line = Math.exp(-((d / rim) ** 2));
      const inner = d < 0 ? glowA * Math.exp(d / glow) : 0;
      out.rgba.set([255, 255, 255, Math.round(Math.min(1, line + inner) * ends * 255)], (y * w + x) * 4);
    }
  }
  return out;
}
/** Endblenden-Masken (ueber die ganze Roehre gedehnt): weiss, Alpha waagrecht auf fade der Breite zum Ende hin auf 0 */
export const ENDMASK = { w: 64, h: 4, fade: 0.06 };
export function endMaskImage(both) {
  const { w, h, fade } = ENDMASK;
  const out = blank(w, h);
  for (let x = 0; x < w; x++) {
    const u = (x + 0.5) / w;
    const a = smooth(1 - u, 0.01, fade) * (both ? smooth(u, 0.01, fade) : 1);
    for (let y = 0; y < h; y++) out.rgba.set([255, 255, 255, Math.round(a * 255)], (y * w + x) * 4);
  }
  return out;
}

/** Einlauf-Maske der Glut: Alpha 0 -> 1 ueber die Breite (im Spiel mit CLAMP, rechts davon voll) */
export function fadeInImage() {
  const out = blank(64, 4);
  for (let x = 0; x < 64; x++) {
    const a = smooth((x + 0.5) / 64, 0, 1);
    for (let y = 0; y < 4; y++) out.rgba.set([255, 255, 255, Math.round((x === 63 ? 1 : a) * 255)], (y * 64 + x) * 4);
  }
  return out;
}

/**
 * uf-glint: Atlas aus zwei Zellen (je 128 x 64), RGB weiss, nur weiche Alpha-Verlaeufe (keine harte Kante, an allen
 * Zellraendern 0, damit bilineares Filtern nicht in die Nachbarzelle blutet). Zelle 0: Glasreflex - breiter weicher Streifen
 * plus schmaler Begleiter, leicht schraeg (oben weiter rechts), oben/unten auslaufend. Zelle 1: Oberflaechenglanz - flacher
 * weicher Fleck (Gauss). Liquid.lua (GLINT) verschiebt beide mit dem Drehwinkel der Physik.
 */
export const GLINT = { w: 256, h: 64, slant: 0.18, mainSigma: 0.12, mainA: 0.8, sideOff: 0.24, sideSigma: 0.045, sideA: 0.45,
  spotSu: 0.2, spotSv: 0.22, spotA: 0.9, edge: 0.14 };
export function glintImage() {
  const G = GLINT;
  const out = blank(G.w, G.h);
  const cw = G.w / 2;
  for (let y = 0; y < G.h; y++) {
    const v = (y + 0.5) / G.h;
    const winV = smooth(v, 0, G.edge) * smooth(1 - v, 0, G.edge);
    for (let x = 0; x < G.w; x++) {
      const cell = x < cw ? 0 : 1;
      const u = (x - cell * cw + 0.5) / cw;
      const winU = smooth(u, 0, G.edge) * smooth(1 - u, 0, G.edge);
      let a;
      if (cell === 0) {
        const uc = 0.42 + G.slant * (0.5 - v);
        const main = G.mainA * Math.exp(-(((u - uc) / G.mainSigma) ** 2));
        const side = G.sideA * Math.exp(-(((u - uc - G.sideOff) / G.sideSigma) ** 2));
        a = (main + side * (1 - main)) * Math.sin(Math.PI * v) ** 0.7;
      } else {
        a = G.spotA * Math.exp(-(((u - 0.5) / G.spotSu) ** 2) - (((v - 0.5) / G.spotSv) ** 2));
      }
      a *= winU * winV;
      out.rgba.set([255, 255, 255, Math.round(clamp(a, 0, 1) * 255)], (y * G.w + x) * 4);
    }
  }
  return out;
}

// Kolben-Kammer (Darstellung "piston") -------------------------------------------------------------------------------------
// Quellen: die freigegebenen Gemini-Vorlagen v2-*.png (Boegen sheet-fluessigkeit-v2.jpg, sheet-kolben-v2.jpg).
/**
 * uf-piston 32 x 256 aus v2-piston.png (Kolben quer: Bronze, EIN dunkler Dichtring, Gravurband). Im Spiel nur 0,15 x Hoehe
 * breit (~3 px): waagrecht ungleichmaessig gestaucht, damit der Dichtring (Quellspalten PISTON.ring) ein Drittel der Breite
 * behaelt und als dunkler senkrechter Streifen erkennbar bleibt. Saum bereinigt, lineares Licht.
 */
export const PISTON = { w: 32, h: 256, src: "v2-piston", ring: [160, 222], cols: [12, 10, 10], lift: 1.45 };
export function pistonImage() {
  const src = cleanFringe(loadSource(PISTON.src));
  const bx = alphaBox(src);
  const cuts = [bx.x0, PISTON.ring[0], PISTON.ring[1], bx.x1];
  const out = blank(PISTON.w, PISTON.h);
  let ox = 0;
  for (let k = 0; k < 3; k++) {
    const part = resampleLinear(src, cuts[k], bx.y0, cuts[k + 1] - cuts[k], bx.y1 - bx.y0, PISTON.cols[k], PISTON.h);
    if (k !== 1) for (let i = 0; i < part.w * part.h; i++) for (let c = 0; c < 3; c++) part.rgba[i * 4 + c] = clamp(Math.round(part.rgba[i * 4 + c] * PISTON.lift));
    for (let y = 0; y < PISTON.h; y++) {
      out.rgba.set(part.rgba.subarray(y * part.w * 4, (y + 1) * part.w * 4), (y * PISTON.w + ox) * 4);
    }
    ox += PISTON.cols[k];
  }
  return bleed(out);
}
export function pistonAspect() {
  const bx = alphaBox(loadSource(PISTON.src));
  return (bx.x1 - bx.x0) / (bx.y1 - bx.y0);
}

/** Grauwert-Bild senkrecht nahtlos (wie seamless, oben in das Ende ueberblendet) */
function seamlessV(img, overlap) {
  const { w, h, rgba } = img;
  const ov = Math.round(h * overlap), P = h - ov;
  const out = blank(w, P);
  for (let y = 0; y < P; y++) {
    const t = y < ov ? smooth(y, 0, ov) : 1;
    for (let x = 0; x < w; x++) {
      for (let k = 0; k < 4; k++) {
        const a = rgba[(y * w + x) * 4 + k];
        const b = y < ov ? rgba[((y + P) * w + x) * 4 + k] : a;
        out.rgba[(y * w + x) * 4 + k] = Math.round(b + (a - b) * t);
      }
    }
  }
  return out;
}

/**
 * uf-body 512 x 128: Fluessigkeitskoerper der Kammer (v2-body.png, grau: Rauchschwaden, oben heller, unten tiefer), per
 * Vertexfarbe getoent. Waagrecht nahtlos (Naht ueberblendet), die volle Hoehe = Roehrenhoehe (keine Lagen wie uf-fill).
 */
export const BODY = { w: 512, h: 128, overlap: 0.25 };
export function bodyImage() {
  const seam = seamless(loadSource("v2-body"), BODY.overlap);
  const img = resampleLinear(seam, 0, 0, seam.w, seam.h, BODY.w, BODY.h);
  for (let i = 0; i < BODY.w * BODY.h; i++) { const v = img.rgba[i * 4]; img.rgba.set([v, v, v, 255], i * 4); }
  return img;
}

/**
 * Kolben-Kammer, glatte Oberflaeche: die Lagen sind (1 + 2 x margin) Roehrenhoehen hoch (Glas von v = margin/(1+2m) bis
 * (1+m)/(1+2m)), die Oberflaeche liegt bei v = surf = (margin + gap)/(1 + 2 x margin) als weicher Alpha-Verlauf (soft) - nie
 * als Polygonkante. Gleich in Liquid.PISTON (margin, gap; der Test vergleicht).
 */
export const AIR = { w: 32, h: 256, margin: 0.5, gap: 0.25, soft: 0.014 };
const airSurf = () => (AIR.margin + AIR.gap) / (1 + 2 * AIR.margin);
const glassV = (v) => clamp((v * (1 + 2 * AIR.margin) - AIR.margin), 0, 1); // 0 Glas oben .. 1 Glas unten
const dH = (v) => (v - airSurf()) * (1 + 2 * AIR.margin); // Abstand zur Oberflaeche in Roehrenhoehen (> 0: Fluessigkeit)
/**
 * Klares Glas (Luftspalt und leerer Teil hinter dem Kolben, gleiche Farbe): kuehles Rauchglas, oben heller, mit weicher
 * waagrechter Spiegelung (refl bei reflV, Breite reflW, Anteil der Glashoehe). Werte sRGB 0..1. Hinter dem Kolben leicht
 * durchsichtig (alpha); die Luft ueber der Fluessigkeit muss decken und nimmt dieselbe Farbe ueber dunklem Grund (under).
 */
export const GLASSBACK = { w: 16, h: 64, top: [0.17, 0.2, 0.26], bot: [0.035, 0.045, 0.07], refl: 0.13, reflV: 0.24, reflW: 0.08,
  alpha: 0.72, under: [0.05, 0.07, 0.12] };
const glassColor = (g) => GLASSBACK.top.map((c, k) => c + (GLASSBACK.bot[k] - c) * g
  + GLASSBACK.refl * Math.exp(-(((g - GLASSBACK.reflV) / GLASSBACK.reflW) ** 2)));
/** uf-glassback: Leerglas der Kolben-Kammer hinter dem Kolben (leicht durchsichtig, Farbe wie uf-air ueber der Oberflaeche) */
export function glassBackImage() {
  const { w, h } = GLASSBACK, out = blank(w, h);
  for (let y = 0; y < h; y++) {
    const col = glassColor((y + 0.5) / h).map((c) => clamp(Math.round(c * 255)));
    for (let x = 0; x < w; x++) out.rgba.set([...col, Math.round(GLASSBACK.alpha * 255)], (y * w + x) * 4);
  }
  return out;
}
/** uf-air: Luft im Glas (uf-glassback ueber dunklem Grund), Alpha 1 ueber der Oberflaeche, weich auf 0 */
export function airImage() {
  const { w, h, soft } = AIR, sv = airSurf();
  const out = blank(w, h);
  for (let y = 0; y < h; y++) {
    const v = (y + 0.5) / h, d = v - sv;
    const a = 1 - smooth(d, -soft, soft);
    const refl = 0.025 * Math.exp(-(((d + 0.02) / 0.012) ** 2)); // zarter Widerschein der Oberflaeche am Glas
    const GA = GLASSBACK.alpha, col = glassColor(glassV(v)).map((c, k) => clamp(Math.round((c * GA + GLASSBACK.under[k] * (1 - GA) + refl) * 255)));
    for (let x = 0; x < w; x++) out.rgba.set([...col, Math.round(a * 255)], (y * w + x) * 4);
  }
  return out;
}

/**
 * uf-surfglow 64 x 256 (Lage wie uf-air) aus v2-surface.png: halbtransparentes, helleres Oberflaechenband (man schaut leicht
 * von oben drauf) von der Oberflaeche band x Hoehe nach unten, mit heller Ober- und Vorderkante, darunter der Glow in die
 * Tiefe. Mittelstueck der Vorlage (SURF.crop) waagrecht nahtlos; senkrecht stueckweise linear abgebildet (SURF.map: Abstand
 * in Roehrenhoehen -> Quellzeile). Im Spiel in der Fluessigkeitsfarbe getoent und waagrecht gekachelt.
 */
export const SURF = { w: 64, h: 256, crop: [230, 690], overlap: 0.3,
  map: [[-0.03, 0], [0, 6], [0.13, 31], [0.2, 40], [0.65, 250]], band: 0.13, bandW: 0.7, glow: 0.45, edge: 0.22, edgeW: 0.014 };
export function surfGlowImage() {
  const src = loadSource("v2-surface");
  const [c0, c1] = SURF.crop;
  const crop = blank(c1 - c0, src.h);
  for (let y = 0; y < src.h; y++) {
    for (let x = c0; x < c1; x++) { const a = src.rgba[(y * src.w + x) * 4 + 3]; crop.rgba.set([a, a, a, 255], (y * crop.w + x - c0) * 4); }
  }
  const seam = seamless(crop, SURF.overlap);
  // Spaltenmittel je Ausgabespalte (Box), Zeilen in voller Quellaufloesung
  const cols = Array.from({ length: SURF.w }, () => new Float64Array(src.h));
  const k = seam.w / SURF.w;
  for (let ox = 0; ox < SURF.w; ox++) {
    for (let y = 0; y < src.h; y++) {
      let s = 0, n = 0;
      for (let x = Math.floor(ox * k); x < Math.floor((ox + 1) * k); x++) { s += seam.rgba[(y * seam.w + x) * 4]; n++; }
      cols[ox][y] = s / n / 255;
    }
  }
  const M = SURF.map;
  const srcY = (d) => {
    if (d <= M[0][0] || d >= M[M.length - 1][0]) return -1;
    let i = 0;
    while (d > M[i + 1][0]) i++;
    return M[i][1] + ((d - M[i][0]) / (M[i + 1][0] - M[i][0])) * (M[i + 1][1] - M[i][1]);
  };
  // Band (bandW) mit heller Ober- und Vorderkante (edge), darunter der Glow (glow), weich ineinander
  const weight = (d) => (d < SURF.band ? SURF.bandW : SURF.glow + (SURF.bandW - SURF.glow) * Math.exp(-(((d - SURF.band) / 0.06) ** 2)))
    + SURF.edge * (Math.exp(-((d / SURF.edgeW) ** 2)) + Math.exp(-(((d - SURF.band) / SURF.edgeW) ** 2)));
  const out = blank(SURF.w, SURF.h), SS = 4;
  for (let y = 0; y < SURF.h; y++) {
    for (let x = 0; x < SURF.w; x++) {
      let acc = 0;
      for (let s = 0; s < SS; s++) {
        const d = dH((y + (s + 0.5) / SS) / SURF.h), sy = srcY(d);
        if (sy < 0) continue;
        const y0 = Math.floor(sy), f = sy - y0, col = cols[x];
        const a = col[clamp(y0, 0, src.h - 1)] * (1 - f) + col[clamp(y0 + 1, 0, src.h - 1)] * f;
        acc += a * weight(d);
      }
      out.rgba.set([255, 255, 255, clamp(Math.round((acc / SS) * 255))], (y * SURF.w + x) * 4);
    }
  }
  return out;
}

/**
 * uf-wet 64 x 256 (Lage wie uf-air): Naessefilm am Glas unter der Linie, an die die Fluessigkeit zuletzt hochschwappte -
 * feiner heller Rand an der Linie, darunter ein schwacher, nach unten auslaufender Schimmer; die Rinnspuren kommen aus
 * v2-wet.png (waagrecht nahtlos, senkrecht ueber den Film gedehnt). Weiss, sehr dezent. Im Spiel waagrecht gekachelt.
 */
export const WET = { w: 64, h: 256, lo: 18, hi: 81, film: 0.075 };
export function wetImage() {
  const seam = seamless(loadSource("v2-wet"), 0.25);
  const pat = resampleLinear(seam, 0, 0, seam.w, seam.h, WET.w, 64);
  const sv = airSurf();
  const out = blank(WET.w, WET.h);
  for (let y = 0; y < WET.h; y++) {
    const d = (y + 0.5) / WET.h - sv;
    const row = clamp(Math.floor((d / WET.film) * 64), 0, 63);
    for (let x = 0; x < WET.w; x++) {
      const p = clamp((pat.rgba[(row * WET.w + x) * 4] - WET.lo) / (WET.hi - WET.lo), 0, 1);
      const rim = 0.22 * Math.exp(-((d / 0.016) ** 2)) * (0.6 + 0.4 * p);
      const film = 0.3 * smooth(d, -0.004, 0.004) * (1 - smooth(d, 0.02, WET.film)) * (0.3 + 0.7 * p);
      out.rgba.set([255, 255, 255, Math.round(Math.min(1, rim + film) * 255)], (y * WET.w + x) * 4);
    }
  }
  return out;
}

/** uf-caustic 256 x 128 aus v2-caustic.png: nur die hellen Linien (Alpha), waagrecht und senkrecht nahtlos. Weiss. */
export const CAUSTIC = { w: 256, h: 128, lo: 105, hi: 225 };
export function causticImage() {
  const seam = seamlessV(seamless(loadSource("v2-caustic"), 0.25), 0.25);
  const img = resampleLinear(seam, 0, 0, seam.w, seam.h, CAUSTIC.w, CAUSTIC.h);
  for (let i = 0; i < CAUSTIC.w * CAUSTIC.h; i++) {
    img.rgba.set([255, 255, 255, Math.round(smooth(img.rgba[i * 4], CAUSTIC.lo, CAUSTIC.hi) * 255)], i * 4);
  }
  return img;
}

/**
 * uf-drop 128 x 32: Atlas aus DROP.cells Einzeltropfen von v2-drops.png (Zusammenhangskomponenten nach Flaeche, Raenge
 * DROP.pick), je in einer 32er-Zelle eingepasst (Seitenverhaeltnis bleibt). Farbe der Vorlage (Glanzlichter), im Spiel
 * additiv und getoent; Zelle und Groesse je Tropfen zufaellig (Liquid.PISTON.dropCells/dropScale).
 */
export const DROP = { cell: 32, cells: 4, pick: [0, 2, 4, 7], pad: 2 };
export function dropComponents(src) {
  const { w, h } = src, seen = new Uint8Array(w * h), comps = [];
  for (let i = 0; i < w * h; i++) {
    if (seen[i] || src.rgba[i * 4 + 3] <= 20) continue;
    const stack = [i];
    seen[i] = 1;
    let x0 = w, y0 = h, x1 = 0, y1 = 0, n = 0;
    while (stack.length) {
      const j = stack.pop(), x = j % w, y = (j / w) | 0;
      n++;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          const q = yy * w + xx;
          if (!seen[q] && src.rgba[q * 4 + 3] > 20) { seen[q] = 1; stack.push(q); }
        }
      }
    }
    comps.push({ x0, y0, x1: x1 + 1, y1: y1 + 1, n });
  }
  return comps.sort((a, b) => b.n - a.n);
}
export function dropImage() {
  const src = loadSource("v2-drops");
  const comps = dropComponents(src);
  const { cell, cells, pad } = DROP;
  const out = blank(cell * cells, cell);
  DROP.pick.forEach((r, i) => {
    const c = comps[r];
    const cw = c.x1 - c.x0 + 2, ch = c.y1 - c.y0 + 2, inner = cell - 2 * pad;
    const s = inner / Math.max(cw, ch), ow = Math.max(1, Math.round(cw * s)), oh = Math.max(1, Math.round(ch * s));
    const part = resampleLinear(src, c.x0 - 1, c.y0 - 1, cw, ch, ow, oh);
    const ox = i * cell + Math.floor((cell - ow) / 2), oy = Math.floor((cell - oh) / 2);
    for (let y = 0; y < oh; y++) out.rgba.set(part.rgba.subarray(y * ow * 4, (y + 1) * ow * 4), ((oy + y) * out.w + ox) * 4);
  });
  return bleed(out);
}

export const BUBBLES = { w: 256, h: 64, crop: 1024 };
/** Ausschnitt der Breite crop, dessen Randspalten (je 6 px) leer sind -> nahtlos kachelbar */
export function bubblesImage() {
  const src = loadSource("liquid-bubbles");
  const empty = (x) => {
    for (let d = -6; d <= 6; d++) {
      const xx = ((x + d) % src.w + src.w) % src.w;
      for (let y = 0; y < src.h; y++) if (alphaAt(src, xx, y) > 4) return false;
    }
    return true;
  };
  let x0 = -1;
  for (let x = 0; x + BUBBLES.crop < src.w; x += 2) {
    if (empty(x) && empty(x + BUBBLES.crop)) { x0 = x; break; }
  }
  if (x0 < 0) throw new Error("kein nahtloser Blaeschen-Ausschnitt gefunden");
  return whiten(resampleLinear(src, x0, 0, BUBBLES.crop, src.h, BUBBLES.w, BUBBLES.h));
}

export const GLASS = { w: 512, h: 64, capH: 0.5 }; // Kappe = capH x Quellhoehe
export function glassImage() {
  const src = loadSource("liquid-glass");
  return { img: whiten(resampleLinear(src, 0, 0, src.w, src.h, GLASS.w, GLASS.h)), aspect: src.w / src.h,
    cap: (GLASS.capH * src.h) / src.w };
}

/**
 * Glut der Schadensspur: weicher Glut-Schein (Farbe EMBER.color, senkrecht Gauss, waagrecht an beiden Enden ein-/
 * auslaufend) unter den Gemini-Funken (liquid-ember.png, gespiegelt: hell rechts, mit derselben Endblende). Hell an der
 * Spitze rechts (= alter Lebensstand), nach links verloeschend.
 */
export const EMBER = { w: 512, h: 128, color: [255, 120, 30], glowA: 0.55, sigma: 0.3, inEnd: 0.1, outStart: 0.45 };
export function emberImage() {
  const src = loadSource("liquid-ember");
  const bx = alphaBox(src, 4);
  const sparks = resampleLinear(src, bx.x0, bx.y0, bx.x1 - bx.x0, bx.y1 - bx.y0, EMBER.w, EMBER.h, { flipX: true });
  const out = blank(EMBER.w, EMBER.h);
  for (let y = 0; y < EMBER.h; y++) {
    const v = (y + 0.5) / EMBER.h;
    const vert = Math.exp(-(((v - 0.5) / EMBER.sigma) ** 2));
    for (let x = 0; x < EMBER.w; x++) {
      const u = (x + 0.5) / EMBER.w;
      const hor = smooth(u, 0, EMBER.outStart) * smooth(1 - u, 0, EMBER.inEnd);
      const o = (y * EMBER.w + x) * 4;
      const ga = EMBER.glowA * vert * hor * u; // zur Spitze heller
      const sa = (sparks.rgba[o + 3] / 255) * hor;
      const a = sa + ga * (1 - sa);
      if (a <= 0) continue;
      for (let k = 0; k < 3; k++) out.rgba[o + k] = Math.round((sparks.rgba[o + k] * sa + EMBER.color[k] * ga * (1 - sa)) / a);
      out.rgba[o + 3] = Math.round(a * 255);
    }
  }
  return { img: bleed(out), aspect: (bx.x1 - bx.x0) / (bx.y1 - bx.y0) };
}

// Effekte (Gemini-Bogen sheet-effekte-v1.jpg, freigestellt fx-*.png auf Schwarz) ----------------------------------------------
/**
 * Effekt-Texturen fuer LiquidFx.lua aus den freigegebenen Gemini-Quellen fx-*.png (opak auf Schwarz, fuer ADD gedacht):
 * Luminanz -> Alpha (ueber dem Schwarzpegel floor, weich, gamma), Farbe auf den hellsten Kanal normiert (weiss bei grauen
 * Quellen, Gold bleibt Gold). Zuschnitt auf den hellen Inhalt (pad), Verkleinern in linearem Licht, weiche Raender (edge,
 * Anteil je Seite; 0 = gekachelte Richtung). tileX/tileY: nahtlos ueberblendet (overlap) fuer UV-Lauf.
 */
export const FX = {
  sweep: { file: "uf-fx-sweep", w: 512, h: 64, floor: 0.03, gamma: 1.0, pad: 0.02, edgeX: 0.12, edgeY: 0.15 },
  burst: { file: "uf-fx-burst", w: 128, h: 128, floor: 0.03, gamma: 1.0, pad: 0.02, edgeX: 0.1, edgeY: 0.1, square: true },
  sparkles: { file: "uf-fx-sparkles", w: 256, h: 64, floor: 0.03, gamma: 1.0, pad: 0.04, edgeX: 0.06, edgeY: 0.1 },
  splash: { file: "uf-fx-splash", w: 256, h: 128, floor: 0.05, gamma: 1.0, pad: 0.03, edgeX: 0.06, edgeY: 0.06 },
  flash: { file: "uf-fx-flash", w: 512, h: 64, floor: 0.05, gamma: 1.0, pad: 0.02, edgeX: 0.15, edgeY: 0.12 },
  ink: { file: "uf-fx-ink", w: 512, h: 128, floor: 0.03, gamma: 0.8, pad: 0, edgeX: 0, edgeY: 0.12, tileX: 0.18, blur: 3, boost: 1.35 },
  mana: { file: "uf-fx-mana", w: 512, h: 128, floor: 0.04, gamma: 1.0, pad: 0, edgeX: 0, edgeY: 0, tileX: 0.15, tileY: 0.2 },
};

function lumToAlpha(src, floor, gamma) {
  const out = blank(src.w, src.h);
  for (let i = 0; i < src.w * src.h; i++) {
    const r = src.rgba[i * 4], g = src.rgba[i * 4 + 1], b = src.rgba[i * 4 + 2];
    const m = Math.max(r, g, b);
    const a = smooth((m / 255 - floor) / (1 - floor), 0, 1) ** gamma;
    if (m > 0) {
      out.rgba[i * 4] = Math.round((r / m) * 255);
      out.rgba[i * 4 + 1] = Math.round((g / m) * 255);
      out.rgba[i * 4 + 2] = Math.round((b / m) * 255);
    } else {
      out.rgba.set([255, 255, 255], i * 4);
    }
    out.rgba[i * 4 + 3] = Math.round(a * 255);
  }
  return out;
}

function seamlessH(img, overlap) {
  const { w, h, rgba } = img;
  const ov = Math.round(w * overlap), P = w - ov;
  const out = blank(P, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < P; x++) {
      const t = x < ov ? smooth(x, 0, ov) : 1;
      for (let k = 0; k < 4; k++) {
        const a = rgba[(y * w + x) * 4 + k];
        const b = x < ov ? rgba[(y * w + x + P) * 4 + k] : a;
        out.rgba[(y * P + x) * 4 + k] = Math.round(b + (a - b) * t);
      }
    }
  }
  return out;
}

export function fxImage(name) {
  const F = FX[name];
  let img = lumToAlpha(loadSource(`fx-${name}`), F.floor, F.gamma);
  let box = { x0: 0, y0: 0, x1: img.w, y1: img.h };
  if (!F.tileX && !F.tileY) {
    // Randlinien der Freisteller (Bogen-Raster) weg: 4 px Rand der Quelle durchsichtig
    for (let y = 0; y < img.h; y++) {
      for (let x = 0; x < img.w; x++) {
        if (x < 4 || y < 4 || x >= img.w - 4 || y >= img.h - 4) img.rgba[(y * img.w + x) * 4 + 3] = 0;
      }
    }
    box = alphaBox(img, 10);
    const px = Math.round((box.x1 - box.x0) * F.pad), py = Math.round((box.y1 - box.y0) * F.pad);
    box = { x0: box.x0 - px, y0: box.y0 - py, x1: box.x1 + px, y1: box.y1 + py };
    if (F.square) {
      const cx = (box.x0 + box.x1) / 2, cy = (box.y0 + box.y1) / 2;
      const s = Math.max(box.x1 - box.x0, box.y1 - box.y0) / 2;
      box = { x0: cx - s, y0: cy - s, x1: cx + s, y1: cy + s };
    }
  }
  if (F.tileX) {
    img = seamlessH(img, F.tileX);
    box = { x0: 0, y0: box.y0, x1: img.w, y1: box.y1 };
  }
  if (F.tileY) {
    img = seamlessV(img, F.tileY);
    box = { x0: box.x0, y0: 0, x1: box.x1, y1: img.h };
  }
  const out = resampleLinear(img, box.x0, box.y0, box.x1 - box.x0, box.y1 - box.y0, F.w, F.h);
  for (let y = 0; y < F.h; y++) {
    const v = (y + 0.5) / F.h;
    const wy = F.edgeY ? smooth(v, 0, F.edgeY) * smooth(1 - v, 0, F.edgeY) : 1;
    for (let x = 0; x < F.w; x++) {
      const u = (x + 0.5) / F.w;
      const wx = F.edgeX ? smooth(u, 0, F.edgeX) * smooth(1 - u, 0, F.edgeX) : 1;
      const o = (y * F.w + x) * 4 + 3;
      out.rgba[o] = Math.round(out.rgba[o] * wx * wy);
    }
  }
  if (F.blur) blurAlpha(out, F.blur, F.boost || 1, !!F.tileX);
  return bleed(out);
}

/** Weichzeichnen des Alphas (zwei Box-Durchgaenge je Richtung, Radius r px; wrapX = waagrecht nahtlos), danach x boost */
function blurAlpha(img, r, boost, wrapX) {
  const { w, h, rgba } = img;
  let a = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = rgba[i * 4 + 3];
  const pass = (src, horiz) => {
    const out = new Float64Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let sum = 0, n = 0;
        for (let d = -r; d <= r; d++) {
          let xx = horiz ? x + d : x;
          const yy = horiz ? y : y + d;
          if (horiz && wrapX) xx = (xx + w) % w;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          sum += src[yy * w + xx];
          n++;
        }
        out[y * w + x] = sum / n;
      }
    }
    return out;
  };
  for (let k = 0; k < 2; k++) a = pass(pass(a, true), false);
  for (let i = 0; i < w * h; i++) rgba[i * 4 + 3] = clamp(Math.round(a[i] * boost));
}

/**
 * Glasreflexe v3 (Gemini, freigegeben 16.11. ohne Fensterspiegelung; glas3-*.png grau auf Schwarz, ADD): je Lage ein waagrecht
 * nahtloser Streifen (tileX), Luminanz ueber floor -> Alpha (gamma, x boost), Ausschnitt y0..y1 der Quelle (rim: nur das
 * untere Randlicht), weiche Ober-/Unterkante (edgeY). Liquid.REFL verschiebt sie laengs per UV (yaw) und senkrecht auf dem
 * Zylinderprofil (pitch).
 */
export const GLAS3 = {
  specular: { file: "uf-glass-specular", w: 512, h: 32, floor: 0.03, gamma: 1.0, boost: 1.0, y0: 0, y1: 1, edgeY: 0.15, tileX: 0.15 },
  environment: { file: "uf-glass-env", w: 512, h: 64, floor: 0.35, gamma: 1.2, boost: 1.0, y0: 0, y1: 1, edgeY: 0.2, tileX: 0.15 },
  rim: { file: "uf-glass-rim", w: 512, h: 32, floor: 0.03, gamma: 1.0, boost: 1.2, y0: 0.6, y1: 1, edgeY: 0.15, tileX: 0.15 },
  sparkle: { file: "uf-glass-sparkle", w: 512, h: 64, floor: 0.02, gamma: 0.8, boost: 1.8, y0: 0, y1: 1, edgeY: 0.12, tileX: 0.15 },
};
export function glas3Image(name) {
  const G = GLAS3[name];
  let img = lumToAlpha(loadSource(`glas3-${name}`), G.floor, G.gamma);
  img = seamlessH(img, G.tileX);
  const y0 = Math.round(img.h * G.y0), y1 = Math.round(img.h * G.y1);
  const out = resampleLinear(img, 0, y0, img.w, y1 - y0, G.w, G.h);
  for (let y = 0; y < G.h; y++) {
    const v = (y + 0.5) / G.h;
    const wy = smooth(v, 0, G.edgeY) * smooth(1 - v, 0, G.edgeY);
    for (let x = 0; x < G.w; x++) {
      const o = (y * G.w + x) * 4;
      out.rgba[o] = 255; out.rgba[o + 1] = 255; out.rgba[o + 2] = 255;
      out.rgba[o + 3] = clamp(Math.round(out.rgba[o + 3] * wy * G.boost));
    }
  }
  return out;
}

// Effektbogen v2 (fx2-*.png, freigegeben 16.11.: grobe Sprites fuer ~220 x 20 px Roehren) ------------------------------------
/**
 * Atlanten aus nebeneinander stehenden Sprites (Spalten mit Inhalt, Luecken < merge px zusammengefasst): je Sprite eine
 * quadratische Zelle (cell px, Inhalt zentriert, pad Rand), Luminanz ueber floor -> Alpha, Farbe weiss, weiche Zellraender.
 * Streifen (cells fehlt): ganzes Bild, waagrecht nahtlos (tileX), weichgezeichnet (blur) - die Status-Wolken; bzw. Gischt.
 * Zellenzahl im Atlas = 2er-Potenz (n), ungenutzte Zellen leer. Lua liest die Zellen aus LiquidFx/LiquidFizz (FX2-Tabellen).
 */
export const FX2 = {
  bubbles: { file: "uf-fx2-bubbles", src: "fx2-bubbles", cells: 5, n: 8, cell: 64, floor: 0.03, pad: 0.04, merge: 40 },
  pop: { file: "uf-fx2-pop", src: "fx2-pop", cells: 4, n: 4, cell: 64, floor: 0.03, pad: 0.04, merge: 60 },
  sparks: { file: "uf-fx2-sparks", src: "fx2-sparks", cells: 7, n: 8, cell: 64, floor: 0.03, pad: 0.06, merge: 70 },
  foam: { file: "uf-fx2-foam", src: "fx2-foam", w: 256, h: 128, floor: 0.08, gamma: 1.0, edgeX: 0.08, edgeY: 0.06 },
};

export function fx2Atlas(name) {
  const A = FX2[name];
  const img = lumToAlpha(loadSource(A.src), A.floor, 1);
  const { w, h } = img;
  const colOn = (x) => {
    for (let y = 0; y < h; y++) if (img.rgba[(y * w + x) * 4 + 3] > 24) return true;
    return false;
  };
  let segs = [], st = -1, gap = 0;
  for (let x = 0; x <= w; x++) {
    const on = x < w && colOn(x);
    if (on) {
      if (st < 0) st = x;
      gap = 0;
    } else if (st >= 0) {
      gap++;
      if (gap > A.merge || x === w) {
        segs.push([st, x - gap + 1]);
        st = -1;
        gap = 0;
      }
    }
  }
  segs = segs.filter((sg) => sg[1] - sg[0] > 6);
  if (segs.length !== A.cells) throw new Error(`${name}: ${segs.length} Sprites statt ${A.cells}`);
  const out = blank(A.n * A.cell, A.cell);
  segs.forEach(([x0, x1], i) => {
    let y0 = h, y1 = 0;
    for (let y = 0; y < h; y++) for (let x = x0; x < x1; x++) if (img.rgba[(y * w + x) * 4 + 3] > 24) { y0 = Math.min(y0, y); y1 = Math.max(y1, y + 1); }
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    const half = (Math.max(x1 - x0, y1 - y0) / 2) * (1 + A.pad);
    const cellImg = resampleLinear(img, cx - half, cy - half, 2 * half, 2 * half, A.cell, A.cell);
    for (let y = 0; y < A.cell; y++) {
      const v = (y + 0.5) / A.cell;
      for (let x = 0; x < A.cell; x++) {
        const u = (x + 0.5) / A.cell;
        const win = smooth(u, 0, 0.05) * smooth(1 - u, 0, 0.05) * smooth(v, 0, 0.05) * smooth(1 - v, 0, 0.05);
        const so = (y * A.cell + x) * 4, d = (y * out.w + i * A.cell + x) * 4;
        out.rgba[d] = 255; out.rgba[d + 1] = 255; out.rgba[d + 2] = 255;
        out.rgba[d + 3] = Math.round(cellImg.rgba[so + 3] * win);
      }
    }
  });
  return out;
}

export function fx2Strip(name) {
  const A = FX2[name];
  let img = lumToAlpha(loadSource(A.src), A.floor, A.gamma);
  if (A.tileX) img = seamlessH(img, A.tileX);
  const out = resampleLinear(img, 0, 0, img.w, img.h, A.w, A.h);
  for (let y = 0; y < A.h; y++) {
    const v = (y + 0.5) / A.h;
    const wy = A.edgeY ? smooth(v, 0, A.edgeY) * smooth(1 - v, 0, A.edgeY) : 1;
    for (let x = 0; x < A.w; x++) {
      const u = (x + 0.5) / A.w;
      const wx = A.edgeX ? smooth(u, 0, A.edgeX) * smooth(1 - u, 0, A.edgeX) : 1;
      const o = (y * A.w + x) * 4;
      out.rgba[o] = 255; out.rgba[o + 1] = 255; out.rgba[o + 2] = 255;
      out.rgba[o + 3] = Math.round(out.rgba[o + 3] * wx * wy);
    }
  }
  if (A.blur) blurAlpha(out, A.blur, A.boost || 1, !!A.tileX);
  return out;
}

// Ziel-Zier (Bogen sheet-ziel-teile-v1.jpg, freigestellt per scripts/cut-ziel-teile.mjs -> ziel-*.png) ----------------------
// Drachen/Boss-Kamm tragen einen eigenen Ring. Lucid behaelt seinen uf-ring (gleiche Optik wie ohne Klassifikation) und
// zerlegt jedes Teil an seinem Ring (Mitte/Innenradius aus dem Loch gemessen, ZIEL.rin Texel gross):
//   back  (ZIEL.backW x backH): alles ausserhalb des Ringbands (Fluegel, Kopf, Schwanz, Hoerner) - liegt UNTER uf-ring,
//   front (ZIEL.front x front, Ringmitte = Texturmitte): im Ringband nur, was nicht nach Ring aussieht (Krallen, Hals,
//          Schwanzwindungen ueber dem Ring) - liegt UEBER uf-ring. Der eigene Ring des Teils faellt per radialer Maske weg:
//          Vergleich mit dem Ringprofil (Median je Radius an freien Winkeln ZIEL.clean) ueber Farbart + Helligkeit.
export const ZIEL = { rin: 76, backW: 256, backH: 512, front: 256, band: [0.95, 1.3], dist: [26, 52], bin: 0.01,
  clean: { elite: [[140, 220]], rare: [[140, 230]], rareelite: [[170, 240]], boss: [[150, 230], [310, 350]] } };
export const ZIEL_KINDS = ["elite", "rare", "rareelite", "boss"];

/** Ring eines Zier-Teils: Loch = groesste durchsichtige Flaeche ohne Bildrand-Kontakt; Mitte aus Breite und Oberkante
 *  (unten kann der Boss-Totenkopf ins Loch ragen), y nach unten */
export function decoRing(img) {
  const inv = { w: img.w, h: img.h, rgba: new Uint8Array(img.rgba.length) };
  for (let i = 0; i < img.w * img.h; i++) inv.rgba[i * 4 + 3] = img.rgba[i * 4 + 3] < 128 ? 255 : 0;
  const { comps } = components(inv, 128);
  const hole = comps.filter((c) => c.x0 > 0 && c.y0 > 0 && c.x1 < img.w && c.y1 < img.h).sort((a, b) => b.n - a.n)[0];
  if (!hole) throw new Error("Ringloch nicht gefunden");
  const rin = (hole.x1 - hole.x0) / 2;
  return { cx: (hole.x0 + hole.x1) / 2, cy: hole.y0 + rin, rin };
}

const lum = (r, g, b) => 0.299 * r + 0.587 * g + 0.114 * b;
/** Farbabstand zum Ringprofil: Farbart (g/r, b/r) stark gewichtet, dazu Helligkeit (Schatten auf Gold bleibt Gold) */
const ringDist = (r, g, b, p) => {
  const rr = Math.max(r, 8), pr = Math.max(p[0], 8);
  const dc = Math.hypot(g / rr - p[1] / pr, b / rr - p[2] / pr) * 160;
  return dc + Math.abs(lum(r, g, b) - lum(p[0], p[1], p[2])) * 0.35;
};

/** Ringprofil: Median-Farbe je Radius-Bin (Anteil von rin) an den freien Winkeln; leere Bins vom Nachbarn */
function ringProfile(img, ring, kind) {
  const Z = ZIEL, n = Math.round((Z.band[1] - Z.band[0]) / Z.bin) + 1;
  const bins = Array.from({ length: n }, () => [[], [], []]);
  for (const [a0, a1] of Z.clean[kind]) {
    for (let deg = a0; deg <= a1; deg += 0.5) {
      const an = (deg * Math.PI) / 180;
      for (let k = 0; k < n; k++) {
        const r = (Z.band[0] + k * Z.bin) * ring.rin;
        const x = Math.round(ring.cx + r * Math.cos(an)), y = Math.round(ring.cy - r * Math.sin(an));
        if (x < 0 || y < 0 || x >= img.w || y >= img.h) continue;
        const o = (y * img.w + x) * 4;
        if (img.rgba[o + 3] < 200) continue;
        for (let c = 0; c < 3; c++) bins[k][c].push(img.rgba[o + c]);
      }
    }
  }
  const med = (a) => { const s = a.slice().sort((p, q) => p - q); return s[s.length >> 1]; };
  const prof = bins.map((b) => (b[0].length >= 8 ? [med(b[0]), med(b[1]), med(b[2])] : null));
  for (let pass = 0; pass < n; pass++) {
    for (let k = 0; k < n; k++) if (!prof[k]) prof[k] = prof[k - 1] || prof[k + 1] || null;
  }
  return prof;
}

/** Zier-Teil -> { back, front, cx, cy } (cx/cy: Ringmitte in der back-Textur, Anteile) */
export function decoImages(kind) {
  const Z = ZIEL, src = loadSource("ziel-" + kind), ring = decoRing(src), prof = ringProfile(src, ring, kind);
  const n = prof.length, { w, h } = src;
  const backSrc = { w, h, rgba: new Uint8Array(src.rgba) };
  const frontSrc = { w, h, rgba: new Uint8Array(src.rgba.length) };
  const mask = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x, o = i * 4;
      if (src.rgba[o + 3] === 0) continue;
      const rr = Math.hypot(x + 0.5 - ring.cx, y + 0.5 - ring.cy) / ring.rin;
      if (rr >= Z.band[1]) continue; // back
      if (rr < Z.band[0]) { mask[i] = 1; continue; } // im Loch: ueber dem Portraet wie im Entwurf
      const p = prof[Math.max(0, Math.min(n - 1, Math.round((rr - Z.band[0]) / Z.bin)))];
      mask[i] = p ? smooth(ringDist(src.rgba[o], src.rgba[o + 1], src.rgba[o + 2], p), Z.dist[0], Z.dist[1]) : 1;
    }
  }
  // weich: 3 x 3 Mittel der Maske (keine Einzelpixel-Kanten), dann aufteilen
  const soft = new Float32Array(w * h);
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      let s = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s += mask[(y + dy) * w + x + dx];
      soft[y * w + x] = s / 9;
    }
  }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x, o = i * 4;
      const rr = Math.hypot(x + 0.5 - ring.cx, y + 0.5 - ring.cy) / ring.rin;
      if (rr >= Z.band[1]) continue;
      for (let c = 0; c < 3; c++) frontSrc.rgba[o + c] = src.rgba[o + c];
      frontSrc.rgba[o + 3] = Math.round(src.rgba[o + 3] * soft[i]);
      backSrc.rgba[o + 3] = 0;
    }
  }
  const s = Z.rin / ring.rin;
  const ox = Math.round((Z.backW - w * s) / 2), oy = Math.round((Z.backH - h * s) / 2);
  const back = bleed(resampleLinear(backSrc, -ox / s, -oy / s, Z.backW / s, Z.backH / s, Z.backW, Z.backH));
  const half = Z.front / 2 / s;
  const front = bleed(resampleLinear(frontSrc, ring.cx - half, ring.cy - half, 2 * half, 2 * half, Z.front, Z.front));
  return { back, front, cx: (ox + ring.cx * s) / Z.backW, cy: (oy + ring.cy * s) / Z.backH };
}

/** Kleinteile: quadratisch (Fassungen, Stein, Plakette) */
export const ZIEL_SMALL = { marker: 64, markerSmall: 64, gem: 64, aura: 64, level: 128 };
const partImage = (name, size, pad = 0.01) => squareCrop(loadSource(name), size, pad);
/** Stufen-Plakette: Scheibenmitte (Breite = Durchmesser, ab Oberkante) und Mitte der Stein-Fassung (dunkle Raute unten),
 *  als Anteile der quadratischen Textur (squareCrop mit pad 0.01) */
export function levelGeometry() {
  const img = loadSource("ziel-level"), bx = alphaBox(img);
  const bw = bx.x1 - bx.x0, bh = bx.y1 - bx.y0, side = Math.max(bw, bh) * 1.02;
  const sx = (bx.x0 + bx.x1) / 2 - side / 2, sy = (bx.y0 + bx.y1) / 2 - side / 2;
  let gx = 0, gy = 0, gn = 0;
  for (let y = Math.floor(bx.y0 + bh * 0.8); y < bx.y1; y++) {
    for (let x = Math.floor(bx.x0 + bw * 0.35); x < bx.x0 + bw * 0.65; x++) {
      const o = (y * img.w + x) * 4;
      if (img.rgba[o + 3] > 200 && lum(img.rgba[o], img.rgba[o + 1], img.rgba[o + 2]) < 75) { gx += x; gy += y; gn++; }
    }
  }
  const discR = bw / 2;
  return { cx: ((bx.x0 + bx.x1) / 2 - sx) / side, cy: (bx.y0 + discR - sy) / side, r: discR / side,
    gx: (gx / gn - sx) / side, gy: (gy / gn - sy) / side };
}
/** Fassung (Marker/Aura): Radius der dunklen Innenflaeche (Anteil des halben Durchmessers), Mittel ueber 36 Strahlen */
export function socketInner(name) {
  const img = partImage(name, 256), c = 128;
  let sum = 0;
  for (let k = 0; k < 36; k++) {
    const an = (k * Math.PI) / 18;
    let r = 1;
    while (r < c) {
      const o = (Math.floor(c + r * Math.sin(an)) * 256 + Math.floor(c + r * Math.cos(an))) * 4;
      if (lum(img.rgba[o], img.rgba[o + 1], img.rgba[o + 2]) > 70) break;
      r++;
    }
    sum += r;
  }
  return sum / 36 / c;
}
/** Aura-Fassung mit ausgestanzter Innenflaeche (das Zaubersymbol liegt darunter, die Fassung als Rahmen darueber):
 *  Alpha 0 bis AURA_HOLE x Innenradius, weich auslaufend ueber AURA_HOLE_SOFT */
export const AURA_HOLE = 0.97, AURA_HOLE_SOFT = 0.05;
export function auraImage() {
  const img = partImage("ziel-aura", ZIEL_SMALL.aura), inner = socketInner("ziel-aura"), n = img.w, c = n / 2;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const r = Math.hypot(x + 0.5 - c, y + 0.5 - c) / c / inner;
      const k = smooth(r, AURA_HOLE - AURA_HOLE_SOFT, AURA_HOLE);
      const o = (y * n + x) * 4 + 3;
      img.rgba[o] = Math.round(img.rgba[o] * k);
    }
  }
  return img;
}
/** Portraetring mit Rohraufnahmen (Gemini-Bogen sheet-ring-aufnahme-v4.jpg, freigestellt per scripts/cut-ring-aufnahme.mjs):
 *  ring-aufnahme.png. Ring rechts, links zwei flache Aufnahmen (oben Lebens-, darunter Ressourcenroehre), je von links:
 *  Manschette mit Lippe -> offenes Fenster (Haarlinien oben/unten, innen durchsichtig) -> Sockel, der ins Ringband fliesst.
 *  Saum entfaerben, quadratisch um die Alpha-Box auf SOCKET.size verkleinern (Ring sitzt dadurch aussermittig), Farbe in
 *  leere Texel ziehen. Spieler: dieselbe Textur waagrecht gespiegelt (TexCoord). */
export const SOCKET = { size: 512, pad: 0.004, src: "ring-aufnahme", file: "uf-ring-aufnahme",
  outerSkip: [110, 250], depth: 0.5 };
function socketCrop() {
  const src = cleanFringe(loadSource(SOCKET.src));
  const bx = alphaBox(src);
  const side = Math.max(bx.x1 - bx.x0, bx.y1 - bx.y0) * (1 + 2 * SOCKET.pad);
  return { src, side, x0: (bx.x0 + bx.x1) / 2 - side / 2, y0: (bx.y0 + bx.y1) / 2 - side / 2 };
}
export function socketImage() {
  const c = socketCrop();
  return bleed(resampleLinear(c.src, c.x0, c.y0, c.side, c.side, SOCKET.size, SOCKET.size));
}

/** Kreis durch Punkte (algebraisch, Kasa): Mitte und Radius */
function fitCircle(pts) {
  let sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, sxz = 0, syz = 0, sz = 0;
  for (const [x, y] of pts) {
    const z = x * x + y * y;
    sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; sxz += x * z; syz += y * z; sz += z;
  }
  const M = [[sxx, sxy, sx, -sxz], [sxy, syy, sy, -syz], [sx, sy, pts.length, -sz]];
  for (let i = 0; i < 3; i++) for (let j = i + 1; j < 3; j++) {
    const q = M[j][i] / M[i][i];
    for (let c = i; c < 4; c++) M[j][c] -= q * M[i][c];
  }
  const v = [0, 0, 0];
  for (let i = 2; i >= 0; i--) {
    let t = M[i][3];
    for (let c = i + 1; c < 3; c++) t -= M[i][c] * v[c];
    v[i] = t / M[i][i];
  }
  const cx = -v[0] / 2, cy = -v[1] / 2;
  return { cx, cy, r: Math.sqrt(cx * cx + cy * cy - v[2]) };
}

/** Ringkreis der Vorlage (Quell-Pixel): Innenkante ueber 360 Strahlen ab der Mitte, Aussenkante von aussen ohne die
 *  Aufnahmen-Seite (SOCKET.outerSkip, Grad, 180 = links); je Kreisfit, zweimal mit der neuen Mitte. Mitte = Mittel beider. */
export function socketRing(src) {
  const op = (x, y) => {
    x = Math.floor(x); y = Math.floor(y);
    return x >= 0 && y >= 0 && x < src.w && y < src.h && src.rgba[(y * src.w + x) * 4 + 3] > 128;
  };
  const box = alphaBox(src);
  let c = { cx: box.x1 - (box.y1 - box.y0) / 2, cy: (box.y0 + box.y1) / 2 }, fi, fo;
  const far = Math.hypot(src.w, src.h);
  for (let it = 0; it < 3; it++) {
    const inner = [], outer = [];
    for (let k = 0; k < 360; k++) {
      const an = (k * Math.PI) / 180, dx = Math.cos(an), dy = Math.sin(an);
      let r = 0;
      while (r < far && !op(c.cx + r * dx, c.cy + r * dy)) r++;
      inner.push([c.cx + r * dx, c.cy + r * dy]);
      if (k > SOCKET.outerSkip[0] && k < SOCKET.outerSkip[1]) continue;
      let ro = far;
      while (ro > 0 && !op(c.cx + ro * dx, c.cy + ro * dy)) ro--;
      outer.push([c.cx + ro * dx, c.cy + ro * dy]);
    }
    fi = fitCircle(inner);
    fo = fitCircle(outer);
    c = { cx: (fi.cx + fo.cx) / 2, cy: (fi.cy + fo.cy) / 2 };
  }
  return { cx: c.cx, cy: c.cy, inner: fi.r, outer: fo.r };
}

/** Rohraufnahmen der Vorlage (Quell-Pixel, Bild-y nach unten), von oben: je Manschette (linke Aussenkante cuff, Ober-/
 *  Unterkante cuffTop/cuffBot), Fenster (win = Ende der Manschette, sock = Sockelbeginn, Innenkanten top/bot, Aussenkanten
 *  der Haarlinien rimTop/rimBot) und die Ring-Innenkante (inner = kleinstes x der Portraetflaeche in den Fensterzeilen) */
export function socketWindows(src) {
  const op = (x, y) => src.rgba[(y * src.w + x) * 4 + 3] > 128;
  const box = alphaBox(src), x = box.x0 + 2, runs = [];
  for (let y = 0, s = -1; y <= src.h; y++) {
    const o = y < src.h && op(x, y);
    if (o && s < 0) s = y;
    if (!o && s >= 0) { runs.push([s, y]); s = -1; }
  }
  const cuffs = runs.filter(([a, b]) => b - a > 20);
  if (cuffs.length !== 2) throw new Error("Rohraufnahmen nicht erkannt: " + JSON.stringify(runs));
  return cuffs.map(([cuffTop, cuffBot]) => {
    const yc = Math.round((cuffTop + cuffBot) / 2);
    let xx = box.x0;
    while (xx < src.w && !op(xx, yc)) xx++;
    const cuff = xx;
    while (xx < src.w && op(xx, yc)) xx++;
    const win = xx;
    while (xx < src.w && !op(xx, yc)) xx++;
    const sock = xx;
    if (sock >= src.w || sock - win < 4) throw new Error("Fenster nicht erkannt (Zeile " + yc + ")");
    const xm = Math.round((win + sock) / 2);
    let t = yc, b = yc;
    while (t > 0 && !op(xm, t - 1)) t--;
    let rt = t;
    while (rt > 0 && op(xm, rt - 1)) rt--;
    while (b < src.h - 1 && !op(xm, b)) b++;
    let rb = b;
    while (rb < src.h && op(xm, rb)) rb++;
    let inner = src.w;
    for (let y = t; y < b; y++) {
      let k = sock;
      while (k < src.w && !op(k, y)) k++; // Sockelkante steht nicht in jeder Zeile genau bei sock
      while (k < src.w && op(k, y)) k++;
      inner = Math.min(inner, k);
    }
    return { cuff, cuffTop, cuffBot, win, sock, top: t, bot: b, rimTop: rt, rimBot: rb, inner };
  });
}

/** Lage fuer Deco.GEO.socket: cx/cy = Ringmitte (Anteil der Texturbreite/-hoehe, y ab oben), size = Texturbreite / Ring-
 *  Durchmesser (uf-ring-Groesse ringSize), inner/outer = Ringkanten (Anteil des halben Durchmessers). Der Ringkreis sitzt mit
 *  der Bandmitte auf der Bandmitte von uf-ring (ring = deren Innen-/Aussenradius). Je Roehre (Anteile des halben
 *  Durchmessers, zur Ringmitte, x nach rechts, y nach oben; Ring rechts wie am Ziel): Fenster top/bot (Innenkanten),
 *  rimTop/rimBot (Aussenkanten der Haarlinien), cuff/win/sock (Manschette, Fensterbeginn, Sockelbeginn), endX = Roehrenende
 *  (SOCKET.depth zwischen Sockelbeginn und Ring-Innenkante: verdeckt, nie im Portraet). */
export function socketGeometry(ring = { inner: ringInner(ringImage()), outer: ringOuter(ringImage()) }) {
  const c = socketCrop(), R = socketRing(c.src), W = socketWindows(c.src);
  const half = ((R.inner + R.outer) / 2) / ((ring.inner + ring.outer) / 2); // Quell-Pixel je halbem uf-ring-Durchmesser
  const X = (x) => (x - R.cx) / half, Y = (y) => (R.cy - y) / half;
  const tube = (w) => ({ top: Y(w.top), bot: Y(w.bot), rimTop: Y(w.rimTop), rimBot: Y(w.rimBot), cuff: X(w.cuff), win: X(w.win),
    sock: X(w.sock), endX: X(w.sock + SOCKET.depth * (w.inner - w.sock)) });
  return { cx: (R.cx - c.x0) / c.side, cy: (R.cy - c.y0) / c.side, size: c.side / (2 * half), inner: R.inner / half,
    outer: R.outer / half, health: tube(W[0]), power: tube(W[1]) };
}

// Messwerte fuer Liquid.lua / Skin.lua (der Test vergleicht sie mit den Konstanten dort) -------------------------------------
const r4 = (v) => Math.round(v * 10000) / 10000;
export function measurements() {
  const frames = {};
  for (const [k, name] of Object.entries(FRAME_SRC)) {
    const m = measureFrame(loadSource(name));
    frames[k] = { srcW: m.srcW, srcH: m.srcH, openL: m.open.l, openT: m.open.t, openR: m.open.r, openB: m.open.b,
      sliceL: m.slice.l, sliceR: m.slice.r };
  }
  const g = loadSource("liquid-glass");
  const eb = alphaBox(loadSource("liquid-ember"), 4);
  return { frames, glass: { aspect: r4(g.w / g.h), cap: r4((GLASS.capH * g.h) / g.w) },
    ember: { aspect: r4((eb.x1 - eb.x0) / (eb.y1 - eb.y0)) }, piston: { aspect: r4(pistonAspect()) },
    air: { margin: AIR.margin, gap: AIR.gap }, drop: { cells: DROP.cells }, ringInner: r4(ringInner(ringImage())),
    ziel: zielMeasurements() };
}

/** Lagen der Ziel-Zier fuer TargetDeco.lua (Deco.GEO) */
export function zielMeasurements() {
  const ring = ringImage();
  const out = { rin: ZIEL.rin, backW: ZIEL.backW, backH: ZIEL.backH, front: ZIEL.front,
    ring: { inner: r4(ringInner(ring)), outer: r4(ringOuter(ring)) } };
  for (const k of ZIEL_KINDS) {
    const d = decoImages(k);
    out[k] = { cx: r4(d.cx), cy: r4(d.cy) };
  }
  const lv = levelGeometry();
  out.level = { cx: r4(lv.cx), cy: r4(lv.cy), r: r4(lv.r), gx: r4(lv.gx), gy: r4(lv.gy) };
  out.aura = { inner: r4(socketInner("ziel-aura")) };
  out.marker = { inner: r4(socketInner("ziel-marker")) };
  const sg = socketGeometry(out.ring);
  const round = (o) => Object.fromEntries(Object.entries(o).map(([k, val]) => [k, typeof val === "object" ? round(val) : r4(val)]));
  out.socket = round(sg);
  return out;
}

export function zielFiles() {
  const list = [];
  for (const k of ZIEL_KINDS) {
    const d = decoImages(k);
    list.push({ file: `uf-ziel-${k}.tga`, img: d.back }, { file: `uf-ziel-${k}-front.tga`, img: d.front });
  }
  const S = ZIEL_SMALL;
  list.push({ file: "uf-ziel-marker.tga", img: partImage("ziel-marker", S.marker) });
  list.push({ file: "uf-ziel-marker-small.tga", img: partImage("ziel-marker-small", S.markerSmall) });
  list.push({ file: "uf-ziel-gem.tga", img: partImage("ziel-gem", S.gem, 0.02) });
  list.push({ file: "uf-ziel-aura.tga", img: auraImage() });
  list.push({ file: "uf-ziel-level.tga", img: partImage("ziel-level", S.level) });
  list.push({ file: SOCKET.file + ".tga", img: socketImage() });
  return list;
}

export function files() {
  const list = [
    { file: "uf-ring.tga", img: ringImage() },
    { file: "uf-level-square.tga", img: plateImage("plate-square") },
    { file: "uf-level-round.tga", img: plateImage("plate-round") },
  ];
  for (const [k, name] of Object.entries(FRAME_SRC)) list.push({ file: `uf-frame-${k}.tga`, img: frameImage(loadSource(name)) });
  for (const [key, M] of Object.entries(MASKS)) {
    const src = loadSource(M.src);
    const m = measureFrame(src);
    const dil = Math.round((m.open.b - m.open.t) * MASK_DILATE);
    list.push({ file: M.file, img: maskFromOpening(src, m, M.w, M.h, M.ratio, dil) });
    if (!OPEN_MASKS[key]) continue;
    for (const side of OPEN_SIDES) {
      list.push({ file: M.file.replace(".tga", `-open${side}.tga`), img: maskFromOpening(src, m, M.w, M.h, M.ratio, dil, side) });
    }
  }

  list.push({ file: "uf-fill.tga", img: fillImage() });
  list.push({ file: "uf-edge-cover.tga", img: edgeCoverImage() });
  list.push({ file: "uf-edge-rim.tga", img: edgeRimImage() });
  list.push({ file: "uf-mask-endright.tga", img: endMaskImage(false) });
  list.push({ file: "uf-mask-endfade.tga", img: endMaskImage(true) });
  list.push({ file: "uf-mask-fadein.tga", img: fadeInImage() });
  list.push({ file: "uf-piston.tga", img: pistonImage() });
  list.push({ file: "uf-air.tga", img: airImage() });
  list.push({ file: "uf-body.tga", img: bodyImage() });
  list.push({ file: "uf-glassback.tga", img: glassBackImage() });
  list.push({ file: "uf-surfglow.tga", img: surfGlowImage() });
  list.push({ file: "uf-wet.tga", img: wetImage() });
  list.push({ file: "uf-caustic.tga", img: causticImage() });
  list.push({ file: "uf-drop.tga", img: dropImage() });
  list.push({ file: "uf-bubbles.tga", img: bubblesImage() });
  list.push({ file: "uf-glass.tga", img: glassImage().img });
  list.push({ file: "uf-ember.tga", img: emberImage().img });
  list.push({ file: "uf-glint.tga", img: glintImage() });
  for (const [k, G] of Object.entries(GLAS3)) list.push({ file: `${G.file}.tga`, img: glas3Image(k) });
  for (const [k, F] of Object.entries(FX)) list.push({ file: `${F.file}.tga`, img: fxImage(k) });
  for (const [k, A] of Object.entries(FX2)) list.push({ file: `${A.file}.tga`, img: A.cells ? fx2Atlas(k) : fx2Strip(k) });
  list.push(...zielFiles());
  return list;
}

function run() {
  for (const { file, img } of files()) {
    const buf = tgaRgba(img);
    writeFileSync(path.join(MEDIA, file), buf);
    console.log(`${file}: ${img.w} x ${img.h}, ${buf.length} B`);
  }
  console.log(JSON.stringify(measurements(), null, 1));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) run();
