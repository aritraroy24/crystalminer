// Gallery 2's holograms, as hologram_logic.lua makes them: a structure on its grid becomes a set of points (atoms, bonds, unit-cell dots), thinned to at most max_points, scaled to fit, turned by a fixed angle and floating over its pedestal, each point a small cloud of particles. The constants come from the game (data.museum.hologram); tests/test_web.mjs checks the points against the Lua. Pure, no DOM.

const key = (x, y, z) => x + ":" + y + ":" + z;

export function scale(H, grid) {
  const span = Math.max(grid.hi[0] - grid.lo[0] + 1, grid.hi[1] - grid.lo[1] + 1, grid.hi[2] - grid.lo[2] + 1);
  return Math.min(1, H.max_span / span);
}

function rawPoints(grid) {
  const atomBy = new Map(), bondBy = new Set(), cellBy = new Set();
  for (const a of grid.atoms || []) atomBy.set(key(a[0], a[1], a[2]), a);
  for (const v of grid.bonds || []) bondBy.add(key(v[0], v[1], v[2]));
  for (const v of grid.cell || []) cellBy.add(key(v[0], v[1], v[2]));
  const out = [];
  for (let y = grid.lo[1]; y <= grid.hi[1]; y++) for (let z = grid.lo[2]; z <= grid.hi[2]; z++) for (let x = grid.lo[0]; x <= grid.hi[0]; x++) {
    const k = key(x, y, z);
    if (atomBy.has(k)) out.push({ x, y, z, kind: "atoms", element: atomBy.get(k)[3] });
    else if (bondBy.has(k)) out.push({ x, y, z, kind: "bonds" });
    else if (cellBy.has(k)) out.push({ x, y, z, kind: "cells" });
  }
  return out;
}

function kept(points, cellStep, bondStep) {
  let ci = 0, bi = 0;
  return points.filter((p) => {
    if (p.kind === "cells") return ci++ % cellStep === 0;
    if (p.kind === "bonds") return bi++ % bondStep === 0;
    return true;
  });
}

export function thin(points, cap) {
  if (points.length <= cap) return points;
  let cellStep = 1, bondStep = 1, out = points;
  while (out.length > cap && cellStep <= points.length + 1) { cellStep++; out = kept(points, cellStep, bondStep); }
  while (out.length > cap) { bondStep++; out = kept(points, cellStep, bondStep); }
  return out;
}

const minimumAmount = (exptime) => Math.max(2, Math.ceil(-Math.log(0.03) / exptime - 1));

// The level of detail by horizontal distance (1 near, 3 far); tier: the one shown now, so a player on a boundary does not flicker.
export function lod(distance, tier) {
  if (!tier || tier === 1) return distance > 33 ? 3 : distance > 17 ? 2 : 1;
  if (tier === 2) return distance <= 11 ? 1 : distance > 33 ? 3 : 2;
  return distance <= 11 ? 1 : distance <= 30 ? 2 : 3;
}

// The points of a hologram whose bottom is at centre (game coordinates): { pos: [x, y, z], colour, kind, size, spread, amount, exptime }.
export function points(H, elements, grid, centre, tier = 1) {
  if (!grid || !grid.lo || !grid.hi) return [];
  const settings = H.lod[tier - 1] || H.lod[0];
  const raw = kept(thin(rawPoints(grid), H.max_points), settings.cell_step, settings.bond_step);
  const s = scale(H, grid), rad = H.static_angle * Math.PI / 180, c = Math.cos(rad), sn = Math.sin(rad);
  const mid = [0, 1, 2].map((a) => (grid.lo[a] + grid.hi[a]) / 2);
  return raw.map((p) => {
    const east = (p.x - mid[0]) * s, north = (p.y - mid[1]) * s, up = (p.z - grid.lo[2]) * s;
    const [spread, size, amount, exptime] = H.look[p.kind];
    const step = p.kind === "atoms" ? 1 : p.kind === "bonds" ? settings.bond_step : settings.cell_step;
    const colour = p.kind === "bonds" ? "#FFFFFF" : p.kind === "cells" ? "#FF8C00" : (elements[p.element] && elements[p.element].hex) || "#FFFFFF";
    return {
      pos: [centre[0] + east * c - north * sn, centre[1] + up, centre[2] + east * sn + north * c], colour, kind: p.kind,
      size: size * settings.size, spread: spread * step, amount: Math.max(minimumAmount(exptime), Math.max(2, Math.floor(amount * settings.amount + 0.5))), exptime,
    };
  });
}

// Whether a player at pos sees the holograms (in Gallery 2 or its doorways); showing: they are shown now.
export function visible(H, pos, showing) {
  const g = H.gallery, m = showing ? H.hide_margin : H.show_margin;
  return pos[0] >= g.x0 - m && pos[0] <= g.x1 + m && pos[2] >= g.z0 - m && pos[2] <= g.z1 + m && pos[1] >= -2 && pos[1] <= 22;
}

const f2 = (v) => Number(v).toFixed(2);

// The plaque in front of pedestal n (hologram.lua plaque_text). s: the structure the exhibit room shows, or none.
export function plaqueText(H, n, s) {
  if (!s) return "# Exhibit " + n + "\nNo structure yet. Visit exhibit room " + n + ".";
  const l = s.lattice;
  return "# Exhibit " + n + ": " + (s.record_name || s.formula || "Crystal structure") + "\ncell " + f2(l.a) + " / " + f2(l.b) + " / " + f2(l.c) + " A\n"
    + (s.sites || s.grid.atoms.length) + " atoms\nMaterials Project record " + String(s.id).slice(0, 8) + "\nScale 1:" + (1 / scale(H, s.grid)).toFixed(1);
}
