// Pixel-Vorschau des Optionsfensters ohne Spiel (Redesign nach docs/config-src/entwurf-config-v1.jpg), aus denselben TGA-Teilen wie
// im Spiel (Media/config/, erzeugt von scripts/cut-config.mjs):
//   node scripts/preview-config.mjs [--out <png>] [--zoom 1.5] [--bg world]
// Unter dem Fenster: 300-%-Ausschnitte der vier Ecken, des Titelschild-Anschlusses und des Reiter-Fusses (Beleg der Uebergaenge).
// Naeherung des Layouts aus UI/Config.lua, UI/ConfigWidgets.lua und UI/ConfigPreview.lua (Masse, Farben und Texte aus dem Lua-Code
// ueber die Test-VM, deDE): Flaechenkachel mit Bronzerand (Ecken gespiegelt, Kanten gekachelt), Titelschild, Reiterleiste (Reiter
// "Fluessigkeit" gewaehlt), die Seite Fluessigkeit (Rahmen-Waehler, Ueberschriften mit Trennlinie, Haken, Dropdown, Schieber) und die
// Vorschau-Spalte mit Mulde um die Buehne, Schiebern, Dropdown, Test-Knoepfen und Rollleiste. Die Buehne selbst zeigt einen
// neutralen Platzhalter (die echte Buehne zeichnet der Kern im Spiel). Schrift: Marcellus statt Friz Quadrata.
// Mit --bg world: Hintergrund "Spielwelt" (Loch in der Flaechenkachel ueber der Buehne, darunter ein Platzhalter-Verlauf).
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import { decodePng } from "./media-lib.mjs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";
import { FRAMES_OFF_SV, UNITFRAME_SETUP } from "../tests/helpers/unitframes-fake.mjs";
import { XPBAR_SETUP } from "../tests/helpers/xpbar-fake.mjs";
import { pngUrl, renderHtml } from "./preview-unitframe.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", "../LucidVials-marketing/befunde/config/vorschau-config-v2.png"));
const Z = Number(opt("--zoom", 1.5));
const BG = opt("--bg", "dark");
const MEDIA = path.join(ROOT, "addon", "LucidVials", "Media", "config");

// Werte aus dem Lua-Code ---------------------------------------------------------------------------------------------------------
const vm = createVm({
  savedVariables: FRAMES_OFF_SV,
  setup: `${UNITFRAME_SETUP}\n${XPBAR_SETUP}\nH.w.toc = 16001\nH.blizzardUi(); H.chatUi(2)\nH.unitFrames()\nH.xpBars({ second = false })`,
}).boot();
vm.exec('NS.Config.Open("liquid")');
const W = vm.lua("return NS.Widgets"); // Konstanten (Tabellen mit Funktionen fallen weg)
const Cfg = vm.lua(`local C = NS.Config; return { W = C.WIDTH, H = C.HEIGHT, cw = C.CONTENT_WIDTH, tabY = C.TAB_Y, tabH = C.TAB_HEIGHT,
  top = C.CONTENT_TOP, titleH = C.TITLE_HEIGHT, raise = C.TITLE_RAISE, titleMin = C.TITLE_MIN_WIDTH }`);
const PP = vm.lua(`local P = NS.Config.PreviewPanel; return { colW = P.COL_W, extra = P.EXTRA, inset = P.INSET,
  contentH = P.content:GetHeight() }`);
const L = (k) => vm.lua(`return NS.L[${JSON.stringify(k)}]`);
const tabs = vm.lua(`local t = {}
  for _, id in ipairs(NS.Config.pageOrder) do t[#t + 1] = { id, NS.Config.pages[id].tab.label:GetText() } end
  return t`);
