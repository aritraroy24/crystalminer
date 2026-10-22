// The crystal exhibits' live pipeline, a port of mods/crystalminer/exhibit_live.lua: an MPContribs structure record (lattice matrix and sites in fractional coordinates) becomes atoms on the game's grid of 0.7 angstrom, with bonds and the unit cell as marker voxels, or is rejected (not bulk, disordered, too big, ...). Fingerprints keep two rooms from showing the same kind of structure. tests/test_web.mjs checks this file against the Lua pipeline on the game's sample records. Pure (no three.js).
//
// elements: the game's table, element -> { hex, radius } (exhibit_elements.lua, exported as data.museum.elements).

export const BLOCK_ANGSTROM = 0.7, MAX_SITES = 120, MAX_GAP = 6, MAX_CELL_HEIGHT = 24, MAX_DOTS = 600;
export const ANIONS = new Set(["O", "S", "Se", "Te", "F", "Cl", "Br", "I", "N"]);

const wrapped = (f) => f - Math.floor(f);
const key = (p) => p[0] + ":" + p[1] + ":" + p[2];
const roundedGrid = (point, minimum) => [0, 1, 2].map((a) => Math.floor((point[a] - minimum[a]) / BLOCK_ANGSTROM + 0.5));

function lineVoxels(start, finish) {
  const distance = Math.max(...[0, 1, 2].map((a) => Math.abs(finish[a] - start[a])));
  const steps = Math.max(1, Math.ceil(distance / 0.5));
  const out = new Map();
  for (let step = 0; step <= steps; step++) {
    const f = step / steps;
    const p = [0, 1, 2].map((a) => Math.floor(start[a] + (finish[a] - start[a]) * f + 0.5));
    out.set(key(p), p);
  }
  return out;
}

export function maxFractionalGaps(record) {
  const lengths = [record.lattice.a, record.lattice.b, record.lattice.c];
  return [0, 1, 2].map((axis) => {
    const values = record.sites.map((s) => wrapped(s.abc[axis])).sort((a, b) => a - b);
    let largest = 0;
    for (let i = 0; i < values.length; i++) {
      let gap = values[(i + 1) % values.length] - values[i];
      if (i === values.length - 1) gap += 1;
      largest = Math.max(largest, gap);
    }
    return largest * lengths[axis];
  });
}

export const isBulk = (record) => maxFractionalGaps(record).every((g) => g <= MAX_GAP);

function cartesian(record) {
  const m = record.lattice.matrix;
  const minimum = [Infinity, Infinity, Infinity];
  const points = record.sites.map((s) => {
    const f = s.abc.map(wrapped);
    return [0, 1, 2].map((a) => {
      const v = f[0] * m[0][a] + f[1] * m[1][a] + f[2] * m[2][a];
      minimum[a] = Math.min(minimum[a], v);
      return v;
    });
  });
  return { points, minimum };
}

export function convert(record) {
  const { points, minimum } = cartesian(record);
  const atoms = [], used = new Set(), size = [0, 0, 0];
  for (let i = 0; i < points.length; i++) {
    const g = roundedGrid(points[i], minimum);
    if (used.has(key(g))) return { error: "two atoms share grid cell " + key(g) };
    used.add(key(g));
    atoms.push([g[0], g[1], g[2], record.sites[i].species[0].element]);
    for (let a = 0; a < 3; a++) size[a] = Math.max(size[a], g[a] + 1);
  }
  return { atoms, box: size, points, minimum };
}

const insideBox = (p, lo, hi) => p.every((v, a) => a > 2 || (v >= lo[a] && v <= hi[a]));
const gcdOf = (counts) => Object.values(counts).reduce((g, c) => { let a = c, b = g ?? c; while (b !== 0) [a, b] = [b, a % b]; return a; }, undefined);

function reduce(counts) {
  const gcd = gcdOf(counts);
  const reduced = Object.entries(counts).map(([el, c]) => [el, c / gcd]).sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const formula = reduced.map(([el, c]) => el + String(c)).join("");
  const anonymous = reduced.map(([, c]) => c).sort((a, b) => a - b).map(String).join(",") + "-" + reduced.length;
  return { formula, anonymous };
}

export function formulaKeys(record) {
  const counts = {};
  for (const s of record.sites) { const el = s.species[0].element; counts[el] = (counts[el] || 0) + 1; }
  const r = reduce(counts);
  return [r.formula, r.anonymous];
}

export function fingerprint(record) {
  if (!Array.isArray(record.sites)) return fingerprintFormula(record.formula || "");
  const [formula, anonymous] = formulaKeys(record);
  return { formula, anonymous };
}

