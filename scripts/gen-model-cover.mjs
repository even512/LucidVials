// Abdeckung fuer den Portrait-Stil "Modell" (modules/UnitFrames/PortraitModel.lua): 256 x 256 RGBA-TGA (32 bit), weiss (Farbe per
// Vertexfarbe = dunkler Glas-Grund), Alpha als Kreisring: innen durchsichtig (Loch), weicher Innenrand, deckend bis kurz vor den
// Texturrand, ganz aussen weich auf 0 (liegt unter dem Bronzering). Masken wirken nicht auf Modelle: diese Lage liegt ueber dem
// Modell und verdeckt die geraden Kanten des quadratischen Modell-Frames (halbe Kante = Model.SIZE / 2 = 0,42 x Portrait, also
// rho = 0,84 >= HOLE). rho = Abstand zur Mitte / halbe Texturbreite.
// Aufruf: node scripts/gen-model-cover.mjs
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tgaRgba } from "./media-lib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const SIZE = 256;
export const HOLE_SOFT = 0.76; // ab hier beginnt der weiche Innenrand
export const HOLE = 0.83;      // ab hier deckend
export const OUTER = 0.96;     // ab hier weich nach aussen auslaufen (bis 1,0)

const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

export function coverAlpha(rho) {
  return smooth(rho, HOLE_SOFT, HOLE) * (1 - smooth(rho, OUTER, 1));
}

export function build() {
  const rgba = Buffer.alloc(SIZE * SIZE * 4);
  const c = (SIZE - 1) / 2;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const rho = Math.hypot(x - c, y - c) / (SIZE / 2);
      const i = (y * SIZE + x) * 4;
      rgba[i] = rgba[i + 1] = rgba[i + 2] = 255;
      rgba[i + 3] = Math.round(255 * coverAlpha(rho));
    }
  }
  return tgaRgba({ w: SIZE, h: SIZE, rgba });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const out = path.join(ROOT, "addon", "LucidVials", "Media", "uf-portrait-model-cover.tga");
  writeFileSync(out, build());
  console.log("geschrieben:", path.relative(ROOT, out));
}
