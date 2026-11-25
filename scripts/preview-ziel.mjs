// Sichtvorschau des Ziel-Portraets Variante A (modules/UnitFrames/Deco.lua) aus den erzeugten Texturen, vor dem Spieltest:
//   node scripts/preview-ziel.mjs [--out docs/unitframe-src/vorschau-ziel.png] [--zoom 3]
// Vier Ziele wie im Entwurf entwurf-ziel-v1.jpg: Elite (Gold-Drache), Rar (Silber), Rar-Elite (Silber-Gold), Boss (Kamm,
// Stufe ?? mit Totenkopf). Je Ziel: Roehren (auf die Fenster der Rohraufnahmen gerueckt, enden im Sockel), Ring mit Aufnahmen
// (uf-ring-aufnahme; mit --ohne-aufnahme der schlichte uf-ring, Roehren enden im Ringband), Zier in zwei Lagen (hinten unter dem
// Ring, vorn darueber), Raidmarker oben (Stern), Quest-Symbol (Schwerter wie an den Plaketten), Stufen-Plakette mit Stein,
// eine Reihe Auren-Fassungen unter den Roehren. Lagen und Masse aus dem Lua-Code (Test-VM). Portraet: Ausschnitt aus dem
// Entwurf entwurf-rahmen-v1.jpg (nur Vorschau), Aura-Symbole: farbige Platzhalter.
import { readFileSync } from "node:fs";
import path from "node:path";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";
import { tube, setZoom, htmlOf, SKIN as SK, TINTS as TN, LIQ as L, abs, px, rgb, pngUrl, renderHtml } from "./preview-unitframe.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", "docs/unitframe-src/vorschau-ziel.png"));
const Z = Number(opt("--zoom", 3));
setZoom(Z);
const MEDIA = path.join(ROOT, "addon", "LucidVials", "Media");

function readTga(name) {
  const b = readFileSync(path.join(MEDIA, name + ".tga")), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    rgba[i * 4] = b[18 + i * 4 + 2]; rgba[i * 4 + 1] = b[18 + i * 4 + 1]; rgba[i * 4 + 2] = b[18 + i * 4]; rgba[i * 4 + 3] = b[18 + i * 4 + 3];
  }
  return { w, h, rgba };
}
const cache = new Map();
const url = (name, tint) => {
  const key = name + (tint ? tint.join(",") : "");
  if (!cache.has(key)) {
    const img = readTga(name);
    if (tint) for (let i = 0; i < img.w * img.h; i++) for (let k = 0; k < 3; k++) img.rgba[i * 4 + k] = Math.round(img.rgba[i * 4 + k] * tint[k]);
    cache.set(key, pngUrl(img));
  }
  return cache.get(key);
};
const img = (name, x, y, w, h, tint) => `<div style="${abs(x, y, w, h, `background:url(${url(name, tint)});background-size:100% 100%`)}"></div>`;

const vm = createVm();
const D = vm.lua("return NS.UnitFrameDeco");
const G = D.GEO, R = D.RING, LT = D.LAYOUT, SO = vm.lua("return NS.UnitFrameSkin.SOCKET");
const SOCKET_ON = !args.includes("--ohne-aufnahme") && SO.ids.target;
const AURA_SIZE = vm.lua("return NS.UnitFrameSkin.AURA_SIZE.default");
const draft = "data:image/jpeg;base64," + readFileSync(path.join(ROOT, "docs", "unitframe-src", "entwurf-rahmen-v1.jpg")).toString("base64");
const boar = [1760, 1479, 178];
const AURA_COLORS = [[0.95, 0.55, 0.15], [0.25, 0.55, 0.95], [0.85, 0.2, 0.2], [0.3, 0.8, 0.35], [0.6, 0.15, 0.15]];

/** Roehrenende wie Deco.lua tubeEnd (gespiegelt: Ring rechts der Roehre); gerade Kante im Ringband */
function tubeGeom(kind, h, ycTube, pcx, size) {
  const U = L.UF_FRAME, total = h + Math.max(U.extraMin, h * U.extraRel);
  const half = size / 2, rIn = half * R.inner, rOut = half * R.outer;
  const y0 = ycTube - total / 2, y1 = ycTube + total / 2;
  const yMin = y0 <= 0 && y1 >= 0 ? 0 : Math.min(Math.abs(y0), Math.abs(y1)), yMax = Math.max(Math.abs(y0), Math.abs(y1));
  const lo = Math.sqrt(Math.max(0, rIn * rIn - yMin * yMin)) + D.ENDS_INSET * half;
  const hi = Math.sqrt(Math.max(0, rOut * rOut - yMax * yMax));
  const dEnd = lo <= hi ? (lo + hi) / 2 : lo, dOut = Math.sqrt(rOut * rOut - ycTube * ycTube);
  return { right: pcx - dEnd, dOut };
}

