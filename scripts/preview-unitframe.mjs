// Sichtvorschau der Einheitenrahmen (Delta "Fluessiges Leben") aus den erzeugten Texturen, vor dem Spieltest:
//   node scripts/preview-unitframe.mjs [--out docs/unitframe-src/vorschau-einbau.png] [--zoom 4]
//   Kolben-Kammer: node scripts/preview-kolben.mjs (Zustaende aus der Lua-Wellensimulation, PNG + GIF)
//   node scripts/preview-unitframe.mjs --glut    (Glut bei Verlust 80 -> 45 % ueber 1 s -> docs/unitframe-src/vorschau-glut.png)
//   node scripts/preview-unitframe.mjs --kante   (Zustaende der Fluessigkeitskante -> docs/unitframe-src/vorschau-kante.png)
// Baut Spieler, Ziel (gespiegelt) und Ziel des Ziels wie modules/UnitFrames/Skin.lua + Liquid.lua in HTML nach (Konstanten
// direkt aus dem Lua-Code ueber die Test-VM): Kapselrahmen 3-Slice um die Glasoeffnung, Maske, Fluessigkeit (Lage A + B,
// getoent), Blaeschen, Ruhe-Kante an der Fuellkante, Glasglanz, Schadensspur mit Glut, Ring, Stufen-Plaettchen, Name in
// Marcellus. Die Portraets sind Ausschnitte aus dem Entwurf (nur Vorschau). Standbild t = 0; Rendern per Headless-Chrome.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", args.includes("--glut") ? "docs/unitframe-src/vorschau-glut.png"
  : args.includes("--kante") ? "docs/unitframe-src/vorschau-kante.png" : "docs/unitframe-src/vorschau-einbau.png"));
let Z = Number(opt("--zoom", 4)); // UI-Einheit -> Bildpunkte (fuer den nativen Detail-Ausschnitt kurz 1)
const MEDIA = path.join(ROOT, "addon", "LucidVials", "Media");
const CHROME = [process.env.CHROME, "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].filter(Boolean);

function chunk(type, data) {
  const t = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}
function readTga(name) {
  const b = readFileSync(path.join(MEDIA, name + ".tga")), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    rgba[i * 4] = b[18 + i * 4 + 2]; rgba[i * 4 + 1] = b[18 + i * 4 + 1]; rgba[i * 4 + 2] = b[18 + i * 4]; rgba[i * 4 + 3] = b[18 + i * 4 + 3];
  }
  return { w, h, rgba };
}
function pngUrl({ w, h, rgba }) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return "data:image/png;base64," + Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]).toString("base64");
}
const cache = new Map();
const url = (name) => { if (!cache.has(name)) cache.set(name, pngUrl(readTga(name))); return cache.get(name); };
/** Textur mit Vertexfarbe (Multiplikation wie im Spiel) */
function tinted(name, c) {
  const key = name + c.join(",");
  if (!cache.has(key)) {
    const img = readTga(name);
    for (let i = 0; i < img.w * img.h; i++) for (let k = 0; k < 3; k++) img.rgba[i * 4 + k] = Math.round(img.rgba[i * 4 + k] * Math.min(1, c[k]));
    cache.set(key, pngUrl(img));
  }
  return cache.get(key);
}

const vm = createVm();
const L = vm.lua("return NS.Liquid");
const SK = vm.lua("return NS.UnitFrameSkin");
const A = vm.lua("return NS.Style.ANIM");
const font = pathToFileURL(path.join(ROOT, "addon", "LucidVials", "Fonts", "Marcellus-Regular.ttf")).href;
const draft = "data:image/jpeg;base64," + readFileSync(path.join(ROOT, "docs", "unitframe-src", "entwurf-rahmen-v1.jpg")).toString("base64");
const rgb = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
const px = (v) => `${(v * Z).toFixed(2)}px`;
const abs = (x, y, w, h, extra = "") => `position:absolute;left:${px(x)};top:${px(y)};width:${px(w)};height:${px(h)};${extra}`;

/** Ausschnitt [u0,u1] x [v0,v1] einer Textur auf eine Box der Breite w, Hoehe h (UI-Einheiten) */
const slice = (u0, u1, v0, v1, w, h) => {
  const fw = w / (u1 - u0), fh = h / (v1 - v0);
  return `background-size:${px(fw)} ${px(fh)};background-position:${px(-u0 * fw)} ${px(-v0 * fh)};background-repeat:repeat`;
};

