// The places of the web version: the Portal Hall (with the Symmetry Gate and Prism's desk), and one world per symmetry region, laid out as the game lays them out (lobby.lua, init.lua's build_region, worlds.lua), simplified.
//
// A place is { id, name, spawn: [x, y, z], yaw, region?, area?, portals: Map "x,y,z" -> target id, objects: [three.js objects], clickables: [{ mesh, action }] }. Positions are the game's (see voxels.js).
import * as THREE from "three";
import { sign, put, Billboard } from "./text.js";
import { key } from "./voxels.js";

const TIER_COLOURS = ["#9A9A9A", "#3AAFD9", "#5BAF2B", "#F0A020", "#B040FF"];

// A world's ground: a large textured plane whose top is level with the top of the floor blocks (y = 0.5).
function ground(size = 400) {
  const tex = new THREE.TextureLoader().load("textures/ground.png");
  tex.magFilter = THREE.NearestFilter;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(size, size);
  tex.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshLambertMaterial({ map: tex }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.499;
  return m;
}

// Symmetry markers as points: 2-fold axes yellow, 3-fold green, 4-fold red, -4 purple, mirror planes light blue, centres white, unit cells orange (elements.lua, International Tables colours).
export function markers(dots) {
  const pos = new Float32Array(dots.length * 3), col = new Float32Array(dots.length * 3);
  const c = new THREE.Color();
  dots.forEach((d, i) => {
    pos.set([d[0], d[1], -d[2]], i * 3);
    c.set(d[3]).convertSRGBToLinear();
    col.set([c.r, c.g, c.b], i * 3);
  });
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("color", new THREE.BufferAttribute(col, 3));
  const p = new THREE.Points(g, new THREE.PointsMaterial({ size: 0.22, vertexColors: true, sizeAttenuation: true, depthWrite: false }));
  p.renderOrder = 2;
  return p;
}

function frameEdges(voxels, x0, x1, y0, y1, z0, z1) {
  for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) for (let z = z0; z <= z1; z++) {
    const edges = (x === x0 || x === x1) + (y === y0 || y === y1) + (z === z0 || z === z1);
    if (edges >= 2) voxels.set(x, y, z, "frame");
  }
}

// A symmetry world: its build space on a floor with a tier-coloured border, a glass frame for a build space above the ground, its name, its markers and a portal back to the hall.
export function buildWorld(voxels, area, lessons) {
  const r = area.region;
  const [sx, sy, sz] = r.size;
  const gy = r.ground;
  const tier = Math.min(area.tier, 4);
  for (let x = -1; x <= sx; x++) for (let z = -1; z <= sz; z++) {
    const edge = x === -1 || x === sx || z === -1 || z === sz;
    let kind = "floor";
    if (edge) kind = "border_" + tier;
    else if (r.cell && (Math.floor(x / r.cell[0]) + Math.floor(z / r.cell[2])) % 2 === 1) kind = "floor_alt";
    voxels.set(x, 0, z, kind);
  }
  if (gy > 1) frameEdges(voxels, -1, sx, gy - 1, gy + sy, -1, sz);
  const cx = Math.floor(sx / 2);
  const place = { id: area.id, name: area.name, area, region: r, spawn: [cx, 1, -6], yaw: 0, portals: new Map(), objects: [ground()], clickables: [] };
  // The portal back, south of the build space, and its plaque.
  voxels.set(cx, 1, -9, "teleporter");
  place.portals.set(key(cx, 1, -9), "hall");
  place.objects.push(put(sign({ title: "Portal Hall", body: "Punch the portal (left-click) to go back.", w: 2.4, h: 1, px: 160 }), cx, 2.6, -9.5, "n"));
  // The world's name over its south edge.
  const unlocked = lessons.unlocked(area);
  const title = sign({
    title: area.name, meta: (area.hidden ? "Symmetry: hidden" : "Symmetry " + area.symbol) + " · tier " + area.tier,
    body: unlocked ? "Build inside the border: every block is copied by the symmetry." : "Building here opens at tier " + area.tier + ": answer the quiz of the places you have unlocked.",
    w: 6, h: 1.8, bar: TIER_COLOURS[tier], px: 140,
  });
  // At eye level to the left of where players arrive, read from the south, so it never hides the build space.
  place.objects.push(put(title, cx - 6, 2.4, -4, "s"));
  place.markers = markers(area.dots);
  return place;
}

