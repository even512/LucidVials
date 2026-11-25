// Bild-Helfer fuer die Rahmen-Medien (aus Lucid scripts/gen-minimap-media.mjs und gen-zone-media.mjs uebernommen, unveraendert):
// RGBA-TGA schreiben, Chroma-Key, PNG dekodieren, JPG -> PNG per Headless-Browser.
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import { pathToFileURL } from "node:url";

const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

/** RGBA-TGA (Typ 2, 32 bit, Ursprung oben links, BGRA) */
export function tgaRgba({ w, h, rgba }) {
  const head = Buffer.alloc(18);
  head[2] = 2;
  head.writeUInt16LE(w, 12);
  head.writeUInt16LE(h, 14);
  head[16] = 32;
  head[17] = 0x28;
  const px = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = rgba[i * 4 + 2];
    px[i * 4 + 1] = rgba[i * 4 + 1];
    px[i * 4 + 2] = rgba[i * 4];
    px[i * 4 + 3] = rgba[i * 4 + 3];
  }
  return Buffer.concat([head, px]);
}

/**
 * Chroma-Key: key = "green" | "magenta". Alpha aus der Schluesselfarb-Dominanz (Gruen: G ueber max(R, B); Magenta:
 * min(R, B) ueber G), Farbsaum an Randpixeln entfernt (die Dominanz wird abgezogen); volltransparent => schwarz.
 */
export function chromaKey({ w, h, rgba }, key) {
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    let r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    const k = key === "green" ? g - Math.max(r, b) : Math.min(r, b) - g;
    const a = 1 - smooth(k, 40, 150);
    if (k > 0) {
      if (key === "green") g -= k;
      else { r -= k; b -= k; }
    }
    if (a <= 0) { r = g = b = 0; }
    out[i * 4] = Math.max(0, r);
    out[i * 4 + 1] = Math.max(0, g);
    out[i * 4 + 2] = Math.max(0, b);
    out[i * 4 + 3] = Math.round(a * 255);
  }
  return { w, h, rgba: out };
}

/** PNG (8 bit, nicht interlaced; Graustufen, RGB, Palette, Grau+Alpha, RGBA) -> { w, h, rgba: Uint8Array } */
export function decodePng(buf) {
  const SIG = [137, 80, 78, 71, 13, 10, 26, 10];
  if (!SIG.every((b, i) => buf[i] === b)) throw new Error("keine PNG-Datei (JPG bitte vorher als PNG speichern)");
  let pos = 8, w = 0, h = 0, depth = 0, type = 0, interlace = 0, plte = null, trns = null;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString("latin1", pos + 4, pos + 8), data = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === "IHDR") { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; type = data[9]; interlace = data[12]; }
    else if (kind === "PLTE") plte = data;
    else if (kind === "tRNS") trns = data;
    else if (kind === "IDAT") idat.push(data);
    else if (kind === "IEND") break;
    pos += 12 + len;
  }
  if (depth !== 8 || interlace !== 0) throw new Error(`PNG nicht unterstuetzt (Bittiefe ${depth}, Interlace ${interlace}); bitte 8 bit ohne Interlace`);
  const ch = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
  if (!ch) throw new Error("PNG-Farbtyp nicht unterstuetzt: " + type);
  const raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * ch, img = new Uint8Array(stride * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? img[dst + x - ch] : 0, b = y > 0 ? img[dst - stride + x] : 0, c = x >= ch && y > 0 ? img[dst - stride + x - ch] : 0;
      let v = raw[src + x];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      img[dst + x] = v & 255;
    }
  }
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const o = i * 4, s = i * ch;
    if (type === 0) { rgba[o] = rgba[o + 1] = rgba[o + 2] = img[s]; rgba[o + 3] = 255; }
    else if (type === 4) { rgba[o] = rgba[o + 1] = rgba[o + 2] = img[s]; rgba[o + 3] = img[s + 1]; }
    else if (type === 2) { rgba[o] = img[s]; rgba[o + 1] = img[s + 1]; rgba[o + 2] = img[s + 2]; rgba[o + 3] = 255; }
    else if (type === 6) { for (let k = 0; k < 4; k++) rgba[o + k] = img[s + k]; }
    else { const p = img[s] * 3; rgba[o] = plte[p]; rgba[o + 1] = plte[p + 1]; rgba[o + 2] = plte[p + 2]; rgba[o + 3] = trns && img[s] < trns.length ? trns[img[s]] : 255; }
  }
  return { w, h, rgba };
}

const CHROME = [process.env.CHROME, "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].filter(Boolean);

/** JPG -> PNG (verlustfrei aus den dekodierten Pixeln) per Headless-Browser-Bildschirmfoto in Originalgroesse */
export function jpgToPng(jpg, png) {
  const b = readFileSync(jpg);
  let i = 2, w = 0, h = 0;
  while (i < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) { h = b.readUInt16BE(i + 5); w = b.readUInt16BE(i + 7); break; }
    i += 2 + b.readUInt16BE(i + 2);
  }
  if (!w || !h) throw new Error("JPG-Masse nicht lesbar: " + jpg);
  const browser = CHROME.find((p) => existsSync(p));
  if (!browser) throw new Error("kein Chrome/Edge gefunden (Umgebungsvariable CHROME setzen) - oder die Vorlage als PNG ablegen");
  const html = png + ".html";
  writeFileSync(html, `<!doctype html><html><body style="margin:0;background:#000"><img src="${pathToFileURL(jpg).href}" style="display:block;width:${w}px;height:${h}px"></body></html>`);
  const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars",
    "--force-device-scale-factor=1", `--window-size=${w},${h}`, "--virtual-time-budget=3000", `--screenshot=${png}`,
    pathToFileURL(html).href], { stdio: "ignore", timeout: 60000 });
  unlinkSync(html);
  if (r.status !== 0 || !existsSync(png)) throw new Error("Umwandlung JPG -> PNG fehlgeschlagen: " + jpg);
}