/** eine Roehre im Kapselrahmen; region = Blizzards Balken (x, y, w, h); fill/trail 0..1 */
export function tube({ kind, x, y, w, h, mirror, tint, fill, trail = null, trailAlpha = null, phase = 0.3, slosh = { tilt: 0, wave: 0 },
  style = "edge", pstate = null, maskName = null, dy = null, reserve = null, open = null }) {
  const piston = style === "piston", PP = L.PISTON;
  const F = L.UF_FRAMES[kind], U = L.UF_FRAME;
  const total = h + Math.max(U.extraMin, h * U.extraRel), s = total / F.srcH;
  const th = (F.openB - F.openT) * s;
  const ty = y + h / 2 - (dy ?? F.dy ?? 0) * total - th / 2; // WoW: +dy nach oben (opts.dy wie Liquid.Layout)
  const ratio = w / th;
  // open = "left"/"right": ringseitig offenes Ende wie Liquid.SetOpenEnd (Maske *-openl/-openr, ohne Endkappe/Glanz-Rundung)
  const autoMask = (ratio >= L.MASK_THIN_RATIO ? "uf-mask-thin" : "uf-mask-capsule") + (open ? "-open" + open[0] : "");
  const mask = `-webkit-mask-image:url(${url(maskName ?? autoMask)});-webkit-mask-size:100% 100%`;
  let html = `<div style="${abs(x, ty, w, th, "overflow:visible")}">`;
  // leerer Teil
  const T = L.TUBE;
  const backBg = piston ? `url(${url("uf-glassback")});background-size:100% 100%`
    : `linear-gradient(${rgb(T.backTop, T.backTop[3])},${rgb(T.backBottom, T.backBottom[3])})`;
  html += `<div style="${abs(0, 0, w, th, `background:${backBg};${mask}`)}"></div>`;
  // Reserve-Lage (Liquid.AddReserve, XP-Ruhebonus): Koerper abgedunkelt ab dem Luftspalt, Lichtlinie; Clip bis reserve.to
  if (reserve) {
    const R = L.RESERVE, rc = reserve.color, k = PP.bodyBright * R.dim, wk = R.glowWhite;
    const lc2 = rc.map((v) => v + (1 - v) * wk);
    html += `<div style="${abs(0, 0, w, th, mask)}"><div style="${abs(0, 0, w * reserve.to, th, "overflow:hidden")}">
      <div style="${abs(0, PP.gap * th, w, th - PP.gap * th, `background-image:url(${tinted("uf-body", rc.map((v) => v * k))});${slice(0, w / (PP.bodyTile * th), 0.2, 0.996, w, th - PP.gap * th)};opacity:${R.alpha}`)}"></div>
      <div style="${abs(0, -PP.margin * th, w, (1 + 2 * PP.margin) * th, `background:url(${tinted("uf-surfglow", lc2)});background-size:${px(PP.glowTile * th)} 100%;background-repeat:repeat-x;mix-blend-mode:plus-lighter;opacity:${R.glowAlpha}`)}"></div></div></div>`;
  }
  let glow = ""; // Glut liegt im Spiel ueber Fluessigkeit und Abdeckung (eigener Frame)
  // Spur: unsichtbare Fuellung, sichtbar nur die weiche Glut mit der Spitze am Spur-Ende
  if (trail !== null) {
    const tw = w * trail, E = L.EMBER, ew = E.length * th;
    // wie Liquid.lua: Clip ab dem Fuellungsende (weicher Einlauf fadeIn x Hoehe), Glut-Spitze am Spur-Ende
    const fx = w * fill + (piston ? PP.piston * th * 0.5 : 0), fin = (E.fadeIn * th) / Math.max(1e-6, w - fx);
    const ta = trailAlpha ?? L.TRAIL.alpha;
    glow = `<div style="${abs(0, 0, w, th, mask)}"><div style="${abs(fx, 0, Math.max(0, w - fx), th, `overflow:hidden;-webkit-mask-image:linear-gradient(90deg,transparent,#000 ${(Math.min(1, fin) * 100).toFixed(1)}%);opacity:${ta}`)}">
      <div style="${abs(tw - ew - fx, (th - th * E.height) / 2, ew, th * E.height, `background:url(${url("uf-ember")});background-size:100% 100%;mix-blend-mode:plus-lighter;opacity:${E.alpha}`)}"></div></div></div>`;
  }
  // Kante wie Liquid.lua applySlosh: Neigung dx (Oberkante +dx), Welle sx, Summe begrenzt
  const SU = L.SURFACE, EG = L.EDGE;
  let dx = (slosh.tilt + slosh.wave * SU.waveTilt) * th * SU.tiltScale, sx = slosh.wave * th * SU.surge;
  const lim = EG.maxShift * th, sum = Math.abs(dx) + Math.abs(sx);
  if (sum > lim) { dx *= lim / sum; sx *= lim / sum; }
  const skew = `transform:translateX(${px(sx)}) skewX(${Math.atan((-2 * dx) / th)}rad)`;
  const ew2 = 2 * EG.half * th;
  // Fluessigkeit (Clip bis Fuellungsende + reach), Lagen ueber die ganze Roehre, darueber die Abdeckung in Leerglas-Farbe
  const fw = w * fill;
  const c = tint.color, base = tint.base || c.map((v) => v * 0.55);
  const flowTex = tint.tex === "color" ? "np-liquid" : "uf-fill";
  const lq = tint.tex === "color" ? base.map((v) => v * PP.colorFromBase) : c; // sichtbare Fluessigkeitsfarbe wie Liquid.SetTint
  const lqb = lq.map((v) => v ** PP.bodySat); // Koerper satter (Liquid.SetTint liqR/G/B)
  const ua = phase, ub = phase + 0.5;
  const bright = A.aBright;
  const back = `linear-gradient(${rgb(T.backTop)},${rgb(T.backBottom)})`;
  html += `<div style="${abs(0, 0, w, th, mask)}"><div style="${abs(0, 0, fw + (piston ? 0 : EG.reach * th), th, "overflow:hidden")}">
    <div style="${abs(0, 0, w, th, `background:url(${tinted("np-fill", base)});background-size:100% 100%`)}"></div>
    ${piston ? bodyLayers() : `<div style="${abs(0, 0, w, th, `background-image:url(${tinted(flowTex, c.map((v) => v * bright))});${slice(ua, ua + A.repeatA, A.vA, A.vA + A.vSpan, w, th)};opacity:${A.aAlpha}`)}"></div>
    <div style="${abs(0, 0, w, th, `background-image:url(${tinted(flowTex, c)});${slice(ub, ub + A.repeatB, A.vB, A.vB + A.vSpan, w, th)};opacity:${A.bBase};mix-blend-mode:plus-lighter;transform:scaleX(-1)`)}"></div>`}
    <div style="${abs(0, 0, w, th, `background-image:url(${url("uf-bubbles")});${slice(0.1, 0.1 + (w * L.BUBBLES.vSpan) / (th * L.BUBBLES.aspect), 0.2, 0.2 + L.BUBBLES.vSpan, w, th)};opacity:${L.BUBBLES.alpha};mix-blend-mode:plus-lighter`)}"></div>
    ${piston ? pistonAir() : `<div style="${abs(0, 0, w, th, `-webkit-mask-image:url(${url("uf-mask-endright")});-webkit-mask-size:100% 100%`)}">
      <div style="${abs(fw - ew2 / 2, 0, ew2, th, `background:${back};-webkit-mask-image:url(${url("uf-edge-cover")});-webkit-mask-size:100% 100%;${skew}`)}"></div></div>`}
  </div></div>`;
  /** Kolben-Kammer: Koerper wie Liquid.lua stepBody (t = 0, Phase phase) */
  function bodyLayers() {
    const tw = w / (th * PP.bodyTile), ua0 = phase + PP.bodySway * Math.sin(phase * 6.28), ub0 = phase * 0.37 + 0.5;
    const a2 = PP.body2Alpha + PP.body2Amp * Math.sin(phase * 6.28 + 1.9);
    return `<div style="${abs(0, 0, w, th, `background-image:url(${tinted("uf-body", lqb.map((v) => v * PP.bodyBright))});${slice(ua0, ua0 + tw, 0.004, 0.996, w, th)};opacity:${PP.bodyAlpha}`)}"></div>
    <div style="${abs(0, 0, w, th, `background-image:url(${tinted("uf-body", lqb)});${slice(ub0, ub0 + tw, 0.004, 0.996, w, th)};opacity:${a2};mix-blend-mode:plus-lighter;transform:scaleX(-1)`)}"></div>`;
  }
  /** Kolben-Kammer wie Liquid.lua stepPiston: Scheiben ueber die Roehrenbreite, je senkrecht geschert (Hoehen der
   *  Scheibengrenzen hk, WoW oben positiv), Licht mit Schaum, Naessefilm, Kaustik, Tropfen. pstate = Zustand aus der
   *  Lua-VM (scripts/preview-kolben.mjs); ohne pstate die Ruhelage der Neigung (gerade schiefe Linie). */
  function pistonAir() {
    let st = pstate;
    if (!st) {
      const len = fw < 1 ? w * PP.fallbackLen : fw, nsl = Math.round(w / PP.slicePx);
      const s0 = Math.max(-PP.maxSlope, Math.min(PP.maxSlope, (slosh.tilt + slosh.wave * SU.waveTilt) * PP.slope * len / th));
      const hk = [];
      for (let k = 0; k <= nsl; k++) hk.push(Math.max(-PP.down * th, Math.min(PP.up * th, s0 * (Math.min(1, (k * w) / nsl / len) - 0.5) * th)));
      st = { nsl, hk, wk: hk, fk: hk.map(() => 0), drops: [], caustic: PP.caustic, y1: hk[nsl] };
    }
    const nsl = st.nsl, sw = w / nsl;
    const top = -PP.margin * th, full = (1 + 2 * PP.margin) * th;
    const lc = lq.map((v) => v + (1 - v) * PP.glowWhite);
    const quad = (x0, wd, dl, dr, bg, extra, tile = 0) => `<div style="${abs(x0, top, wd + (extra ? 0 : 0.02), full,
      `background:url(${bg});${tile ? `background-size:${px(tile)} 100%;background-position:${px(-x0)} 0;background-repeat:repeat-x` : "background-size:100% 100%"};transform-origin:0 0;transform:translateY(${px(-dl)}) skewY(${Math.atan(-(dr - dl) / Math.max(1e-6, wd))}rad);${extra}`)}"></div>`;
    // Verlauf je Scheibe (wie SetGradient im Spiel): Maske nur ueber der Scheibe [x0, x0 + sw]
    const grad = (a0, a1, x0) => `-webkit-mask-image:linear-gradient(90deg,rgba(0,0,0,${a0.toFixed(3)}),rgba(0,0,0,${a1.toFixed(3)}));-webkit-mask-size:${px(sw)} 100%;-webkit-mask-position:${px(x0)} 0;-webkit-mask-repeat:no-repeat`;
    let o = `<div style="${abs(0, 0, w, th, `background-image:url(${url("uf-caustic")});background-size:${px(PP.causticTile * th * 2)} ${px(PP.causticTile * th)};mix-blend-mode:plus-lighter;opacity:${st.caustic}`)}"></div>`;
    for (let i = 1; i <= nsl; i++) o += quad((i - 1) * sw, sw, st.hk[i - 1], st.hk[i], url("uf-air"), "");
    for (let i = 1; i <= nsl; i++) {
      const wa0 = PP.wetAlpha * Math.min(1, Math.max(0, (st.wk[i - 1] - st.hk[i - 1]) / (PP.wetBand * th)));
      const wa1 = PP.wetAlpha * Math.min(1, Math.max(0, (st.wk[i] - st.hk[i]) / (PP.wetBand * th)));
      if (wa0 + wa1 > 0.01) o += `<div style="${grad(wa0, wa1, (i - 1) * sw)};position:absolute;left:0;top:0;width:100%;height:100%">${quad((i - 1) * sw, sw, st.wk[i - 1], st.wk[i], tinted("uf-wet", lc), "mix-blend-mode:plus-lighter", PP.wetTile * th)}</div>`;
    }
    const gl = tinted("uf-surfglow", lc), wh = tinted("uf-surfglow", [1, 1, 1]);
    for (let i = 1; i <= nsl; i++) {
      const f0 = st.fk[i - 1], f1 = st.fk[i];
      o += quad((i - 1) * sw, sw, st.hk[i - 1], st.hk[i], gl, `mix-blend-mode:plus-lighter;opacity:${PP.glowAlpha}`, PP.glowTile * th);
      if (f0 + f1 > 0.02) o += `<div style="${grad(f0, f1, (i - 1) * sw)};position:absolute;left:0;top:0;width:100%;height:100%;mix-blend-mode:plus-lighter">${quad((i - 1) * sw, sw, st.hk[i - 1], st.hk[i], wh, "", PP.glowTile * th)}</div>`;
    }
    const dc = tinted("uf-drop", lc), NC = PP.dropCells;
    for (const d of st.drops) {
      const ds = d.size || PP.dropSize * th, cell = d.cell || 1; // Atlas-Zelle wie Liquid.lua splash
      o += `<div style="${abs(d.x - ds / 2, -d.y - ds / 2, ds, ds, `background-image:url(${dc});${slice((cell - 1) / NC, cell / NC, 0, 1, ds, ds)};mix-blend-mode:plus-lighter;opacity:${d.a}`)}"></div>`;
    }
    return o;
  }
  html += glow;
  // Randlicht auf derselben Linie (beidseitige Endblende), innerer Schatten
  const k = SU.rimMix, rc = c.map((v) => v + (1 - v) * k);
  html += `<div style="${abs(0, 0, w, th, mask)}"><div style="${abs(0, 0, w, th, `-webkit-mask-image:url(${url("uf-mask-endfade")});-webkit-mask-size:100% 100%`)}">
      ${piston ? "" : `<div style="${abs(fw - ew2 / 2, 0, ew2, th, `background:url(${tinted("uf-edge-rim", rc)});background-size:100% 100%;mix-blend-mode:plus-lighter;opacity:${SU.alphaBase};${skew}`)}"></div>`}</div>
      ${piston ? `<div style="${abs(fw - (PP.piston * th) / 2, 0, PP.piston * th, th, `background:url(${url("uf-piston")});background-size:100% 100%`)}"></div>` : ""}
    <div style="${abs(0, 0, w, th, `background:#000;-webkit-mask-image:url(${url("np-inset")});-webkit-mask-size:100% 100%;opacity:${T.insetAlpha}`)}"></div></div>`;
  // Glasglanz 3-Slice
  const G = L.GLASS, gc = G.cap * G.aspect * th;
  const [l0, l1] = open === "left" ? [G.cap, 2 * G.cap] : [0, G.cap], [r0, r1] = open === "right" ? [1 - 2 * G.cap, 1 - G.cap] : [1 - G.cap, 1];
  for (const [gx, gw, u0, u1] of [[0, gc, l0, l1], [gc, w - 2 * gc, G.cap, 1 - G.cap], [w - gc, gc, r0, r1]]) {
    html += `<div style="${abs(gx, 0, gw, th, `background-image:url(${url("uf-glass")});${slice(u0, u1, 0, 1, gw, th)};opacity:${G.alpha}`)}"></div>`;
  }
  // Kapselrahmen 3-Slice (ungespiegelt aufgebaut, beim Ziel um die Roehrenmitte gespiegelt)
  const uL = F.sliceL / F.srcW, uR = F.sliceR / F.srcW;
  const fx0 = -F.openL * s, fy0 = -F.openT * s, fH = F.srcH * s, cL = F.sliceL * s, cR = (F.srcW - F.sliceR) * s;
  const fx1 = w + (F.srcW - F.openR) * s;
  let frame = "";
  const openU = open && ((open === "right") !== !!mirror ? "r" : "l"); // offene Seite im ungespiegelten Aufbau
  const slices = openU === "l" ? [[0, fx1 - cR, uL, uR], [fx1 - cR, cR, uR, 1]]
    : openU === "r" ? [[fx0, cL, 0, uL], [fx0 + cL, w - (fx0 + cL), uL, uR]]
      : [[fx0, cL, 0, uL], [fx0 + cL, fx1 - cR - (fx0 + cL), uL, uR], [fx1 - cR, cR, uR, 1]];
  for (const [fx, fwid, u0, u1] of slices) {
    frame += `<div style="${abs(fx, fy0, fwid, fH, `background-image:url(${url("uf-frame-" + kind)});${slice(u0, u1, 0, 1, fwid, fH)}`)}"></div>`;
  }
  html += `<div style="${abs(0, 0, w, th, mirror ? "transform:scaleX(-1)" : "")}">${frame}</div>`;
  html += "</div>";
  return { html, top: ty - F.openT * s };
}