// The Portal Hall: one portal per world along the north wall, the Symmetry Gate's four displays in the middle, Prism's desk and billboard on the east side, a welcome board on the west. Players start facing south, towards the Gate, so that its displays read A to D from left to right as in the game.
export function buildHall(voxels, data, lessons, onPrism) {
  const X0 = -52, X1 = 52, Z0 = -24, Z1 = 24, H = 13;
  for (let x = X0; x <= X1; x++) for (let z = Z0; z <= Z1; z++) {
    const wall = x === X0 || x === X1 || z === Z0 || z === Z1;
    voxels.set(x, 0, z, "plaza");
    if (wall) for (let y = 1; y <= H; y++) voxels.set(x, y, z, (x - X0) % 8 === 0 || (z - Z0) % 8 === 0 ? "pillar" : "stone_brick");
  }
  const place = { id: "hall", name: "Portal Hall", spawn: [0, 1, 6], yaw: Math.PI, portals: new Map(), objects: [], clickables: [] };

  // Portals, ordered by tier as in lobby.lua.
  const order = data.regions.map((r, i) => ({ r, i })).sort((a, b) => a.r.tier - b.r.tier || a.i - b.i).map((e) => e.r);
  order.forEach((r, k) => {
    const x = X0 + 6 + k * 4, z = Z1 - 2;
    const tier = Math.min(r.tier, 4);
    voxels.set(x, 0, z, "border_" + tier);
    voxels.set(x, 1, z, "teleporter");
    for (let y = 1; y <= 4; y++) { voxels.set(x - 2, y, z + 1, "pillar"); voxels.set(x + 2, y, z + 1, "pillar"); }
    for (let xx = x - 2; xx <= x + 2; xx++) voxels.set(xx, 5, z + 1, "stone_brick");
    place.portals.set(key(x, 1, z), r.id);
    const open = lessons.unlocked(r);
    const plaque = sign({ title: r.name, meta: (r.hidden ? "hidden symmetry" : "Symmetry " + r.symbol) + " · tier " + r.tier,
      body: open ? "Punch the portal to travel." : "Open for building at tier " + r.tier + ".", w: 2.8, h: 1.4, bar: TIER_COLOURS[tier], px: 150 });
    place.objects.push(put(plaque, x, 3, z + 0.48, "s"));
  });

  // The Symmetry Gate: each display's original and copy, on its floor, with a plaque (gate.lua).
  const gx = -29, gz = -12;
  data.gate.displays.forEach((d) => {
    const [fx0, fx1, fz0, fz1] = d.floor;
    for (let x = fx0; x <= fx1; x++) for (let z = fz0; z <= fz1; z++) voxels.set(gx + x, 0, gz + z, "floor");
    for (const p of d.original) voxels.set(gx + p[0], p[1], gz + p[2], d.colour);
    for (const p of d.copy) voxels.set(gx + p[0], p[1], gz + p[2], d.colour);
    const mx = gx + (fx0 + fx1) / 2;
    place.objects.push(put(sign({ title: "Display " + d.letter, body: "Which operation made the copy on the right? Press Q to answer.", w: 3.6, h: 1.5, px: 140 }),
      mx, 6, gz + fz1 + 0.6, "n"));
  });
  place.gateArea = data.gate;

  // A welcome board on the west wall.
  place.objects.push(put(sign({ title: "Museum of Crystals and Symmetry", body: data.intro.join("\n") + "\n\nPress G for the guide to where you are, Q for the quiz, I for your progress, P to talk to Prism.", w: 9, h: 5, px: 110 }),
    X0 + 0.52, 4, 0, "e"));

  // Prism's desk on the east side: a desk, Prism floating above it, the billboard on the wall behind.
  for (let z = -4; z <= 4; z++) { voxels.set(X1 - 6, 1, z, "planks"); voxels.set(X1 - 6, 2, z, "marble"); }
  const tex = new THREE.TextureLoader().load("textures/tutor_avatar.png");
  tex.colorSpace = THREE.SRGBColorSpace;
  const prism = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true }));
  prism.scale.set(2.4, 2.4, 1);
  prism.position.set(X1 - 4, 4.4, 0);
  prism.userData.bob = true;
  place.objects.push(prism);
  place.clickables.push({ mesh: prism, action: onPrism });
  const desk = sign({ title: "Ask Prism, the AI tutor", body: "Click Prism or press P anywhere.", w: 6, h: 1.2, bar: "#7A52D0", px: 120 });
  place.objects.push(put(desk, X1 - 6.52, 1.4, 0, "w"));
  place.clickables.push({ mesh: desk, action: onPrism });
  const board = new Billboard(data.tutor.board);
  // Just in front of the wall's face (the wall block spans X1 - 0.5 to X1 + 0.5).
  place.objects.push(put(board.mesh, X1 - 0.52, 9.6, 0, "w"));
  place.clickables.push({ mesh: board.mesh, action: onPrism });
  place.billboard = board;
  return place;
}
