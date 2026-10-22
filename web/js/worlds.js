// The symmetry worlds of the web version, one per region, laid out as the game lays them out (init.lua's build_region, worlds.lua), simplified. The museum is museum.js.
//
// A place is { id, name, spawn: [x, y, z], yaw, region?, area?, portals: Map "x,y,z" -> target id, objects: [three.js objects], clickables: [{ mesh, action }] }. Positions are the game's (see voxels.js).
import * as THREE from "three";
import { sign, put } from "./text.js";
import { key } from "./voxels.js";

const TIER_COLOURS = ["#9A9A9A", "#3AAFD9", "#5BAF2B", "#F0A020", "#B040FF"];

// A world's ground: a large textured plane whose top is level with the top of the floor blocks (y = 0.5).
function ground(size = 400) {
  const tex = new THREE.TextureLoader().load("textures/ground.png");
  tex.magFilter = THREE.NearestFilter;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(size, size);
  tex.colorSpace = THREE.SRGBColorSpace;
  // Pushed back in depth, so the floor blocks (whose tops are a hair above it) always win.
  const m = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshLambertMaterial({ map: tex, polygonOffset: true, polygonOffsetFactor: 4, polygonOffsetUnits: 4 }));
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
  place.portals.set(key(cx, 1, -9), "portal_hall");
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