/** Rohraufnahmen wie Deco.lua socketEnd (nur Spieler, Ring links): Roehren auf die Fenstermitte gerueckt (dy, Bildschirm-y
 *  nach unten), linkes Ende endX im Sockel; null = eine Roehre liegt zu weit neben ihrem Fenster (schlichter Ring) */
function socketTubes(pcx, pcy, rs, bars) {
  const D = vm.lua("return NS.UnitFrameDeco"), SO = SK.SOCKET, half = rs / 2;
  const out = bars.map(([kind, y, h]) => {
    const F = L.UF_FRAMES[kind], U = L.UF_FRAME, total = h + Math.max(U.extraMin, h * U.extraRel);
    const W = D.GEO.socket[kind], yc = y + h / 2 - (F.dy || 0) * total - pcy, want = -((W.top + W.bot) / 2) * half;
    return Math.abs(want - yc) > SO.maxDy * half ? null : { dy: yc - want, left: pcx - W.endX * half };
  });
  return out.every(Boolean) ? out : null;
}

/** ein Rahmen: Portraet bei (pcx, pcy), Balken ab bx; socket = Ring mit Rohraufnahmen (Spieler) */
function unitFrame({ id, pcx, pcy, pw, bx, by, hw, hh, ph, mirror, tint, power, fill, pfill, trail, name, level, plate, nameSize, portrait,
  socket = false }) {
  let html = "";
  // Portraet (Ausschnitt aus dem Entwurf, rund)
  const [sx, sy, sr] = portrait, k = pw / (2 * sr);
  html += `<div style="${abs(pcx - pw / 2, pcy - pw / 2, pw, pw, `border-radius:50%;background:url(${draft});background-size:${px(2048 * k)} ${px(2048 * k)};background-position:${px(-(sx - sr) * k)} ${px(-(sy - sr) * k)}`)}"></div>`;
  const rs = Math.floor(pw * SK.RING_SCALE + 0.5);
  const so = socket ? socketTubes(pcx, pcy, rs, [["power", by + hh, ph], ["health", by, hh]]) : null;
  const end = (i) => (so ? { x: so[i].left, w: bx + hw - so[i].left, y: -so[i].dy, open: "left" } : { x: bx, w: hw, y: 0, open: null });
  const ep = end(0), eh = end(1);
  const pwr = tube({ kind: "power", x: ep.x, y: by + hh + ep.y, w: ep.w, h: ph, mirror, tint: power, fill: pfill, phase: 0.6, open: ep.open });
  const hp = tube({ kind: "health", x: eh.x, y: by + eh.y, w: eh.w, h: hh, mirror, tint, fill, trail, open: eh.open });
  html += pwr.html + hp.html;
  // Ring (mit Aufnahmen: gespiegelte uf-ring-aufnahme, Ringkreis deckungsgleich) + Plaettchen + Stufe
  if (so) {
    const [x, y, s] = vm.lua(`return { NS.UnitFrameDeco.SocketPlace(${rs}, true) }`);
    html += `<div style="${abs(pcx + x - s / 2, pcy - y - s / 2, s, s, `background:url(${url("uf-ring-aufnahme")});background-size:100% 100%;transform:scaleX(-1)`)}"></div>`;
  } else html += `<div style="${abs(pcx - rs / 2, pcy - rs / 2, rs, rs, `background:url(${url("uf-ring")});background-size:100% 100%`)}"></div>`;
  if (plate) {
    const P = SK.PLATE, ps = pw * P[plate], ins = pw * P.inset;
    const cx = mirror ? pcx + pw / 2 - ins : pcx - pw / 2 + ins, cy = pcy + pw / 2 - ins;
    html += `<div style="${abs(cx - ps / 2, cy - ps / 2, ps, ps, `background:url(${url(plate === "square" ? "uf-level-square" : "uf-level-round")});background-size:100% 100%;display:flex;align-items:center;justify-content:center;font:${px(Math.max(7, Math.round(ps * P.font)))} Marcellus;color:${rgb(SK.NAME.color)};text-shadow:${px(1)} ${px(1)} 0 ${rgb(SK.NAME.shadow, SK.NAME.shadow[3])}`)}">${level}</div>`;
  }
  // Name ueber der Lebensroehre
  const N = SK.NAME;
  const style = `font:${px(nameSize)} Marcellus;color:${rgb(N.color)};text-shadow:${px(1)} ${px(1)} 0 ${rgb(N.shadow, N.shadow[3])};white-space:nowrap;position:absolute;top:${px(hp.top - N.y - nameSize * 1.25)};`;
  html += mirror ? `<div style="${style}right:calc(100% - ${px(bx + hw - N.x)})">${name}</div>` : `<div style="${style}left:${px(bx + N.x)}">${name}</div>`;
  return `<div id="${id}">${html}</div>`;
}