/** Roehre in der Rohraufnahme wie Deco.lua socketEnd: Rahmenmitte auf die Fenstermitte (Bildschirm-y nach unten, zur
 *  Ringmitte), Ende endX im Sockel; null = zu weit neben dem Fenster (dann schlichter Ring) */
function socketGeom(kind, yc, pcx, size) {
  const W = G.socket[kind], half = size / 2, want = -((W.top + W.bot) / 2) * half;
  if (Math.abs(want - yc) > SO.maxDy * half) return null;
  return { yc: want, right: pcx + W.endX * half, dy: yc - want };
}

function target({ ox, oy, kind, skull, level, name }) {
  const S = SK.SPEC.target, pw = S.portraitSize, size = Math.floor(pw * SK.RING_SCALE + 0.5);
  // Roehrenlage wie im Spiel (ist-ziel-v2.png): Mitte der Lebensroehre etwa 1 px unter der Ringmitte
  const pcx = ox + 150, pcy = oy + 60, bx = ox + 10, hh = 20, ph = 10, by = pcy - 9;
  let html = "";
  // Hinterlage der Zier (unter allem Rahmenwerk des Rings)
  const k = (size / 2) * R.inner / G.rin;
  if (kind) {
    const g = G[kind];
    html += img(`uf-ziel-${kind}`, pcx - g.cx * G.backW * k, pcy - g.cy * G.backH * k, G.backW * k, G.backH * k);
  }
  // Portraet
  const [sx, sy, sr] = boar, kk = pw / (2 * sr);
  html += `<div style="${abs(pcx - pw / 2, pcy - pw / 2, pw, pw, `border-radius:50%;background:url(${draft});background-size:${px(2048 * kk)} ${px(2048 * kk)};background-position:${px(-(sx - sr) * kk)} ${px(-(sy - sr) * kk)}`)}"></div>`;
  // Roehren: auf die Fenster der Aufnahmen gerueckt und im Sockel endend (beide passen) - sonst aussen am Ring
  const tubes = [["power", by + hh, ph, { tex: "mono", color: [1, 0.06, 0.06] }, 0.3, null],
    ["health", by, hh, TN.hostile, 0.45, 0.62]].map(([kd, y, h, tint, fill, trail]) => {
    const F = L.UF_FRAMES[kd], U = L.UF_FRAME, total = h + Math.max(U.extraMin, h * U.extraRel);
    const yc = y + h / 2 - (F.dy || 0) * total - pcy;
    return { kd, y, h, tint, fill, trail, F, total, yc, s: SOCKET_ON ? socketGeom(kd, yc, pcx, size) : null };
  });
  const socket = tubes.every((t) => t.s);
  for (const t of tubes) {
    const y = socket ? t.y - t.s.dy : t.y, right = socket ? t.s.right : tubeGeom(t.kd, t.h, t.yc, pcx, size).right;
    if (socket && !shifts.has(t.kd)) shifts.set(t.kd, t.s.dy);
    html += tube({ kind: t.kd, x: bx, y, w: right - bx, h: t.h, mirror: true, tint: t.tint, fill: t.fill, trail: t.trail, open: "right" }).html;
  }
  // Ring (mit Aufnahmen: deckungsgleicher Ringkreis, uf-ring bleibt unsichtbar als Anker), Vorderlage der Zier
  if (socket) {
    const [x, y, s] = vm.lua(`return { NS.UnitFrameDeco.SocketPlace(${size}, false) }`);
    html += img("uf-ring-aufnahme", pcx + x - s / 2, pcy - y - s / 2, s, s);
  } else html += img("uf-ring", pcx - size / 2, pcy - size / 2, size, size);
  if (kind) html += img(`uf-ziel-${kind}-front`, pcx - (G.front * k) / 2, pcy - (G.front * k) / 2, G.front * k, G.front * k);
  // Raidmarker oben (grosse Fassung), Quest-Symbol oben aussen (kleine Fassung)
  const rm = (size / 2) * (R.inner + R.outer) / 2;
  const at = (deg) => [pcx + Math.cos((deg * Math.PI) / 180) * rm, pcy - Math.sin((deg * Math.PI) / 180) * rm];
  const [mx, my] = at(LT.markerAngle), ms = size * LT.marker, mi = ms * G.marker.inner * LT.raidIcon;
  html += img("uf-ziel-marker", mx - ms / 2, my - ms / 2, ms, ms);
  const raid = pngUrl(readTga("uf-ziel-gem")); // Platzhalter-Kontrast: Stern als goldener Stein
  html += `<div style="${abs(mx - mi / 2, my - mi / 2, mi, mi, `background:radial-gradient(circle,#ffe680 0 35%,#d9a520 36% 55%,transparent 56%)`)}"></div>`;
  void raid;
  const [qx, qy] = at(LT.questAngle), qs = size * LT.quest, qi = qs * LT.questIcon;
  html += img("uf-ziel-marker-small", qx - qs / 2, qy - qs / 2, qs, qs);
  html += img("np-obj-slay", qx - qi / 2, qy - qi / 2, qi, qi);
  // Stufen-Plakette mit Stein
  const ps = Math.floor(pw * SK.PLATE.badge + 0.5), ins = Math.floor(pw * SK.PLATE.inset + 0.5);
  const plx = pcx + pw / 2 - ins - ps / 2, ply = pcy + pw / 2 - ins - ps / 2, P = G.level;
  html += img("uf-ziel-level", plx, ply, ps, ps);
  const gs = ps * LT.gem;
  html += img("uf-ziel-gem", plx + P.gx * ps - gs / 2, ply + P.gy * ps - gs / 2, gs, gs, skull ? [1, 0.15, 0.1] : [1, 0.55, 0.25]);
  const N = SK.NAME;
  if (skull) {
    const ks = ps * LT.skull;
    html += img("np-skull", plx + P.cx * ps - ks / 2, ply + P.cy * ps - ks / 2, ks, ks);
  } else {
    const d = 2 * P.r * ps;
    html += `<div style="${abs(plx + P.cx * ps - d / 2, ply + P.cy * ps - d / 2, d, d, `display:flex;align-items:center;justify-content:center;font:${px(Math.max(7, Math.round(ps * LT.levelFont)))} Marcellus;color:${rgb(N.color)};text-shadow:${px(1)} ${px(1)} 0 ${rgb(N.shadow, N.shadow[3])}`)}">${level}</div>`;
  }
  // Auren: eine Reihe Schwaechungen unter den Roehren
  // Symbolgroesse = Profil-Standard (Skin.AURA_SIZE), Abstaende wachsen mit wie Deco.lua auraMetrics
  const A = D.AURA, as = AURA_SIZE, gap = Math.max(1, Math.floor(A.gap * as / A.refSize + 0.5));
  const ay = by + hh + ph + 6 + A.top;
  AURA_COLORS.forEach((c, i) => {
    const x = bx + i * (as + gap), inset = as * (1 - G.aura.inner * A.iconFill) / 2;
    html += `<div style="${abs(x + inset, ay + inset, as - 2 * inset, as - 2 * inset, `border-radius:50%;background:radial-gradient(circle at 35% 30%,${rgb(c.map((v) => Math.min(1, v + 0.35)))},${rgb(c)} 55%,${rgb(c.map((v) => v * 0.35))})`)}"></div>`;
    html += img("uf-ziel-aura", x, ay, as, as);
  });
  // Name
  html += `<div style="font:${px(S.nameSize)} Marcellus;color:${rgb(N.color)};text-shadow:${px(1)} ${px(1)} 0 ${rgb(N.shadow, N.shadow[3])};white-space:nowrap;position:absolute;top:${px(by - 20)};right:calc(100% - ${px(pcx - size / 2 - 4)})">${name}</div>`;
  return html;
}

const shifts = new Map();
const W = 420, H = 300;
const body = [
  target({ ox: 0, oy: 20, kind: "elite", level: 30, name: "Schnappkiefer" }),
  target({ ox: 210, oy: 20, kind: "rare", level: 30, name: "Schnappkiefer" }),
  target({ ox: 0, oy: 165, kind: "rareelite", level: 30, name: "Schnappkiefer" }),
  target({ ox: 210, oy: 165, kind: "boss", skull: true, level: "??", name: "Schnappkiefer" }),
].join("\n");
renderHtml(htmlOf({ W, H, body }), out, W * Z, H * Z);
console.log("Vorschau: " + out + (shifts.size ? "  Roehren gerueckt (UI, + = nach oben): "
  + [...shifts].map(([k, v]) => `${k} ${v.toFixed(2)}`).join(", ") : "  (schlichter Ring)"));
