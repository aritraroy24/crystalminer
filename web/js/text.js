// Signs, plaques and the billboard: text drawn on a canvas and shown on a flat panel in the world.
import * as THREE from "three";

const FONT = '"DejaVu Sans", "Segoe UI", system-ui, sans-serif';
const MONO = '"DejaVu Sans Mono", Consolas, "Courier New", monospace';

// Wraps text into lines no wider than `width` px for the context's current font.
export function wrap(ctx, text, width) {
  const out = [];
  for (const para of String(text).split("\n")) {
    if (para === "") { out.push(""); continue; }
    let line = "";
    for (const word of para.split(/\s+/)) {
      const t = line ? line + " " + word : word;
      if (ctx.measureText(t).width > width && line) { out.push(line); line = word; } else line = t;
    }
    out.push(line);
  }
  return out;
}

// A sign: a title and body text on a light panel with a coloured bar, like the game's boards. w and h in world units (nodes).
export function sign({ title, meta, body, w = 4, h = 2, bar = "#7A52D0", dark = false, px = 128 }) {
  const c = document.createElement("canvas");
  c.width = Math.round(w * px);
  c.height = Math.round(h * px);
  const ctx = c.getContext("2d");
  ctx.fillStyle = dark ? "#141A26" : "#F4F1EA";
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = bar;
  ctx.fillRect(0, 0, c.width, Math.max(6, px * 0.06));
  const pad = px * 0.22;
  let y = pad + px * 0.08;
  const ink = dark ? "#F0F0F0" : "#28241E";
  if (title) {
    ctx.fillStyle = ink;
    ctx.font = `bold ${Math.round(px * 0.3)}px ${FONT}`;
    for (const l of wrap(ctx, title, c.width - 2 * pad)) { y += px * 0.32; ctx.fillText(l, pad, y); }
  }
  if (meta) {
    ctx.fillStyle = bar;
    ctx.font = `bold ${Math.round(px * 0.17)}px ${FONT}`;
    y += px * 0.26;
    ctx.fillText(meta, pad, y);
  }
  if (body) {
    ctx.fillStyle = ink;
    ctx.font = `${Math.round(px * 0.16)}px ${FONT}`;
    y += px * 0.1;
    for (const l of wrap(ctx, body, c.width - 2 * pad)) {
      y += px * 0.21;
      if (y > c.height - pad * 0.5) break;
      ctx.fillText(l, pad, y);
    }
  }
  return panel(c, w, h);
}

export function panel(canvas, w, h) {
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tex, side: THREE.FrontSide }));
  mesh.userData.canvas = canvas;
  return mesh;
}

// Faces a panel the way a game sign faces: "n", "s", "e" or "w" (the side it is read from), at game position (x, y, z).
export function put(mesh, x, y, z, facing) {
  mesh.position.set(x, y, -z);
  // A plane faces three.js +z (game south) unless turned.
  mesh.rotation.y = { s: 0, n: Math.PI, e: Math.PI / 2, w: -Math.PI / 2 }[facing] ?? 0;
  return mesh;
}

// Prism's billboard: the latest question and answer in an LED-style pixel font, as in the game (billboard.lua). Draws on its canvas again each time.
export class Billboard {
  constructor(words, w = 12, h = 7) {
    this.words = words;
    this.canvas = document.createElement("canvas");
    this.canvas.width = 1536;
    this.canvas.height = 896;
    this.mesh = panel(this.canvas, w, h);
    this.state = { mode: "idle", fact: "" };
    this.draw();
  }

  set(state) { this.state = state; this.draw(); }

  draw() {
    const c = this.canvas, ctx = c.getContext("2d");
    const W = this.words, s = this.state;
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = "#0B1020";
    ctx.fillRect(0, 0, c.width, c.height);
    for (let y = 0; y < c.height; y += 6) { ctx.fillStyle = "#0F1528"; ctx.fillRect(0, y, c.width, 2); }
    ctx.fillStyle = "#2B2346";
    ctx.fillRect(0, 0, c.width, 84);
    ctx.strokeStyle = "#7A52D0";
    ctx.lineWidth = 8;
    ctx.strokeRect(14, 14, c.width - 28, c.height - 28);
    const font = (size) => `bold ${size}px ${MONO}`;
    const colour = { w: "#ECF0FF", c: "#78DCFF", v: "#D080FF", y: "#FFCE5C", g: "#8088A0" };
    ctx.font = font(36);
    ctx.fillStyle = colour.v;
    ctx.fillText(W.title, 54, 56);
    ctx.fillStyle = colour.g;
    ctx.textAlign = "right";
    ctx.fillText(W.hint, c.width - 54, 56);
    ctx.textAlign = "left";
    ctx.font = font(34);
    const width = c.width - 108, line = 42;
    let y = 150;
    const room = () => y < c.height - 60;
    // Text with **bold** words highlighted, wrapped.
    const write = (text, ink, maxLines = 99) => {
      const parts = [];
      String(text).split(/(\*\*[^*]+\*\*)/).forEach((p) => {
        const bold = p.startsWith("**") && p.endsWith("**");
        for (const word of (bold ? p.slice(2, -2) : p).split(/(\s+)/)) if (word) parts.push({ word, ink: bold ? "y" : ink });
      });
      let x = 54, n = 0;
      for (const p of parts) {
        if (p.word.includes("\n")) { for (let i = 0; i < (p.word.match(/\n/g) || []).length; i++) { y += line; x = 54; n++; } continue; }
        const wd = ctx.measureText(p.word).width;
        if (x + wd > 54 + width && p.word.trim()) { y += line; x = 54; n++; if (n >= maxLines || !room()) return false; }
        if (x === 54 && !p.word.trim()) continue;
        ctx.fillStyle = colour[p.ink];
        ctx.fillText(p.word, x, y);
        x += wd;
      }
      y += line;
      return true;
    };
    if (s.mode === "idle") {
      write(W.welcome, "w");
      write(W.how, "c");
      if (s.fact) { y += line; write(W.fact_title, "y"); write(s.fact, "w"); }
    } else {
      write(W.asked, "g");
      write(s.q, "c", 3);
      y += line;
      write(W.answer, "v");
      if (s.mode === "thinking") write(W.thinking, "g");
      else if (!write(s.a, "w")) { ctx.fillStyle = colour.g; ctx.fillText(W.more, 54, c.height - 52); }
    }
    this.mesh.material.map.needsUpdate = true;
  }
}