const S = SK.SPEC, TN = SK.TINTS;
const mana = { tex: "mono", color: [0.05, 0.05, 1].map((v) => Math.min(1, v * 1.1 + 0.05)) };
const rage = { tex: "mono", color: [1, 0, 0].map((v) => Math.min(1, v * 1.1 + 0.05)) };
const dwarf = [350, 443, 201], boar = [1760, 1479, 178];
function framesPage() {
  const W = 236, H = 180;
  const body = [
  // Spieler: Balken wie im Spiel etwa 1 px unter der Portraetmitte (ist-forever-frames.jpg), Ring mit Rohraufnahmen
  unitFrame({ id: "player", pcx: 40, pcy: 42, pw: S.player.portraitSize, bx: 76, by: 33, hw: 124, hh: 20, ph: 10, mirror: false,
    tint: TN.player, power: mana, fill: 0.72, pfill: 0.95, name: "Lenu", level: 11, plate: "square", nameSize: S.player.nameSize, portrait: dwarf,
    socket: !!SK.SOCKET.ids.player }),
  unitFrame({ id: "target", pcx: 196, pcy: 112, pw: S.target.portraitSize, bx: 36, by: 96, hw: 124, hh: 20, ph: 10, mirror: true,
    tint: TN.hostile, power: rage, fill: 0.45, pfill: 0.3, trail: 0.78, name: "Alter Klippeneber", level: 7, plate: "round",
    nameSize: S.target.nameSize, portrait: boar }),
  unitFrame({ id: "tot", pcx: 160, pcy: 160, pw: S.tot.portraitSize * 0.6, bx: 178, by: 154, hw: 50, hh: 8, ph: 5, mirror: false,
    tint: TN.player, power: mana, fill: 0.85, pfill: 0.9, name: "Lenu", level: 11, plate: "round", nameSize: S.tot.nameSize * 0.8, portrait: dwarf }),
  ].join("\n");
  return { W, H, body };
}

