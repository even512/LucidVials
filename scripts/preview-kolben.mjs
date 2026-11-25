// Sichtvorschau der Kolben-Kammer aus der ECHTEN Lua-Wellensimulation (Liquid.lua stepPiston + LiquidWave.lua in der Test-VM):
//   node scripts/preview-kolben.mjs [--gif]
// Eine Zeitleiste speist die Anregung wie LiquidPhysics (ax, jolts/joltStrength/joltKind, Fuellbreite fuer den Kolben) und ruft
// Liquid.Step mit 60 Bildern/s. Zustaende (Scheibenhoehen, Naesse, Schaum, Tropfen, Kaustik) werden mit den erzeugten
// Texturen in HTML nachgebaut (scripts/preview-unitframe.mjs tube) und per Headless-Chrome gerendert:
//   docs/unitframe-src/vorschau-kolben.png  Ruhe, Anlaufen, Nachschwappen, Landung mit Spritzern, Treffer, Kolben faellt schnell;
//                                            darunter zwei Zustaende in nativer Groesse 3x (naechster Nachbar) gegen Treppen/Knicke
//   docs/unitframe-src/vorschau-vs-referenz.png  oben die Referenz (verkleinert), darunter Ruhe/Neigung/Welle in gleicher Groesse
//   docs/unitframe-src/vorschau-kolben.gif  (--gif) 3,2 s Anlaufen -> Stopp -> Landung, 15 Bilder/s
//   docs/unitframe-src/vorschau-kolben-lauf.gif  (--lauf) echte Bewegungsphysik: Anlaufen, 3 s Laufen, Stopp, Landung;
//                                            Leben + Mana nativ und 4x (naechster Nachbar) gegen Treppen/Naehte
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";
import { UNITFRAME_SETUP } from "../tests/helpers/unitframes-fake.mjs";
import { decodePng } from "./media-lib.mjs";
import { tube, setZoom, htmlOf, SKIN, TINTS, LIQ, abs, px, rgb, pngUrl, renderHtml } from "./preview-unitframe.mjs";

const OUT_PNG = path.join(ROOT, "docs", "unitframe-src", "vorschau-kolben.png");
const OUT_GIF = path.join(ROOT, "docs", "unitframe-src", "vorschau-kolben.gif");
const OUT_LAUF = path.join(ROOT, "docs", "unitframe-src", "vorschau-kolben-lauf.gif");
const REF = path.join(ROOT, "docs", "unitframe-src", "referenz-kolben-fluessigkeit.jpg");
const OUT_CMP = path.join(ROOT, "docs", "unitframe-src", "vorschau-vs-referenz.png");
const FPS = 60;

// --- Simulation in der VM ------------------------------------------------------------------------------------------------
const vm = createVm({ setup: `${UNITFRAME_SETUP}
H.w.toc = 16001
local RMT = getmetatable(CreateFrame("Frame"):CreateTexture()).__index
function RMT:SetVertexOffset(i, x, y) self.vo = self.vo or {}; self.vo[i] = { x, y } end
H.unitFrames()` }).boot();
vm.slash("/vials on");
const LB = `NS.UnitFrameSkin.Get("player").health`;
vm.exec(`local lb = ${LB}; H.fillW = lb.w * 0.6; lb.barTex.GetWidth = function() return H.fillW end
  NS.LiquidPhysics.ax, NS.LiquidPhysics.jolts, NS.LiquidPhysics.shake = 0, 0, 0; H.tq = 100; H.jc = 0`);
const W0 = vm.lua(`return ${LB}.w`), TH = vm.lua(`return ${LB}.h`);

