// The symmetry engine's arithmetic, for the browser: the copies of a block (S.images in mods/crystalminer/symmetry.lua) and the symmetry of a build (S.detect). Everything else, the groups themselves, comes from data/crystalminer.json, made by tools/export_web.lua from the Lua engine. tests/test_web.mjs checks this file against the Lua engine.
//
// Coordinates are "doubled" as in the engine: a node at x has its centre at 2x + 1. An operation is a flat array [w1..w9, t1, t2, t3]: r' = W r + t.

export function apply(o, r) {
  return [
    o[0] * r[0] + o[1] * r[1] + o[2] * r[2] + o[9],
    o[3] * r[0] + o[4] * r[1] + o[5] * r[2] + o[10],
    o[6] * r[0] + o[7] * r[1] + o[8] * r[2] + o[11],
  ];
}

// Lua's % is always non-negative for a positive divisor; JavaScript's is not.
const mod = (a, n) => ((a % n) + n) % n;

export function inside(region, x, y, z) {
  const s = region.size;
  return x >= 0 && x < s[0] && y >= region.ground && y < region.ground + s[1] && z >= 0 && z < s[2];
}

// All distinct images of the node at (x, y, z), itself included, as [x, y, z] in the world's coordinates.
export function images(region, x, y, z) {
  const o = region.origin;
  const c = [2 * x + 1 - o[0], 2 * y + 1 - o[1], 2 * z + 1 - o[2]];
  const out = [];
  const seen = new Set();
  const add = (d, shift) => {
    const p = [0, 0, 0];
    for (let a = 0; a < 3; a++) {
      const v = d[a] + shift[a] + o[a];
      if (mod(v, 2) !== 1) throw new Error("Image is not on a node centre");
      p[a] = (v - 1) / 2;
    }
    const k = p.join(",");
    if (!seen.has(k)) { seen.add(k); out.push(p); }
  };
  if (!region.cell) {
    for (const op of region.ops) add(apply(op, c), [0, 0, 0]);
    return out;
  }
  const cd = region.cell.map((v) => 2 * v);
  const loc = [mod(c[0], cd[0]), mod(c[1], cd[1]), mod(c[2], cd[2])];
  const n = [region.size[0] / region.cell[0], region.size[1] / region.cell[1], region.size[2] / region.cell[2]];
  for (const op of region.ops) {
    const p = apply(op, loc).map((v, a) => mod(v, cd[a]));
    for (let i = 0; i < n[0]; i++)
      for (let j = 0; j < n[1]; j++)
        for (let k = 0; k < n[2]; k++) add(p, [i * cd[0], j * cd[1], k * cd[2]]);
  }
  return out;
}

// Crystallographic kind of an operation's linear part, from its determinant and trace (S.kind).
const PROPER = { 3: "1", "-1": "2", 0: "3", 1: "4", 2: "6" };
const IMPROPER = { "-3": "-1", 1: "m", 0: "-3", "-1": "-4", "-2": "-6" };
export function kind(o) {
  const det = o[0] * (o[4] * o[8] - o[5] * o[7]) - o[1] * (o[3] * o[8] - o[5] * o[6]) + o[2] * (o[3] * o[7] - o[4] * o[6]);
  const tr = o[0] + o[4] + o[8];
  if (det === 1) return PROPER[tr] ?? "?";
  if (det === -1) return IMPROPER[tr] ?? "?";
  return "?";
}

// The signature of a set of operations, as S.signature_key writes it: "kind=count" sorted by kind, joined by ";".
export function signature(ops) {
  const counts = {};
  for (const o of ops) { const k = kind(o); counts[k] = (counts[k] || 0) + 1; }
  // Lua's table.sort on strings compares bytes, as JavaScript's default sort does for these ASCII keys.
  return Object.keys(counts).sort().map((k) => k + "=" + counts[k]).join(";");
}

// The exact point group of a build: every operation of the cube, about the centre of the build's bounding box, that maps each block onto a block of the same colour (S.detect). blocks: Map "x,y,z" -> colour, node coordinates. Returns { ops, entry } where entry is the catalogue's point group.
export function detect(blocks, detectData) {
  const pts = [];
  const mn = [Infinity, Infinity, Infinity];
  const mx = [-Infinity, -Infinity, -Infinity];
  for (const [k, colour] of blocks) {
    const p = k.split(",").map((v) => 2 * Number(v) + 1);
    for (let a = 0; a < 3; a++) { mn[a] = Math.min(mn[a], p[a]); mx[a] = Math.max(mx[a], p[a]); }
    pts.push([p, colour]);
  }
  if (pts.length === 0) return null;
  const centre = [0, 1, 2].map((a) => (mn[a] + mx[a]) / 2);
  const rel = new Map();
  for (const [p, colour] of pts) rel.set(p.map((v, a) => v - centre[a]).join(","), colour);
  const found = [];
  for (const o of detectData.cube) {
    let ok = true;
    for (const [p, colour] of pts) {
      const v = apply(o, p.map((v, a) => v - centre[a]));
      if (rel.get(v.join(",")) !== colour) { ok = false; break; }
    }
    if (ok) found.push(o);
  }
  // The operations that work always form a group (they are exactly the build's symmetries), so they need no closing.
  const sig = signature(found);
  const entry = detectData.catalog.find((e) => e.signature === sig) || null;
  return { ops: found, entry };
}