/** Zustandsreihe der Fluessigkeitskante (--kante): Lebensroehre in Spielgroesse 124 x 20 */
function edgePage() {
  const rows = [
    ["Ruhe 60 %", { fill: 0.6 }],
    ["Neigung vor (Anlaufen)", { fill: 0.6, slosh: { tilt: -0.6, wave: 0 } }],
    ["Neigung zurück (Anhalten)", { fill: 0.6, slosh: { tilt: 0.6, wave: 0 } }],
    ["Welle (Sprung/Landung)", { fill: 0.6, slosh: { tilt: 0.1, wave: 0.8 } }],
    ["Schadensspur 45 % → 80 %", { fill: 0.45, trail: 0.8, tint: TN.hostile }],
    ["Ressource, Spur 30 % → 70 %", { kind: "power", h: 10, fill: 0.3, trail: 0.7, tint: rage }],
    ["100 % (läuft in die Kappe)", { fill: 1, slosh: { tilt: 0.4, wave: 0.3 } }],
    ["0 % (leer)", { fill: 0, slosh: { tilt: 0.4, wave: 0 } }],
  ];
  const W = 260, RH = 34;
  const body = rows.map(([label, o], r) => {
    const t = tube({ kind: o.kind || "health", x: 116, y: 8 + r * RH, w: 124, h: o.h || 20, mirror: false, tint: o.tint || TN.player,
      fill: o.fill, trail: o.trail ?? null, slosh: o.slosh || { tilt: 0, wave: 0 } });
    return t.html + `<div style="${abs(6, 12 + r * RH, 100, 14, `font:${px(8)} Marcellus;color:${rgb(SK.NAME.color)}`)}">${label}</div>`;
  }).join("\n");
  return { W, H: rows.length * RH + 8, body };
}