const tests = vm.lua('return NS.Preview.TESTS_BY_PAGE.liquid');
const C = W.COLORS;
const SK = W.SKIN;
const rgb = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${c[3] ?? a})`;

// Texturen -----------------------------------------------------------------------------------------------------------------------
function readTga(name) {
  const b = readFileSync(path.join(MEDIA, name + ".tga")), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    rgba[i * 4] = b[18 + i * 4 + 2]; rgba[i * 4 + 1] = b[18 + i * 4 + 1]; rgba[i * 4 + 2] = b[18 + i * 4]; rgba[i * 4 + 3] = b[18 + i * 4 + 3];
  }
  return { w, h, rgba };
}
const cache = new Map();
const tex = (name) => {
  if (!cache.has(name)) { const img = readTga(name); cache.set(name, { url: pngUrl(img), w: img.w, h: img.h }); }
  return cache.get(name);
};

const abs = (x, y, w, h, extra = "") => `position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;${extra}`;
/** Textur mit Texturkoordinaten (l, r, t, b) wie SetTexCoord; l > r bzw. t > b spiegelt; Werte > 1 kacheln (REPEAT) */
function quad(name, x, y, w, h, [l, r, t, b] = [0, 1, 0, 1], extra = "") {
  const T = tex(name);
  const fx = l > r, fy = t > b;
  const u0 = Math.min(l, r), u1 = Math.max(l, r), v0 = Math.min(t, b), v1 = Math.max(t, b);
  const bw = w / (u1 - u0), bh = h / (v1 - v0);
  const tf = fx || fy ? `transform:scale(${fx ? -1 : 1},${fy ? -1 : 1});` : "";
  return `<div style="${abs(x, y, w, h, `background:url(${T.url}) ${-u0 * bw}px ${-v0 * bh}px / ${bw}px ${bh}px repeat;${tf}${extra}`)}"></div>`;
}
/** 3-Slice wie W.Slice3: Kappen aus dem Seitenverhaeltnis im Bogen, Mitte gedehnt; senkrecht mittig in (x, y, w, boxH) */
function slice3(name, x, y, w, h, extra = "") {
  const s = SK[name];
  const capL = Math.round((h * s.l) / s.h), capR = Math.round((h * s.r) / s.h);
  const uL = s.l / s.w, uR = 1 - s.r / s.w;
  return quad(name, x, y, capL, h, [0, uL, 0, 1], extra) + quad(name, x + capL, y, w - capL - capR, h, [uL, uR, 0, 1], extra)
    + quad(name, x + w - capR, y, capR, h, [uR, 1, 0, 1], extra);
}
/** 9-Slice wie W.Slice9 (outside: Rand aussen um das Rechteck, ohne Mitte) */
function slice9(name, x, y, w, h, c, { outside = false, center = false } = {}, extra = "") {
  const s = SK[name], box = s.box || [0, 0, s.w, s.h];
  const u0 = box[0] / s.w, v0 = box[1] / s.h, u3 = (box[0] + box[2]) / s.w, v3 = (box[1] + box[3]) / s.h;
  const u1 = u0 + s.s9 / s.w, v1 = v0 + s.s9 / s.h, u2 = u3 - s.s9 / s.w, v2 = v3 - s.s9 / s.h;
  if (outside) { x -= c; y -= c; w += 2 * c; h += 2 * c; }
  let o = quad(name, x, y, c, c, [u0, u1, v0, v1], extra) + quad(name, x + w - c, y, c, c, [u2, u3, v0, v1], extra)
    + quad(name, x, y + h - c, c, c, [u0, u1, v2, v3], extra) + quad(name, x + w - c, y + h - c, c, c, [u2, u3, v2, v3], extra)
    + quad(name, x + c, y, w - 2 * c, c, [u1, u2, v0, v1], extra) + quad(name, x + c, y + h - c, w - 2 * c, c, [u1, u2, v2, v3], extra)
    + quad(name, x, y + c, c, h - 2 * c, [u0, u1, v1, v2], extra) + quad(name, x + w - c, y + c, c, h - 2 * c, [u2, u3, v1, v2], extra);
  if (center) o += quad(name, x + c, y + c, w - 2 * c, h - 2 * c, [u1, u2, v1, v2], extra);
  return o;
}

// Schrift wie GameFont* (Groesse), Farbe aus W.COLORS
const FONTS = { large: 16, normal: 12, small: 10 };
const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
function text(s, x, y, { size = "normal", color = C.text, align = "left", w = null, anchor = "top" } = {}) {
  const fs = FONTS[size];
  const style = `position:absolute;left:${x}px;top:${anchor === "middle" ? y - fs * 0.62 : y}px;${w ? `width:${w}px;` : ""}`
    + `font-size:${fs}px;line-height:${Math.round(fs * 1.24)}px;color:${rgb(color)};text-align:${align};white-space:nowrap;`
    + "text-shadow:1px 1px 0 rgba(0,0,0,0.85)";
  return `<div style="${style}">${esc(s)}</div>`;
}
const textW = (s, size = "normal") => String(s).length * FONTS[size] * 0.56; // Schaetzung wie GetStringWidth

// Bausteine wie die Widgets ----------------------------------------------------------------------------------------------------
const check = (x, y, label, on, active = true) =>
  quad("check-off", x, y - 2, 22, 22, undefined, active ? "" : "opacity:0.55")
  + (on ? quad("check-on", x, y - 2, 22, 22, undefined, active ? "" : "filter:brightness(0.55)") : "")
  + text(label, x + 24, y + 11, { anchor: "middle", color: active ? C.text : C.disabled });
const header = (s, x, y, w) => text(s, x, y, { color: C.accent }) + slice3("divider", x - 2, y + 15, Math.max(70, w), W.DIVIDER_H);
const dropdown = (x, y, w, value) => slice3("dropdown", x, y, w, 22) + text(value, x + 8, y + 11, { size: "small", anchor: "middle" });
function slider(x, y, w, label, value, frac) {
  return text(label, x, y, { size: "small", color: C.muted }) + text(value, x, y, { size: "small", w, align: "right" })
    + slice3("slider-track", x, y + 20, w, 8) + quad("slider-knob", x + 8 + (w - 16) * frac - 8, y + 16, 16, 16);
}
const button = (x, y, w, label, h = 22) =>
  slice9("check-off", x, y, w, h, 5, { center: true }) + text(label, x, y + h / 2, { anchor: "middle", w, align: "center" });
function chip(x, y, w, h, label, on, size = "normal") {
  const border = `border:1px solid ${rgb(C.line)};box-sizing:border-box;`;
  return `<div style="${abs(x, y, w, h, `background:${rgb(C.panel)};${border}`)}"></div>`
    + (on ? `<div style="${abs(x, y, w, h, `background:${rgb(C.select)}`)}"></div>`
      + `<div style="${abs(x + 2, y + h - 2, w - 4, 2, `background:${rgb(C.bronze)}`)}"></div>` : "")
    + text(label, x, y + h / 2, { size, anchor: "middle", w, align: "center", color: on ? C.text : C.muted });
}
function scrollbar(x, y, h) {
  // Leiste rechts neben einer Flaeche (W.ScrollPage): Pfeil oben, Rinne, Daumen, Pfeil unten
  const A = W.SCROLL_ARROW, B = W.SCROLL_BAR_W;
  return quad("scroll-up", x, y, B, A) + quad("scroll-track", x, y + A, B, h - 2 * A)
    + quad("scroll-thumb", x + 2, y + A + 1, B - 4, B - 3) + quad("scroll-down", x, y + h - A, B, A);
}

// Fenster ------------------------------------------------------------------------------------------------------------------------
function page(Zr = Z) {
  const { W: FW, H: FH } = Cfg;
  const I = W.FILL_INSET, B = W.FRAME_BORDER, CN = W.FRAME_CORNER, T = W.EDGE_TILE, FT = W.FILL_TILE;
  const PAD = 30; // Rand um das Fenster im Bild (Titelschild ragt nach oben)
  let h = "";
  const sx = FW - 28 - PP.colW, sy = -Cfg.top + 24; // Buehne (links oben, Fensterkoordinaten nach unten positiv)
  const STAGE_H = 200;

  // Flaechenkachel (bei Spielwelt vier Teilstuecke mit Loch ueber der Buehne)
  const fill = (x, y, w, hh) => quad("fill", x, y, w, hh, [x / FT, (x + w) / FT, y / FT, (y + hh) / FT]);
  if (BG === "world") {
    h += fill(I, I, FW - 2 * I, sy - I) + fill(I, sy + STAGE_H, FW - 2 * I, FH - I - sy - STAGE_H)
      + fill(I, sy, sx - I, STAGE_H) + fill(sx + PP.colW, sy, FW - I - sx - PP.colW, STAGE_H);
  } else {
    h += fill(I, I, FW - 2 * I, FH - 2 * I);
  }
  // Rand: Kanten gekachelt, Ecken gespiegelt
  // Kanten laufen EDGE_OVERLAP unter die Ecken (wie W.WindowSkin)
  const E = CN - W.EDGE_OVERLAP, lenH = (FW - 2 * E) / T, lenV = (FH - 2 * E) / T;
  h += quad("edge-h", E, 0, FW - 2 * E, B, [0, lenH, 0, 1]) + quad("edge-h", E, FH - B, FW - 2 * E, B, [0, lenH, 1, 0])
    + quad("edge-v", 0, E, B, FH - 2 * E, [0, 1, 0, lenV]) + quad("edge-v", FW - B, E, B, FH - 2 * E, [1, 0, 0, lenV]);
  h += quad("corner", 0, 0, CN, CN, [0, 1, 0, 1]) + quad("corner", FW - CN, 0, CN, CN, [1, 0, 0, 1])
    + quad("corner", 0, FH - CN, CN, CN, [0, 1, 1, 0]) + quad("corner", FW - CN, FH - CN, CN, CN, [1, 0, 1, 0]);

  // Titelschild
  const title = "Lucid Vials";
  const s = SK.title, capL = Math.round((Cfg.titleH * s.l) / s.h), capR = Math.round((Cfg.titleH * s.r) / s.h);
  let pw = Math.max(Cfg.titleMin, Math.ceil(textW(title, "large")) + capL + capR + 24);
  if ((FW - pw) % 2) pw += 1;
  const px = (FW - pw) / 2, py = -Cfg.raise;
  // Innenflaeche durchsichtig: darunter die Flaechenkachel (wie plate.bg in UI/Config.lua)
  const inX = Math.floor(capL * 0.6), inY = 3;
  h += fill(px + inX, py + inY, pw - 2 * inX, Cfg.titleH - 2 * inY);
  h += slice3("title", px, py, pw, Cfg.titleH) + text(title, px, py + Cfg.titleH / 2, { size: "large", color: C.accent, anchor: "middle", w: pw, align: "center" });
  h += button(FW - 14 - 20, 14, 20, "X", 20);

  // Reiter
  const tabY = -Cfg.tabY;
  h += "<!--RULE-->";
  let tx = 16;
  for (const [id, label] of tabs) {
    const w = Math.max(70, Math.ceil(textW(label)) + 26);
    const on = id === "liquid";
    h += slice3(on ? "tab-on" : "tab-off", tx, tabY, w, Cfg.tabH)
      + text(label, tx + 6, tabY + Cfg.tabH / 2 - 1, { anchor: "middle", w: w - 12, align: "center", color: on ? C.accent : C.muted });
    tx += w + 2;
  }
  // Grundlinie: Fuss-Zeilen aus tab-off (wie frame.tabRule)
  const ft = W.TAB_FOOT_TOP;
  h = h.replace("<!--RULE-->", quad("tab-off", B, tabY + ft, FW - 2 * B, Cfg.tabH - ft, [0.02, 0.04, ft / Cfg.tabH, 1]));

  // Seite "Fluessigkeit" (Koordinaten wie UI/ConfigLiquid.lua, Ursprung = Seite links oben)
  const ox = 16, oy = -Cfg.top;
  const P = (x, y) => [ox + x, oy + y];
  h += text(L("UI_SCOPE_LABEL"), ...P(4, 0), { size: "small", color: C.muted });
  h += dropdown(...P(4, 16), 210, L("UI_SCOPE_ALL"));
  h += text(L("UI_SCOPE_HINT_ALL"), ...P(4, 42), { size: "small", color: C.muted });
  h += header(L("UI_FRAMES_HEAD_LIQUID"), ...P(0, 66), 740);
  h += text(L("UI_FRAMES_STYLE"), ...P(4, 92), { size: "small", color: C.muted });
  h += dropdown(...P(4, 108), 220, L("FRAMES_STYLE_PISTON"));
  h += check(...P(394, 96), L("UI_FRAMES_SMOOTH"), true) + check(...P(570, 96), L("UI_FRAMES_TRAIL"), true)
    + check(...P(394, 122), L("UI_FRAMES_FX"), true) + check(...P(570, 122), L("UI_FRAMES_DEBUFFS"), false);
  h += header(L("UI_LIQUID_HEAD_SLOSH"), ...P(0, 162), 740);
  h += check(...P(0, 212), L("UI_FRAMES_SLOSH"), true);
  h += slider(...P(4, 242), 340, L("UI_FRAMES_STRENGTH"), "60 %", 0.6) + slider(...P(394, 242), 340, L("UI_FRAMES_DAMPING"), "40 %", 0.4);

  // Vorschau-Spalte
  h += `<div style="${abs(sx - 8, -Cfg.top, 1, FH - 16 + Cfg.top, `background:${rgb(C.line)}`)}"></div>`;
  h += text(L("UI_PREVIEW_HEAD"), sx, -Cfg.top, { color: C.accent });
  let bx = PP.colW;
  for (const [mode, key] of [["world", "UI_PREVIEW_BG_WORLD"], ["light", "UI_PREVIEW_BG_LIGHT"], ["dark", "UI_PREVIEW_BG_DARK"]]) {
    const w = mode === "world" ? 66 : 50;
    bx -= w;
    h += chip(sx + bx, -Cfg.top - 1, w, 18, L(key), mode === BG, "small");
    bx -= 3;
  }
  // Buehne: neutraler Platzhalter (die echte Buehne zeichnet der Kern im Spiel), bei Spielwelt ein Verlauf als "Welt"
  if (BG === "world") {
    h += `<div style="${abs(sx, sy, PP.colW, STAGE_H, "background:linear-gradient(160deg,#5d7d8f,#38513a 60%,#2b3b25)")}"></div>`;
  } else {
    h += `<div style="${abs(sx, sy, PP.colW, STAGE_H, "background:#0f0d0c")}"></div>`;
  }
  h += text("Bühne (zeichnet das Spiel)", sx, sy + STAGE_H / 2, { size: "small", color: C.disabled, anchor: "middle", w: PP.colW, align: "center" });
  h += slice9("inset", sx, sy, PP.colW, STAGE_H, PP.inset, { outside: true });
  // Rest der Spalte (rollt): Umschalter, Pegel, Ziel-Art, Test-Knoepfe
  const cy = sy + STAGE_H + 6;
  h += chip(sx, cy, 128, 24, L("UI_PREVIEW_FRAME_PLAYER"), true) + chip(sx + PP.colW - 128, cy, 128, 24, L("UI_PREVIEW_FRAME_TARGET"), false);
  h += slider(sx, cy + 30, PP.colW, L("UI_PREVIEW_LVL_HEALTH"), "80 %", 0.8)
    + slider(sx, cy + 64, PP.colW, L("UI_PREVIEW_LVL_POWER"), "65 %", 0.65)
    + slider(sx, cy + 98, PP.colW, L("UI_PREVIEW_LVL_XP"), "45 %", 0.45);
  h += text(L("UI_PREVIEW_KIND"), sx, cy + 144, { size: "small", color: C.muted }) + dropdown(sx + PP.colW - 180, cy + 138, 180, L("UI_PREVIEW_KIND_NORMAL"));
  h += header(L("UI_PREVIEW_HEAD_TESTS"), sx, cy + 172, PP.colW);
  const cols = tests.length >= 5 ? 3 : tests.length >= 2 ? 2 : 1, bw = Math.floor((PP.colW - (cols - 1) * 4) / cols);
  const viewH = FH - 16 - cy;
  tests.forEach((word, i) => {
    const col = i % cols, row = Math.floor(i / cols), y = cy + 196 + row * 26;
    if (y + 22 <= cy + viewH) h += button(sx + col * (bw + 4), y, bw, L("UI_PREVIEW_T_" + word.toUpperCase()));
  });
  if (PP.contentH > viewH) h += scrollbar(sx + PP.colW + 4, cy, viewH);

  const fontUrl = pathToFileURL(path.join(ROOT, "addon", "LucidVials", "Fonts", "Marcellus-Regular.ttf")).href;
  const body = `<div style="position:relative;left:${PAD}px;top:${PAD}px;width:${FW}px;height:${FH}px">${h}</div>`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face { font-family: Marcellus; src: url(${fontUrl}); }
    html, body { margin: 0; background: #1b2430; font-family: Marcellus, Georgia, serif; }
    #z { zoom: ${Zr}; width: ${FW + 2 * PAD}px; height: ${FH + 2 * PAD}px; overflow: hidden;
      background: radial-gradient(ellipse at 50% 40%, #2a3442, #141a22); }
  </style></head><body><div id="z">${body}</div></body></html>`;
  return { html, w: (FW + 2 * PAD) * Zr, h: (FH + 2 * PAD) * Zr, pad: PAD, FW, FH };
}

// Beleg der Uebergaenge: unter dem Fenster die vier Ecken (und Titelschild-Anschluss, Reiter-Fuss) mit 300 % (eigener Render
// mit Zoom 3, kein Hochskalieren eines kleineren Bildes)
const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-cfg-prev-"));
try {
  const main = page(Z);
  const mainPng = path.join(tmp, "main.png");
  renderHtml(main.html, mainPng, main.w, main.h);
  const big = page(3);
  const bigPng = path.join(tmp, "big.png");
  renderHtml(big.html, bigPng, big.w, big.h);
  const A = decodePng(readFileSync(mainPng)), Bg = decodePng(readFileSync(bigPng));
  const S = 70, Zb = 3, GAP = 12, pad = big.pad, FW = big.FW, FH = big.FH;
  // Ausschnitte in Fensterkoordinaten (UI-Einheiten): vier Ecken, Titelschild links, Reiter-Fuss am linken Rand
  const plateX = (FW - vm.lua("return NS.Config.frame.titlePlate:GetWidth()")) / 2;
  const cuts = [[-4, -4], [FW - S + 4, -4], [-4, FH - S + 4], [FW - S + 4, FH - S + 4], [plateX - 20, -12], [-4, -Cfg.tabY - 20]];
  const cw = S * Zb, rows = 2, perRow = 3;
  const W2 = Math.max(A.w, perRow * cw + (perRow + 1) * GAP), H2 = A.h + rows * (cw + GAP) + GAP;
  const rgba = new Uint8Array(W2 * H2 * 4);
  for (let i = 0; i < W2 * H2; i++) { rgba[i * 4] = 20; rgba[i * 4 + 1] = 26; rgba[i * 4 + 2] = 34; rgba[i * 4 + 3] = 255; }
  const blit = (src, sx, sy, w, h, dx, dy) => {
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const X = sx + x, Y = sy + y;
      if (X < 0 || Y < 0 || X >= src.w || Y >= src.h) continue;
      const si = (Y * src.w + X) * 4, di = ((dy + y) * W2 + dx + x) * 4;
      for (let k = 0; k < 4; k++) rgba[di + k] = src.rgba[si + k];
    }
  };
  blit(A, 0, 0, A.w, A.h, 0, 0);
  cuts.forEach(([ux, uy], i) => {
    const col = i % perRow, row = Math.floor(i / perRow);
    blit(Bg, Math.round((pad + ux) * Zb), Math.round((pad + uy) * Zb), cw, cw, GAP + col * (cw + GAP), A.h + GAP + row * (cw + GAP));
  });
  writeFileSync(out, Buffer.from(pngUrl({ w: W2, h: H2, rgba }).split(",")[1], "base64"));
  console.log("Vorschau: " + out);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