// As the Lua: the next element-and-digits match at or after the index, then the index moves on by the match's length.
export function fingerprintFormula(text) {
  const counts = {};
  let index = 0;
  const re = /([A-Z][a-z]?)(\d*)/g;
  while (index < text.length) {
    re.lastIndex = index;
    const m = re.exec(text);
    if (!m) break;
    counts[m[1]] = (counts[m[1]] || 0) + (m[2] === "" ? 1 : Number(m[2]));
    index += m[1].length + m[2].length;
  }
  return reduce(counts);
}

// Formula-like names from the API's list ("BaTi(SiO3)3", "BaTiO3-0"); a trailing -digits is a structure suffix. Malformed names give null, so the full record decides.
export function nameFingerprint(name) {
  if (typeof name !== "string") return null;
  const text = name.replace(/-\d+$/, "");
  const add = (into, from, k) => { for (const [el, c] of Object.entries(from)) into[el] = (into[el] || 0) + c * k; };
  function group(index, closing) {
    const counts = {};
    while (index < text.length) {
      const ch = text[index];
      if (closing && ch === closing) return [counts, index + 1];
      if (ch === "(") {
        const [nested, next] = group(index + 1, ")");
        if (!nested) return [null, next];
        index = next;
        const digits = /^\d*/.exec(text.slice(index))[0];
        add(counts, nested, digits === "" ? 1 : Number(digits));
        index += digits.length;
      } else if (/[A-Z]/.test(ch)) {
        const el = /^[A-Z][a-z]?/.exec(text.slice(index))[0];
        const digits = /^\d*/.exec(text.slice(index + el.length))[0];
        counts[el] = (counts[el] || 0) + (digits === "" ? 1 : Number(digits));
        index += el.length + digits.length;
      } else {
        return [null, index];
      }
    }
    // The Lua ends with "return closing and nil or counts, index", which gives counts either way (Lua's and/or with a nil in the middle): a bracket left open still counts. Kept, so that rooms are told apart exactly as in the game.
    return [counts, index];
  }
  const [counts, index] = group(0);
  if (!counts || index < text.length) return null;
  return reduce(counts);
}

export const similarFingerprint = (fp, fps) => (fps || []).some((e) => e.formula === fp.formula || e.anonymous === fp.anonymous);

export function filterNameCandidates(list, fps, tried) {
  const candidates = [];
  let similar = 0;
  for (const item of list || []) {
    if (item && typeof item === "object" && item.id && !(tried && tried.has(item.id))) {
      const fp = nameFingerprint(item.name);
      if (fp && similarFingerprint(fp, fps)) similar++;
      else candidates.push(item);
    }
  }
  return [candidates, similar];
}

export const similar = (record, fps) => similarFingerprint(fingerprint(record), fps);

function makeGeometry(record, converted, elements) {
  const m = record.lattice.matrix, minimum = converted.minimum;
  const corners = [];
  for (let f1 = 0; f1 <= 1; f1++) for (let f2 = 0; f2 <= 1; f2++) for (let f3 = 0; f3 <= 1; f3++) {
    corners.push(roundedGrid([0, 1, 2].map((a) => f1 * m[0][a] + f2 * m[1][a] + f3 * m[2][a]), minimum));
  }
  const atomVoxels = new Set(converted.atoms.map(key));
  const extent = [...converted.atoms, ...corners];
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const p of extent) for (let a = 0; a < 3; a++) { lo[a] = Math.min(lo[a], p[a]); hi[a] = Math.max(hi[a], p[a]); }
  const cellSet = new Map();
  const edges = [[1, 2], [1, 3], [1, 5], [2, 4], [2, 6], [3, 4], [3, 7], [4, 8], [5, 6], [5, 7], [6, 8], [7, 8]];
  for (const [i, j] of edges) for (const [k, p] of lineVoxels(corners[i - 1], corners[j - 1])) cellSet.set(k, p);
  const bonds = new Map();
  const el = (i) => record.sites[i].species[0].element;
  const anionCount = record.sites.filter((s, i) => ANIONS.has(el(i))).length;
  const addBond = (mi, ni, metal) => {
    const mp = converted.points[mi], np = converted.points[ni];
    const r1 = elements[metal] ? elements[metal].radius : 1.5;
    const r2 = elements[el(ni)] ? elements[el(ni)].radius : 1.5;
    for (let s1 = -1; s1 <= 1; s1++) for (let s2 = -1; s2 <= 1; s2++) for (let s3 = -1; s3 <= 1; s3++) {
      const image = [0, 1, 2].map((a) => np[a] + s1 * m[0][a] + s2 * m[1][a] + s3 * m[2][a]);
      const d = Math.sqrt([0, 1, 2].reduce((s, a) => s + (image[a] - mp[a]) ** 2, 0));
      if (d < 1.25 * (r1 + r2)) {
        for (const [k, p] of lineVoxels(roundedGrid(mp, minimum), roundedGrid(image, minimum))) {
          // The voxel keeps the alphabetically first metal, whichever bond reached it first.
          if (insideBox(p, lo, hi) && !atomVoxels.has(key(p)) && (!bonds.has(k) || metal < bonds.get(k)[3])) bonds.set(k, [p[0], p[1], p[2], metal]);
        }
      }
    }
  };
  for (let i = 0; i < record.sites.length; i++) {
    if (ANIONS.has(el(i))) continue;
    for (let j = 0; j < record.sites.length; j++) if (ANIONS.has(el(j))) addBond(i, j, el(i));
  }
  if (anionCount === 0) {
    for (let i = 0; i < record.sites.length; i++) for (let j = i + 1; j < record.sites.length; j++) if (el(i) !== el(j)) addBond(i, j, el(i));
  }
  const byXYZ = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
  const cell = [...cellSet].filter(([k, p]) => insideBox(p, lo, hi) && !atomVoxels.has(k) && !bonds.has(k)).map(([, p]) => p).sort(byXYZ);
  const sortedBonds = [...bonds.values()].sort((a, b) => byXYZ(a, b) || (a[3] < b[3] ? -1 : a[3] > b[3] ? 1 : 0));
  return { atoms: converted.atoms, box: converted.box, lo, hi, cell, bonds: sortedBonds };
}