/** Glut-Sequenz (--glut): Verlust 80 -> 45 % ueber 1 s in 6 Bildern, Zeitverlauf wie Liquid.lua (Fluessigkeit gleitet
 *  ExponentialEaseOut tau ~0,063 s; Spur folgt TRAIL.delay s spaeter, haelt hold s, blendet in fade s aus) */
function glowPage() {
  const T = L.TRAIL, tau = 0.063, a = 0.8, b = 0.45;
  const glide = (dt) => (dt <= 0 ? a : b + (a - b) * Math.exp(-dt / tau));
  const rows = [0, 0.2, 0.4, 0.6, 0.8, 1.0].map((t) => {
    const fill = glide(t), trail = t < T.delay ? a : glide(t - T.delay);
    const age = t - T.delay - T.hold, alpha = age <= 0 ? T.alpha : Math.max(0, T.alpha * (1 - age / T.fade));
    return [`t = ${t.toFixed(1)} s  (${Math.round(fill * 100)} % / Spur ${Math.round(trail * 100)} %)`, { fill, trail, alpha }];
  });
  const W = 280, RH = 34;
  const body = rows.map(([label, o], r) => {
    const t = tube({ kind: "health", x: 136, y: 8 + r * RH, w: 124, h: 20, mirror: false, tint: TN.hostile, fill: o.fill,
      trail: o.trail, trailAlpha: o.alpha });
    return t.html + `<div style="${abs(6, 12 + r * RH, 120, 14, `font:${px(7.5)} Marcellus;color:${rgb(SK.NAME.color)}`)}">${label}</div>`;
  }).join("\n");
  return { W, H: rows.length * RH + 8, body };
}

