// Sichtvorschau der Erfahrungsleiste als Fluessigkeits-Roehre (modules/UnitFrames/XP.lua), vor dem Spieltest:
//   node scripts/preview-xp.mjs [--out docs/unitframe-src/vorschau-xp.png] [--zoom 2]
// Drei Zustaende an Blizzards Retail-Leiste (565 x 11, Kappen eingerueckt wie XP.lua layout): normal (violett, 40 %),
// ausgeruht (blau, 40 % + dunklerer Ruhe-Abschnitt bis 70 %), Stufenaufstieg (golden voll, Gischt-Krone und Schaum an der
// Glasdecke wie Liquid.BREAK). Darunter Forever (1189 x 14) ausgeruht in halber Groesse. Farben/Konstanten aus dem Lua-Code
// (Test-VM), Texturen aus addon/LucidVials/Media; Baukasten scripts/preview-unitframe.mjs tube().
import path from "node:path";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";
import { tube, setZoom, htmlOf, LIQ, abs, renderHtml, texUrl } from "./preview-unitframe.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", "docs/unitframe-src/vorschau-xp.png"));
const Z = Number(opt("--zoom", 2));
setZoom(Z);

const vm = createVm();
const XP = vm.lua("return NS.UnitFrameXP");
const L = LIQ, F = L.UF_FRAMES.power, U = L.UF_FRAME, B = L.BREAK, PP = L.PISTON;

/** XP-Roehre an Blizzards Leiste (bx, by, bw, bh): Enden um den Kappenrand eingerueckt (Liquid.SetEnds wie XP.lua) */
function xpTube({ bx, by, bw, bh, tint, fill, reserve = null, levelup = false }) {
  const total = bh + Math.max(U.extraMin, bh * U.extraRel), s = total / F.srcH;
  const pad = Math.max(F.openL, F.srcW - F.openR) * s;
  const x = bx + pad, w = bw - 2 * pad;
  const r = tube({ kind: "power", x, y: by, w, h: bh, mirror: false, tint, fill, style: "piston", maskName: "uf-mask-xp", dy: 0,
    reserve });
  let html = r.html;
  if (levelup) { // Ueberschwappen: Gischt-Krone am Kamm, Schaumstreifen an der Glasdecke (stepBreak, Mitte des Ablaufs)
    const th = (F.openB - F.openT) * s, ty = by + bh / 2 - th / 2;
    for (const cx of [0.32, 0.71]) {
      const kx = x + w * cx, cw = B.crownW * th * 1.05, ch = B.crownH * th * 0.85;
      html += `<div style="${abs(kx - cw / 2, ty + PP.gap * th + 0.35 * th - ch, cw, ch, `background:url(${crown});background-size:100% 100%;mix-blend-mode:plus-lighter;opacity:${B.crownA * 0.8}`)}"></div>`;
      html += `<div style="${abs(kx - (B.foamW * th) / 2, ty, B.foamW * th, B.foamH * th, `background:radial-gradient(ellipse at 50% 0%,rgba(255,240,200,0.8),transparent 70%);mix-blend-mode:plus-lighter;opacity:${B.foamA * 0.6}`)}"></div>`;
    }
  }
  return html;
}
const crown = texUrl("uf-fx2-foam");

const tints = XP.TINTS, C = XP.COLORS;
const label = (x, y, t) => `<div style="${abs(x, y, 150, 12, "font:" + 7 * Z + "px Marcellus;color:#e6cc99")}">${t}</div>`;
const W = 760, H = 150;
let body = "";
const rows = [
  { t: "normal (violett)", tint: tints.normal, fill: 0.4 },
  { t: "ausgeruht (Ruhe-Abschnitt)", tint: tints.rested, fill: 0.4, reserve: { to: 0.7, color: C.rested } },
  { t: "Stufenaufstieg", tint: tints.gold, fill: 1, levelup: true },
];
rows.forEach((r, i) => {
  const by = 14 + i * 30;
  body += label(8, by - 1, r.t);
  body += xpTube({ bx: 180, by, bw: 565, bh: 11, tint: r.tint, fill: r.fill, reserve: r.reserve, levelup: r.levelup });
});
body += label(8, 107, "Forever 1189 x 14 (halbe Groesse)");
body += `<div style="${abs(180, 100, 1189, 30, "transform:scale(0.475);transform-origin:0 0")}">${xpTube({ bx: 0, by: 4, bw: 1189, bh: 14, tint: tints.rested, fill: 0.55, reserve: { to: 0.8, color: C.rested } })}</div>`;
renderHtml(htmlOf({ W, H, body }), out, W * Z, H * Z);
console.log("Vorschau: " + out);