export const footprint = (r) => [0, 1, 2].map((a) => r.hi[a] - r.lo[a] + 1);

// A record ready for an exhibit room, or { error } as the game words it.
export function prepare(record, elements) {
  if (!record || !record.lattice || !record.lattice.matrix) return { error: "missing lattice matrix" };
  if (!Array.isArray(record.sites) || record.sites.length === 0 || record.sites.length > MAX_SITES) return { error: "unsupported atom count" };
  for (const s of record.sites) {
    if (!s.abc || !Array.isArray(s.species) || s.species.length !== 1 || s.species[0].occu !== 1) return { error: "disordered or incomplete site" };
    if (!elements[s.species[0].element]) return { error: "unknown element" };
  }
  if (!isBulk(record)) return { error: "structure is not bulk" };
  const converted = convert(record);
  if (converted.error) return converted;
  const out = makeGeometry(record, converted, elements);
  const fp = footprint(out);
  if (fp[0] + 2 > 19 || fp[1] + 2 > 19) return { error: "horizontal footprint is too large" };
  if (fp[2] > MAX_CELL_HEIGHT) return { error: "cell is too tall" };
  if (out.bonds.length < 1) return { error: "structure has no bonds" };
  if (out.bonds.length + out.cell.length > MAX_DOTS) return { error: "too many marker dots" };
  return Object.assign(out, { id: record.id, name: record.name, md5: record.md5, formula: record.formula || formulaKeys(record)[0],
    lattice: record.lattice, sites: record.sites.length });
}

// As exhibit_dynamic.lua: a short name, else the formula.
export function displayName(r) {
  if (typeof r.name === "string" && r.name.length <= 24 && !/\s/.test(r.name)) return r.name;
  return r.formula || "Live structure";
}

export function plaqueText(r) {
  const l = r.lattice, f = (v) => Number(v).toFixed(2);
  return "# " + displayName(r) + "\n## " + (r.formula || "") + "\ncell a " + f(l.a) + " b " + f(l.b) + " c " + f(l.c) + " A\nangles " + f(l.alpha) + " " + f(l.beta) + " " + f(l.gamma)
    + " deg\n" + r.sites + " atoms\nMaterials Project record " + String(r.id).slice(0, 8) + "\nSource: MPContribs\nAtoms: Jmol colours. White lines: bonds. Orange: unit cell.";
}

// The same shape as the exported baked structures (tools/export_web.lua): atoms and dots from the model's origin in the game's axes (y up), and the grid the holograms are made from.
export function forRoom(r) {
  return {
    id: r.id, name: displayName(r), formula: r.formula, md5: r.md5, footprint: footprint(r), live: true, fingerprint: fingerprint(r),
    record_name: r.name, lattice: { a: r.lattice.a, b: r.lattice.b, c: r.lattice.c }, sites: r.sites,
    grid: { lo: r.lo, hi: r.hi, atoms: r.atoms, bonds: r.bonds, cell: r.cell },
    atoms: r.atoms.map(([x, y, z, el]) => [x - r.lo[0], z - r.lo[2], y - r.lo[1], el]),
    dots: [...r.bonds.map((v) => [v, "#FFFFFF", "bonds", 1.7]), ...r.cell.map((v) => [v, "#FF8C00", "cells", 1.2])]
      .map(([v, c, k, s]) => [v[0] - r.lo[0] - 0.5, v[2] - r.lo[2] - 0.5, v[1] - r.lo[1] - 0.5, c, k, s]),
    plaque: { text: plaqueText(r) },
  };
}