/** Anregung zur Zeit t (s): Anlaufen, Laufen, Bremsen, Landung, Treffer, schneller Lebensverlust */
function inputs(t) {
  let ax = 0;
  if (t >= 0.6 && t < 1.0) ax = 0.75;
  else if (t >= 1.0 && t < 1.6) ax = 0.08;
  else if (t >= 1.6 && t < 1.95) ax = -0.8;
  let fill = 0.6;
  if (t >= 5.0) fill = 0.6 - 0.3 * Math.min(1, (t - 5.0) / 0.15);
  return { ax, fill, jolt: t >= 2.9 && t < 2.9 + 1 / FPS ? ["land", 0.85] : t >= 4.0 && t < 4.0 + 1 / FPS ? ["hit", 0.75] : null };
}
let simT = 0;
function advanceTo(t) {
  while (simT < t - 1e-9) {
    simT += 1 / FPS;
    const i = inputs(simT);
    let code = `NS.LiquidPhysics.ax = ${i.ax}; H.fillW = ${LB}.w * ${i.fill}`;
    if (i.jolt) code += `; H.jc = H.jc + 1; NS.LiquidPhysics.jolts = H.jc; NS.LiquidPhysics.joltKind = "${i.jolt[0]}"; NS.LiquidPhysics.joltStrength = ${i.jolt[1]}`;
    vm.exec(`${code}; H.tq = H.tq + 1 / ${FPS}; NS.Liquid.Step(${LB}, H.tq)`);
  }
}
function capture() {
  const s = vm.lua(`local lb = ${LB}; local hk, wk, fk, dr = {}, {}, {}, {}
    for k = 0, lb.sliceN do hk[#hk + 1], wk[#wk + 1], fk[#fk + 1] = lb.hk[k], lb.wk[k], lb.fk[k] end
    for _, d in ipairs(lb.drops) do if d.on then dr[#dr + 1] = { x = d.x, y = d.y, a = d.a, cell = d.cell, size = d.size } end end
    return { nsl = lb.sliceN, hk = hk, wk = wk, fk = fk, drops = dr, caustic = lb.caustic:GetAlpha(), y1 = lb.pistonD or hk[#hk],
      fill = H.fillW / lb.w }`);
  s.drops = Array.isArray(s.drops) ? s.drops : Object.values(s.drops || {});
  return s;
}
const tubeAt = (st, x, y) => tube({ kind: "health", x, y, w: W0, h: 20, mirror: false, tint: TINTS.player, fill: st.fill,
  style: "piston", pstate: st }).html;

// --- PNG mit Zustaenden ---------------------------------------------------------------------------------------------------
const STATES = [["Ruhe 60 %", 0.5], ["Anlaufen (hinten höher)", 0.95], ["Nachschwappen nach dem Stopp", 2.25],
  ["Landung mit Spritzern", 3.02], ["Treffer (Ruck)", 4.08], ["Kolben fällt schnell", 5.17]];
