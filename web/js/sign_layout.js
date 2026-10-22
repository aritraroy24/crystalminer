// The game's sign lettering for text that only the browser knows (a live exhibit's information panel, a hologram's plaque): a port of the board, panel and plaque layout in signs.lua, giving the same [combine recipe that SG.texture gives, drawn by signs.js from the game's glyph images. The formats and the glyph metrics come from the export (data.museum.lettering); tests/test_web.mjs checks the recipes against the ones the Lua made. Pure, no DOM.

const STEP = 32;

function codepoints(M, s) {
  const known = M.r20.adv;
  return [...s].map((ch) => { const c = ch.codePointAt(0); return c <= 0xffff && known[c] !== undefined ? c : 63; });
}

// ' as an opening or closing quote, a hyphen before a digit as a minus sign.
function wordCps(M, word) {
  const cps = codepoints(M, word);
  cps.forEach((c, i) => {
    if (c === 39) cps[i] = i === 0 || cps[i - 1] === 40 ? 8216 : 8217;
    else if (c === 45 && cps[i + 1] >= 48 && cps[i + 1] <= 57) cps[i] = 8722;
  });
  return cps;
}

function measure(M, set, cps) {
  const m = M[set];
  let w = 0;
  cps.forEach((c, i) => { w += m.adv[c] + (i > 0 ? m.track : 0); });
  return w;
}

function wrap(M, set, para, maxw) {
  const m = M[set], space = m.adv[32] + m.track;
  const lines = [];
  let line = [], w = 0;
  for (const word of para.split(/[ \t\n\v\f\r]+/).filter(Boolean)) {
    const cps = wordCps(M, word), ww = measure(M, set, cps);
    if (line.length && w + space + m.track + ww > maxw) { lines.push({ cps: line, w }); line = []; w = 0; }
    if (line.length) { line.push(32); w += space + m.track; }
    line.push(...cps);
    w += ww;
  }
  if (line.length) lines.push({ cps: line, w });
  return lines;
}

function parse(text) {
  let title = null, stage = 0;
  const meta = [], paras = [];
  for (let line of text.split("\n")) {
    if (stage === 0 && line.startsWith("# ")) { title = line.slice(2); stage = 1; }
    else if (stage <= 1 && line.startsWith("## ")) { meta.push(line.slice(3)); stage = 1; }
    else {
      stage = 2;
      if (line.startsWith("## ")) line = line.slice(3); else if (line.startsWith("# ")) line = line.slice(2);
      paras.push(line);
    }
  }
  while (paras.length && paras[paras.length - 1] === "") paras.pop();
  return { title, meta, paras };
}

const snap = (h) => Math.ceil(h / STEP) * STEP;
const luaRound = (v) => Math.floor(v + 0.5);

function drawLine(M, parts, set, cps, x, y) {
  const m = M[set], gy = y + Math.floor((m.lh - m.h) / 2);
  let pen = x;
  for (const c of cps) {
    const xo = m.xoff[c];
    if (xo !== undefined) parts.push((luaRound(pen) + xo) + "," + gy + "=crystalminer_" + set + "_" + c + ".png");
    pen += m.adv[c] + m.track;
  }
}

function layoutBlock(M, f, text, body) {
  const { title, meta, paras } = parse(text);
  const maxw = f.w - f.x0 - f.pr, plan = [];
  let y = f.top, fits = true, ruleY = null;
  const add = (set, lines) => { for (const l of lines) { if (l.w > maxw) fits = false; plan.push([set, l.cps, y]); y += M[set].lh; } };
  if (title !== null) add(f.title, wrap(M, f.title, title, maxw));
  if (meta.length) y += 2;
  for (const m of meta) add(f.meta, wrap(M, f.meta, m, maxw));
  if (f.rule && title !== null) { y += f.rule.above; ruleY = y; y += f.rule.h + f.rule.below; }
  else if (title !== null || meta.length) y += f.after;
  for (const p of paras) { if (p === "") y += f.pgap; else add(body, wrap(M, body, p, maxw)); }
  const content = y + f.bottom;
  const h = Math.max(f.minh, snap(content));
  if (h > f.maxh) fits = false;
  const shift = Math.max(0, Math.floor((Math.min(h, f.maxh) - content) / 2));
  const parts = [];
  if (ruleY !== null) parts.push(f.x0 + "," + (ruleY + shift) + "=crystalminer_sign_rule.png");
  for (const [set, cps, py] of plan) drawLine(M, parts, set, cps, f.x0, py + shift);
  return { parts, h: Math.min(h, f.maxh), fits };
}

// As SG.texture for a panel or a plaque: { texture, fits, w, h }. lettering: data.museum.lettering.
export function texture(lettering, name, text, opts) {
  const f = lettering.formats[name], M = lettering.metrics;
  let r;
  for (const body of f.body) { r = layoutBlock(M, f, text, body); if (r.fits) break; }
  const head = ["[combine:" + f.w + "x" + r.h + ":0,0=crystalminer_sign_" + name + "_" + r.h + ".png"];
  if (opts && opts.tier && f.bar === "left") for (let y = 0; y < r.h; y += STEP) head.push("0," + y + "=crystalminer_sign_bar_" + Math.min(opts.tier, 4) + ".png");
  return { texture: [...head, ...r.parts].join(":"), fits: r.fits, w: f.w, h: r.h };
}