const page = () => (args.includes("--glut") ? glowPage() : args.includes("--kante") ? edgePage() : framesPage());
const htmlOf = ({ W, H, body }) => `<!doctype html><html><head><meta charset="utf-8"><style>@font-face{font-family:Marcellus;src:url(${font})}
html,body{margin:0;width:${px(W)};height:${px(H)};overflow:hidden;background:radial-gradient(ellipse at 40% 30%,#22324f,#0b1220 75%)}</style></head>
<body>${body}</body></html>`;

export function setZoom(z) { Z = z; }
export { htmlOf, L as LIQ, SK as SKIN, TN as TINTS, abs, px, rgb, pngUrl, url as texUrl };

/** HTML -> PNG-Datei (Headless-Chrome), Groesse W x H Bildpunkte */
export function renderHtml(html, dest, W, H) {
  const dir = mkdtempSync(path.join(os.tmpdir(), "lucid-uf-shot-"));
  try {
    const file = path.join(dir, "p.html");
    writeFileSync(file, html);
    const browser = CHROME.find((p) => { try { readFileSync(p); return true; } catch { return false; } });
    if (!browser) throw new Error("kein Chrome/Edge gefunden (Umgebungsvariable CHROME setzen)");
    const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars",
      `--user-data-dir=${path.join(dir, "profile")}`, "--force-device-scale-factor=1", `--window-size=${Math.round(W)},${Math.round(H)}`,
      "--virtual-time-budget=3000", `--screenshot=${dest}`, pathToFileURL(file).href], { stdio: "ignore", timeout: 120000 });
    if (r.status !== 0) throw new Error("Rendern fehlgeschlagen");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function main() {
const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-uf-preview-"));
  /** HTML -> PNG-Datei (Headless-Chrome), Groesse W x H Bildpunkte */
  function shot(html, dest, W, H, name) {
    const file = path.join(tmp, name + ".html");
    writeFileSync(file, html);
    const browser = CHROME.find((p) => { try { readFileSync(p); return true; } catch { return false; } });
    if (!browser) throw new Error("kein Chrome/Edge gefunden (Umgebungsvariable CHROME setzen)");
    const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars",
      `--user-data-dir=${path.join(tmp, "profile-" + name)}`, "--force-device-scale-factor=1", `--window-size=${Math.round(W)},${Math.round(H)}`,
      "--virtual-time-budget=3000", `--screenshot=${dest}`, pathToFileURL(file).href], { stdio: "ignore", timeout: 90000 });
    if (r.status !== 0) throw new Error("Rendern fehlgeschlagen");
  }
  try {
    const main = page();
    shot(htmlOf(main), out, main.W * Z, main.H * Z, "main");
    console.log("Vorschau: " + out);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