const shots = [];
for (const [label, t] of STATES) { advanceTo(t); shots.push([label, capture()]); }
const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-kolben-"));
try {
  const Z = 4, RH = 34, Wd = 270, Hd = STATES.length * RH + 8;
  setZoom(Z);
  const body = shots.map(([label, st], r) => tubeAt(st, 136, 8 + r * RH)
    + `<div style="${abs(6, 12 + r * RH, 125, 14, `font:${px(7.5)} Marcellus;color:${rgb(SKIN.NAME.color)}`)}">${label}</div>`).join("\n");
  renderHtml(htmlOf({ W: Wd, H: Hd, body }), OUT_PNG, Wd * Z, Hd * Z);
  // Detail: Nachschwappen und Landung in nativer Groesse (1 px je UI-Einheit), 3x naechster Nachbar
  setZoom(1);
  const det = { W: 150, H: 62, body: [shots[2][1], shots[3][1]].map((st, r) => tubeAt(st, 10, 6 + r * 28)).join("") };
  const detFile = path.join(tmp, "detail.png");
  renderHtml(htmlOf(det), detFile, det.W, det.H);
  setZoom(Z);
  const A = decodePng(readFileSync(OUT_PNG)), D = decodePng(readFileSync(detFile));
  const k = 3, cw = Math.min(D.w, Math.floor(A.w / k)), ch = D.h;
  const OW = A.w, OH = A.h + ch * k;
  const rgba = new Uint8Array(OW * OH * 4);
  rgba.set(A.rgba.subarray(0, A.w * A.h * 4), 0);
  for (let y = 0; y < ch * k; y++) {
    for (let x = 0; x < OW; x++) {
      const o = ((A.h + y) * OW + x) * 4;
      if (x < cw * k) {
        const s = (Math.floor(y / k) * D.w + Math.floor(x / k)) * 4;
        rgba[o] = D.rgba[s]; rgba[o + 1] = D.rgba[s + 1]; rgba[o + 2] = D.rgba[s + 2]; rgba[o + 3] = 255;
      } else rgba.set([11, 18, 32, 255], o);
    }
  }
  writeFileSync(OUT_PNG, Buffer.from(pngUrl({ w: OW, h: OH, rgba }).split(",")[1], "base64"));
  console.log("Vorschau: " + OUT_PNG);
  compareWithReference(shots);

  // --- GIF: 0,5 ... 3,7 s mit 15 Bildern/s ----------------------------------------------------------------------------------
  if (process.argv.includes("--gif")) {
    simT = 0;
    vm.exec(`local lb = ${LB}; H.tq = 1000; lb.pT = nil`);
    const GZ = 3, GW = W0 + 24, GH = 30, frames = [];
    const times = [];
    for (let t = 0.5; t <= 3.7; t += 1 / 15) times.push(t);
    // Zustaende neu ab t = 0 (frisches Feld): erneut booten waere teuer - stattdessen Feld beruhigen und Zeitleiste neu
    vm.exec(`local lb = ${LB}; local W = NS.LiquidWave; for i = 1, lb.field.n do lb.field.h[i], lb.field.v[i] = 0, 0 end
      lb.field.awake = true; lb.ruck, lb.ruckV = 0, 0; for _, d in ipairs(lb.drops) do d.on = false end; lb.dropsOn = 0
      for k = 0, lb.sliceN do lb.wk[k] = 0 end`);
    for (const t of times) { advanceTo(t); frames.push(capture()); }
    setZoom(GZ);
    const body2 = frames.map((st, r) => tubeAt(st, 12, 5 + r * GH)).join("\n");
    const sheet = path.join(tmp, "sheet.png");
    renderHtml(htmlOf({ W: GW, H: frames.length * GH, body: body2 }), sheet, GW * GZ, frames.length * GH * GZ);
    const S = decodePng(readFileSync(sheet));
    const fw = S.w, fh = GH * GZ;
    const imgs = frames.map((_, r) => S.rgba.subarray(r * fh * fw * 4, (r + 1) * fh * fw * 4));
    writeFileSync(OUT_GIF, encodeGif(imgs, fw, fh, 7));
    console.log("Animation: " + OUT_GIF + " (" + frames.length + " Bilder)");
  }
  if (process.argv.includes("--lauf")) runLauf(tmp);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// --- Vergleich mit der freigegebenen Referenz (Sichtziel) -------------------------------------------------------------------
// Oben die Referenz verkleinert (1024 px breit), darunter unsere Kammer in Ruhe, Neigung (Anlaufen) und Welle (Landung)
// mit gleicher Rahmenbreite wie die Roehren der Referenz (~0,9 der Bildbreite).
function compareWithReference(shotList) {
  const RW = 1024, FRAME = 0.9 * RW;
  const F = LIQ.UF_FRAMES.health, U = LIQ.UF_FRAME;
  const total = 20 + Math.max(U.extraMin, 20 * U.extraRel), sc = total / F.srcH;
  const frameW = W0 + (F.openL + F.srcW - F.openR) * sc;
  const Z = FRAME / frameW, RH = 300 / Z;
  setZoom(Z);
  const ref = "data:image/jpeg;base64," + readFileSync(REF).toString("base64");
  const picks = [["Ruhe", shotList[0][1]], ["Neigung (Anlaufen)", shotList[1][1]], ["Welle (Landung)", shotList[3][1]]];
  const W = RW / Z, top = RW / Z;
  let body = `<img src="${ref}" style="${abs(0, 0, W, W)}">`;
  body += `<div style="${abs(8 / Z, 6 / Z, 400 / Z, 30 / Z, `font:${px(22 / Z)} Marcellus;color:#e8d9b0`)}">Referenz (Sichtziel)</div>`;
  picks.forEach(([label, st], r) => {
    const y = top + 40 / Z + r * RH;
    body += tube({ kind: "health", x: (W - frameW) / 2 + F.openL * sc, y, w: W0, h: 20, mirror: false, tint: TINTS.player, fill: st.fill,
      style: "piston", pstate: st }).html;
    body += `<div style="${abs(8 / Z, y - 34 / Z, 500 / Z, 30 / Z, `font:${px(22 / Z)} Marcellus;color:#e8d9b0`)}">Lucid Vials: ${label}</div>`;
  });
  const H = top + 40 / Z + picks.length * RH;
  renderHtml(htmlOf({ W, H, body }), OUT_CMP, RW, Math.round(H * Z));
  console.log("Vergleich: " + OUT_CMP);
}

// --- Realistische Laufsequenz mit der ECHTEN Bewegungsphysik (LiquidPhysics) --------------------------------------------------
// Bewegungs-APIs als Attrappe wie tests/liquid-physics.test.mjs; der gemeinsame Treiber laeuft mit 60 Bildern/s (vm.advance),
// Physik und Fluessigkeit rechnen also genau wie im Spiel. Die Fuellbreite bleibt unlesbar (wie secret in Forever).
// Ablauf: Stand 0,5 s, Anlaufen und 3 s Laufen (leichte Kurven), Stopp, Sprung und Landung. GIF in nativer Groesse
// (1 px je UI-Einheit, Leben + Mana wie im Spielerrahmen) und darunter ein 4x-Ausschnitt (naechster Nachbar).
function runLauf(dir) {
  const MOVE = `
H.w.speed, H.w.facing, H.w.falling, H.w.moving = 0, 1.0, false, false
function GetUnitSpeed() return H.w.speed, 7, 7, 4.72 end
function IsPlayerMoving() return H.w.moving end
function IsFalling() return H.w.falling end
function GetPlayerFacing() return H.w.facing end
function JumpOrAscendStart() end
for _, n in ipairs({ "MoveForward", "MoveBackward", "StrafeLeft", "StrafeRight", "TurnLeft", "TurnRight", "MoveAndSteer",
    "CameraOrSelectOrMove", "TurnOrAction", "Mouselook" }) do
    _G[n .. "Start"] = function() end
    _G[n .. "Stop"] = function() end
end
H.w.cdx, H.w.zoom = 0, 15
function GetCursorDelta() return H.w.cdx, 0 end
function GetCameraZoom() return H.w.zoom end
function IsSwimming() return false end
function IsFlying() return false end
function IsMounted() return false end
function UnitIsDeadOrGhost() return false end
function UnitIsGhost() return false end
local RMT = getmetatable(CreateFrame("Frame"):CreateTexture()).__index
function RMT:SetVertexOffset(i, x, y) self.vo = self.vo or {}; self.vo[i] = { x, y } end`;
  const v2 = createVm({ setup: `${UNITFRAME_SETUP}\nH.w.toc = 16001\n${MOVE}\nH.unitFrames()` }).boot();
  v2.slash("/vials on");
  const tubes = [`NS.UnitFrameSkin.Get("player").health`, `NS.UnitFrameSkin.Get("player").power`];
  const cap = (lb) => {
    const s = v2.lua(`local lb = ${lb}; local hk, wk, fk, dr = {}, {}, {}, {}
      for k = 0, lb.sliceN do hk[#hk + 1], wk[#wk + 1], fk[#fk + 1] = lb.hk[k], lb.wk[k], lb.fk[k] end
      for _, d in ipairs(lb.drops) do if d.on then dr[#dr + 1] = { x = d.x, y = d.y, a = d.a, cell = d.cell, size = d.size } end end
      return { nsl = lb.sliceN, hk = hk, wk = wk, fk = fk, drops = dr, caustic = lb.caustic:GetAlpha(), y1 = lb.pistonD or hk[#hk] }`);
    s.drops = Array.isArray(s.drops) ? s.drops : Object.values(s.drops || {});
    return s;
  };
  const events = [
    [0.5, `MoveForwardStart(); H.w.moving, H.w.speed = true, 7`, "PLAYER_STARTED_MOVING"],
    [1.6, `H.w.facing = 1.15`], [2.4, `H.w.facing = 1.0`], [3.0, `H.w.facing = 0.9`],
    [3.5, `MoveForwardStop(); H.w.moving, H.w.speed = false, 0`, "PLAYER_STOPPED_MOVING"],
    [4.6, `JumpOrAscendStart(); H.w.falling = true`], [5.2, `H.w.falling = false`],
  ];
  const frames = [];
  let t = 0, ei = 0;
  const END = 6.6, STEP = 1 / 60;
  let next = 0.2;
  while (t < END) {
    while (ei < events.length && events[ei][0] <= t + 1e-9) {
      v2.exec(events[ei][1]);
      if (events[ei][2]) v2.fire(events[ei][2]);
      ei++;
    }
    v2.advance(STEP);
    t += STEP;
    if (t >= next) { frames.push(tubes.map(cap)); next += 1 / 15; }
  }
  setZoom(1);
  const NW = 150, NH = 34, mana = { tex: "mono", color: [0.105, 0.105, 1] };
  const body = frames.map((fr, r) => tube({ kind: "health", x: 12, y: 2 + r * NH, w: W0, h: 20, mirror: false, tint: TINTS.player,
    fill: 0.85, style: "piston", pstate: fr[0] }).html + tube({ kind: "power", x: 12, y: 22 + r * NH, w: W0, h: 10, mirror: false,
    tint: mana, fill: 0.7, style: "piston", pstate: fr[1] }).html).join("\n");
  const sheet = path.join(dir, "lauf.png");
  renderHtml(htmlOf({ W: NW, H: frames.length * NH, body }), sheet, NW, frames.length * NH);
  setZoom(4);
  const S = decodePng(readFileSync(sheet));
  // Bild: oben nativ (zentriert), darunter 4x naechster Nachbar vom linken Teil (x 8..108, ganze Hoehe)
  const K = 4, CX = 8, CW = 100, OW = CW * K, OH = NH + NH * K;
  const imgs = frames.map((_, r) => {
    const out = new Uint8Array(OW * OH * 4);
    for (let i = 0; i < OW * OH; i++) out.set([11, 18, 32, 255], i * 4);
    for (let y = 0; y < NH; y++) for (let x = 0; x < NW && x < OW; x++) {
      const s = ((r * NH + y) * S.w + x) * 4, o = (y * OW + x + Math.floor((OW - NW) / 2)) * 4;
      out[o] = S.rgba[s]; out[o + 1] = S.rgba[s + 1]; out[o + 2] = S.rgba[s + 2];
    }
    for (let y = 0; y < NH * K; y++) for (let x = 0; x < OW; x++) {
      const s = ((r * NH + Math.floor(y / K)) * S.w + CX + Math.floor(x / K)) * 4, o = ((NH + y) * OW + x) * 4;
      out[o] = S.rgba[s]; out[o + 1] = S.rgba[s + 1]; out[o + 2] = S.rgba[s + 2];
    }
    return out;
  });
  writeFileSync(OUT_LAUF, encodeGif(imgs, OW, OH, 7));
  // --sheet <datei>: jedes 6. Bild (4x-Ausschnitt) als PNG-Kontaktbogen zur Durchsicht
  const si = process.argv.indexOf("--sheet");
  if (si > 0) {
    const pick = imgs.filter((_, i) => i % 6 === 0), CH = OH - NH;
    const sh = new Uint8Array(OW * CH * pick.length * 4);
    pick.forEach((im, i) => sh.set(im.subarray(NH * OW * 4), i * CH * OW * 4));
    writeFileSync(process.argv[si + 1], Buffer.from(pngUrl({ w: OW, h: CH * pick.length, rgba: sh }).split(',')[1], 'base64'));
  }
  console.log("Laufsequenz: " + OUT_LAUF + " (" + frames.length + " Bilder, nativ + 4x)");
}

// --- GIF89a (Farbwuerfel 6x7x6 mit geordnetem Dithering, LZW) ---------------------------------------------------------------
function encodeGif(frames, w, h, delayCs) {
  const pal = Buffer.alloc(256 * 3);
  for (let r = 0; r < 6; r++) for (let g = 0; g < 7; g++) for (let b = 0; b < 6; b++) {
    const i = r * 42 + g * 6 + b;
    pal[i * 3] = Math.round((r * 255) / 5); pal[i * 3 + 1] = Math.round((g * 255) / 6); pal[i * 3 + 2] = Math.round((b * 255) / 5);
  }
  const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  const parts = [Buffer.from("GIF89a")];
  const lsd = Buffer.alloc(7);
  lsd.writeUInt16LE(w, 0); lsd.writeUInt16LE(h, 2); lsd[4] = 0xf7; lsd[5] = 0; lsd[6] = 0;
  parts.push(lsd, pal, Buffer.from([0x21, 0xff, 0x0b]), Buffer.from("NETSCAPE2.0"), Buffer.from([3, 1, 0, 0, 0]));
  for (const rgba of frames) {
    const idx = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const o = (y * w + x) * 4, d = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5;
        const q = (v, n) => Math.max(0, Math.min(n, Math.round((v / 255) * n + d)));
        idx[y * w + x] = q(rgba[o], 5) * 42 + q(rgba[o + 1], 6) * 6 + q(rgba[o + 2], 5);
      }
    }
    const gce = Buffer.from([0x21, 0xf9, 4, 0, delayCs & 255, delayCs >> 8, 0, 0]);
    const desc = Buffer.alloc(10);
    desc[0] = 0x2c; desc.writeUInt16LE(w, 5); desc.writeUInt16LE(h, 7); desc[9] = 0;
    desc.writeUInt16LE(0, 1); desc.writeUInt16LE(0, 3);
    parts.push(gce, desc, Buffer.from([8]), lzwBlocks(idx));
  }
  parts.push(Buffer.from([0x3b]));
  return Buffer.concat(parts);
}
function lzwBlocks(idx) {
  const out = [];
  let cur = 0, nbits = 0;
  const bytes = [];
  const emit = (code, size) => {
    cur |= code << nbits; nbits += size;
    while (nbits >= 8) { bytes.push(cur & 255); cur >>>= 8; nbits -= 8; }
  };
  const CLEAR = 256, EOI = 257;
  let size = 9, next = 258, dict = new Map();
  emit(CLEAR, size);
  let prefix = idx[0];
  for (let i = 1; i < idx.length; i++) {
    const k = idx[i], key = prefix * 256 + k;
    const hit = dict.get(key);
    if (hit !== undefined) { prefix = hit; continue; }
    emit(prefix, size);
    if (next < 4096) {
      dict.set(key, next++);
      if (next > (1 << size) && size < 12) size++;
    } else {
      emit(CLEAR, size);
      dict = new Map(); next = 258; size = 9;
    }
    prefix = k;
  }
  emit(prefix, size);
  emit(EOI, size);
  if (nbits > 0) bytes.push(cur & 255);
  for (let i = 0; i < bytes.length; i += 255) {
    const chunk = bytes.slice(i, i + 255);
    out.push(Buffer.from([chunk.length]), Buffer.from(chunk));
  }
  out.push(Buffer.from([0]));
  return Buffer.concat(out);
}
