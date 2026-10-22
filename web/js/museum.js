// The Museum of Crystals and Symmetry as the game builds it, from data/museum.json (recorded by tools/export_museum.sh in a real Luanti build): every block, sign and picture, Prism's desk and billboard, the NPCs, the six crystal-exhibit rooms. What blocks do when punched (doors, portals, clue crystals, levers, Prism) is in main.js.
import * as THREE from "three";
import { NodeKinds, Builder, facedirMatrix, turnedBoxes } from "./nodes.js";
import { signMesh, pictureMesh } from "./signs.js";
import { Billboard } from "./text.js";
import { markers } from "./worlds.js";
import { key } from "./voxels.js";
import { texture as signTexture } from "./sign_layout.js";
import { Holograms } from "./hologram.js";
import { similarFingerprint } from "./exhibit_live.js";

// Each browser keeps what its exhibit rooms show, as the game keeps it in the world (exhibit_dynamic.lua), so Gallery 2's holograms stay filled.
const STORE = "crystalminer.exhibits.v1";

const CM = "crystalminer:";
const short = (name) => name.replace(CM, "");

// Kinds drawn once as one merged mesh each (they never change): cubes and glass. Everything else is instanced, so that doors can open and close.
const STATIC = new Set(["normal", "glasslike", "allfaces"]);

export class Museum {
  constructor(dump, data) {
    this.dump = dump;
    this.data = data;
    this.kinds = new NodeKinds(dump.defs);
    this.group = new THREE.Group();
    this.blocks = [];          // [x, y, z, name, param2]
    const n = dump.nodes;
    for (let i = 0; i < n.length; i += 5) this.blocks.push([n[i], n[i + 1], n[i + 2], dump.palette[n[i + 3]], n[i + 4]]);
    this.meta = new Map(dump.meta.map((m) => [key(...m.pos), m]));
    this.instanced = new Map();   // name -> { mesh, keys: [], index: Map }
    this.where = new Map();       // key -> name, for instanced blocks
    this.clickables = [];
    this.npcs = [];
    this.exhibitShown = new Map();   // exhibit room id -> the structure on show (baked or live)
    this.exhibitBefore = new Map();  // exhibit room id -> the fingerprint of what it showed before the current load
    this.fallbackIndex = new Map();  // exhibit room id -> the baked structure it fell back to last (1 to 3, as the game counts)
    this.restore();
    this.built = false;
  }

  // Everything that does not change, built once.
  build(onPrism) {
    if (this.built) return;
    this.built = true;
    const occupied = new Map(this.blocks.map((b) => [key(b[0], b[1], b[2]), b[3]]));
    const builders = new Map();
    const dynamic = [];
    for (const b of this.blocks) {
      const [x, y, z, name, p2] = b;
      const d = this.kinds.def(name);
      if (!STATIC.has(d.drawtype)) { dynamic.push(b); continue; }
      // A face is hidden by an opaque cube next to it, or by the same glass (as Luanti joins glass); the floor's underside is never seen.
      const hides = (dx, dy, dz) => {
        const other = occupied.get(key(x + dx, y + dy, z + dz));
        if (!other) return false;
        return this.kinds.opaque(other) || (d.drawtype === "glasslike" && other === name);
      };
      const skip = [hides(0, 1, 0), hides(0, -1, 0) || y === 0, hides(1, 0, 0), hides(-1, 0, 0), hides(0, 0, 1), hides(0, 0, -1)];
      if (skip.every(Boolean)) continue;
      if (!builders.has(name)) builders.set(name, new Builder());
      builders.get(name).box([-0.5, -0.5, -0.5, 0.5, 0.5, 0.5], 1, [x, y, z], skip);
    }
    for (const [name, b] of builders) {
      const mesh = new THREE.Mesh(b.build(), this.kinds.materials6(name));
      if (this.kinds.def(name).drawtype === "glasslike") mesh.renderOrder = 1;
      this.group.add(mesh);
    }
    for (const [x, y, z, name, p2] of dynamic) this.addInstanced(x, y, z, name, p2);
    // The hologram plaques are lettered here for what each room shows; every other sign as the game lettered it.
    const plaques = {};
    for (const s of this.dump.signs) { if (s.holo) plaques[s.holo] = s; else this.group.add(signMesh(s)); }
    this.holograms = new Holograms(this.data.museum.hologram, this.data.museum.elements, this.data.museum.lettering, plaques);
    for (const r of this.dump.exhibit_rooms || []) this.holograms.set(r.number, this.exhibitShown.get(r.id) || null);
    this.group.add(this.holograms.group);
    for (const p of this.dump.pictures) this.group.add(pictureMesh(p));
    // Prism's billboard above the desk (billboard.lua), drawn by text.js's Billboard.
    const bb = this.dump.billboard;
    this.billboard = new Billboard(this.data.tutor.board, bb.size.w, bb.size.h);
    this.billboard.mesh.position.set(bb.pos[0], bb.pos[1], -bb.pos[2]);
    this.billboard.mesh.rotation.y = { s: 0, n: Math.PI, e: Math.PI / 2, w: -Math.PI / 2 }[bb.facing] ?? Math.PI;
    this.group.add(this.billboard.mesh);
    this.clickables.push({ mesh: this.billboard.mesh, action: onPrism });
    this.buildNpcs(onPrism);
    // The ground outside, level with the floor's top.
    const tex = new THREE.TextureLoader().load("textures/ground.png");
    tex.magFilter = THREE.NearestFilter;
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(900, 300);
    tex.colorSpace = THREE.SRGBColorSpace;
    // Pushed back in depth: it lies a hair below the floor's top, too close for the depth buffer to tell them apart otherwise.
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(900, 300), new THREE.MeshLambertMaterial({ map: tex, polygonOffset: true, polygonOffsetFactor: 4, polygonOffsetUnits: 4 }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(0, 0.499, -20);
    this.group.add(ground);
  }

  // The collision and pointing map for voxels.js: every block, with its shape.
  fill(voxels) {
    for (const [x, y, z, name, p2] of this.blocks) voxels.setStatic(x, y, z, this.where.get(key(x, y, z)) || name, p2);
    voxels.shape = (name, p2) => this.shape(name, p2);
  }

  // null: nothing to bump into; "full": a whole block; else boxes relative to the block's centre.
  shape(name, p2) {
    const d = this.kinds.def(name);
    if (!d || d.unknown) return "full";
    if (d.walkable === false || d.drawtype === "plantlike") return null;
    if (d.drawtype !== "nodebox") return "full";
    // A box lying flat on the floor (a carpet) is walked over, as Luanti's step height lets you.
    const boxes = turnedBoxes(this.kinds.boxes(name), p2 || 0).filter((b) => b[4] > -0.35);
    return boxes.length ? boxes : null;
  }

  addInstanced(x, y, z, name, p2) {
    let l = this.instanced.get(name);
    const need = (l ? l.keys.length : 0) + 1;
    if (!l || l.mesh.instanceMatrix.count < need) {
      const mesh = new THREE.InstancedMesh(this.kinds.geometry(name), this.kinds.materials6(name), Math.max(16, need * 2));
      mesh.count = 0;
      mesh.frustumCulled = false;
      if (l) {
        const m = new THREE.Matrix4();
        for (let i = 0; i < l.mesh.count; i++) { l.mesh.getMatrixAt(i, m); mesh.setMatrixAt(i, m); }
        mesh.count = l.mesh.count;
        this.group.remove(l.mesh);
        l.mesh = mesh;
      } else {
        l = { mesh, keys: [], index: new Map() };
        this.instanced.set(name, l);
      }
      this.group.add(mesh);
    }
    const k = key(x, y, z);
    const i = l.keys.length;
    l.keys.push(k);
    l.index.set(k, i);
    l.mesh.setMatrixAt(i, facedirMatrix(x, y, z, p2));
    l.mesh.count = i + 1;
    l.mesh.instanceMatrix.needsUpdate = true;
    this.where.set(k, name);
  }

  removeInstanced(x, y, z) {
    const k = key(x, y, z);
    const name = this.where.get(k);
    if (!name) return;
    const l = this.instanced.get(name);
    const i = l.index.get(k), last = l.keys.length - 1;
    if (i !== last) {
      const m = new THREE.Matrix4();
      l.mesh.getMatrixAt(last, m);
      l.mesh.setMatrixAt(i, m);
      l.keys[i] = l.keys[last];
      l.index.set(l.keys[i], i);
    }
    l.keys.pop();
    l.index.delete(k);
    l.mesh.count = l.keys.length;
    l.mesh.instanceMatrix.needsUpdate = true;
    this.where.delete(k);
  }

  // Opens or closes a door, both halves, keeping their facedir (doors.lua toggle_door).
  toggleDoor(x, y, z, voxels) {
    const name = voxels.get(x, y, z);
    if (!name || !name.startsWith(CM + "door_")) return false;
    const open = name.endsWith("_open");
    const other = name.includes("bottom") ? [x, y + 1, z] : [x, y - 1, z];
    for (const p of [[x, y, z], other]) {
      const n = voxels.get(...p);
      if (!n || !n.startsWith(CM + "door_")) continue;
      const p2 = voxels.param2Of(...p);
      const next = open ? n.replace("_open", "") : n + "_open";
      this.removeInstanced(...p);
      this.addInstanced(...p, next, p2);
      voxels.setStatic(...p, next, p2);
    }
    return true;
  }

  // ------------------------------------------------------------------ NPCs (npc.lua)

  buildNpcs(onPrism) {
    const loader = new THREE.TextureLoader();
    const mat = (file) => {
      const t = loader.load("textures/game/" + file);
      t.magFilter = THREE.NearestFilter;
      t.colorSpace = THREE.SRGBColorSpace;
      return new THREE.MeshLambertMaterial({ map: t });
    };
    for (const n of this.dump.npcs) {
      const t = n.textures || [];
      const s = n.visual_size || { x: 1, y: 2, z: 1 };
      // Textures in Luanti's order (+Y, -Y, +X, -X, +Z, -Z) to three.js's box order (+x, -x, +y, -y, +z, -z), with game +Z being three.js -z.
      const mats = [t[2], t[3], t[0], t[1], t[5], t[4]].map((f) => mat(f || t[0]));
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(s.x, s.y, s.z), mats);
      const home = n.pos;
      mesh.position.set(home[0], home[1] - 0.5 + s.y / 2, -home[2]);
      this.group.add(mesh);
      const npc = { kind: n.kind, mesh, home, message: n.message, target: null, until: 0 };
      this.npcs.push(npc);
      this.clickables.push({ mesh, action: () => (n.kind === "desk" ? onPrism() : npc.say && npc.say(n.message)) });
    }
  }

  // Visitors wander within 3 blocks of home at 0.6 blocks a second, choosing a new spot every 3 to 8 seconds (npc.lua).
  updateNpcs(dt, now) {
    for (const v of this.npcs) {
      if (v.kind !== "visitor") continue;
      const p = v.mesh.position;
      const here = [p.x, -p.z];
      if (!v.target || now > v.until || Math.hypot(v.target[0] - here[0], v.target[1] - here[1]) < 0.4) {
        const a = Math.random() * 2 * Math.PI, r = Math.random() * 3;
        v.target = [v.home[0] + Math.cos(a) * r, v.home[2] + Math.sin(a) * r];
        v.until = now + 3000 + Math.random() * 5000;
      }
      const dx = v.target[0] - here[0], dz = v.target[1] - here[1];
      const d = Math.hypot(dx, dz);
      if (d < 0.1) continue;
      const step = Math.min(d, 0.6 * dt);
      p.x += (dx / d) * step;
      p.z -= (dz / d) * step;
      // The face is on the +X side: turn it the way the visitor walks.
      v.mesh.rotation.y = Math.atan2(dz, dx);
    }
  }

  // ------------------------------------------------------------------ the crystal-exhibit rooms (exhibits.lua, exhibit_dynamic.lua)

  room(id) { return (this.dump.exhibit_rooms || []).find((r) => r.id === id); }

  // Where a player arrives in an exhibit room, facing north.
  arrival(room) { return [room.min[0] + 17, 1, room.min[2] + 2]; }

  restore() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORE) || "null");
      if (!saved) return;
      const baked = new Map(this.data.museum.structures.map((s) => [s.id, s]));
      for (const [id, s] of Object.entries(saved.rooms || {})) {
        const st = s.baked ? baked.get(s.baked) : s;
        if (st && st.grid && st.atoms) this.exhibitShown.set(id, st);
      }
      for (const [id, fp] of Object.entries(saved.before || {})) this.exhibitBefore.set(id, fp);
      for (const [id, i] of Object.entries(saved.fallback || {})) this.fallbackIndex.set(id, i);
    } catch { /* no storage: the rooms start empty, as in a new world */ }
  }

  save() {
    try {
      const rooms = {};
      for (const [id, s] of this.exhibitShown) rooms[id] = s.live ? s : { baked: s.id };
      localStorage.setItem(STORE, JSON.stringify({ rooms, before: Object.fromEntries(this.exhibitBefore), fallback: Object.fromEntries(this.fallbackIndex) }));
    } catch { /* full or blocked: kept for this visit only */ }
  }

  // A load begins (exhibit_dynamic.lua start_load): what the room shows now is what the new structure must not be like.
  startLoad(room) {
    const s = this.exhibitShown.get(room.id);
    if (s) this.exhibitBefore.set(room.id, s.fingerprint);
  }

  // What a live structure for a room must not be like (exhibit_live.lua exclusion_fingerprints): what the other rooms show and what this room showed before.
  exclusions(room) {
    const out = [...this.exhibitShown].filter(([id, s]) => id !== room.id && s.fingerprint).map(([, s]) => s.fingerprint);
    if (this.exhibitBefore.has(room.id)) out.push(this.exhibitBefore.get(room.id));
    return out;
  }

  // The md5s of every structure on show or baked in: a live one must be new.
  shownMd5() { return new Set([...[...this.exhibitShown.values()].map((s) => s.md5), ...this.data.museum.structures.map((s) => s.md5)]); }

  // The offline choice among the baked structures (exhibit_dynamic.lua fallback): the next one, in turn, not like what the other rooms show; with only three, else the next one this room is not showing.
  fallbackFor(room) {
    const S = this.data.museum.structures, excluded = this.exclusions(room), current = this.exhibitShown.get(room.id);
    const from = this.fallbackIndex.get(room.id) || 0;
    for (const ok of [(s) => !similarFingerprint(s.fingerprint, excluded), (s) => !(current && current.md5 === s.md5)]) {
      for (let off = 0; off < S.length; off++) {
        const i = (from + off) % S.length;
        if (ok(S[i])) { this.fallbackIndex.set(room.id, i + 1); return S[i]; }
      }
    }
    return S[0];
  }

  // Shows a structure in a room: the model on its platform and the information panel; its hologram in Gallery 2 follows.
  showExhibit(room, s) {
    const changed = this.exhibitShown.get(room.id) !== s;
    this.exhibitShown.set(room.id, s);
    if (changed) { this.save(); if (this.holograms) this.holograms.set(room.number, s); }
    if (room.model) this.group.remove(room.model);
    const g = new THREE.Group();
    const origin = [room.min[0] + 9, 2, room.min[2] + 10];
    // footprint is in the structure's axes (x, y, z up): game x, game z, height.
    const fx = s.footprint[0];
    // The platform the model stands on.
    const stone = this.kinds.materials6(CM + "stone_brick")[0];
    const plat = new THREE.Mesh(new THREE.BoxGeometry(fx + 2, 1, s.footprint[1] + 2), stone);
    plat.position.set(origin[0] - 1 + (fx + 2) / 2 - 0.5, 1, -(origin[2] - 1 + (s.footprint[1] + 2) / 2 - 0.5));
    g.add(plat);
    // Atoms: rounded cubes in Jmol colours, as the game's atom mesh (models/crystalminer_atom.obj).
    const geo = roundedCube(0.92);
    const atoms = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ color: 0xffffff }), s.atoms.length);
    const m = new THREE.Matrix4(), c = new THREE.Color();
    s.atoms.forEach(([ax, ay, az, el], k) => {
      m.makeTranslation(origin[0] + ax, origin[1] + ay, -(origin[2] + az));
      atoms.setMatrixAt(k, m);
      atoms.setColorAt(k, c.set(this.data.museum.element_colours[el] || "#909090"));
    });
    g.add(atoms);
    g.add(markers(s.dots.map(([x, y, z, colour, kind, size]) => [origin[0] + x, origin[1] + y, origin[2] + z, colour, kind, size])));
    // The information panel on the far wall.
    const plaqueX = origin[0] + Math.floor((fx - 1) / 2);
    g.add(signMesh({ pos: [plaqueX, 5, room.min[2] + room.size[2] - 1 - 0.52], dir: "s", texture: s.plaque.texture || signTexture(this.data.museum.lettering, "panel", s.plaque.text).texture }));
    room.model = g;
    this.group.add(g);
    return s;
  }
}

// A cube with rounded edges: a subdivided box pulled part of the way towards a sphere.
function roundedCube(size) {
  const g = new THREE.BoxGeometry(1, 1, 1, 4, 4, 4);
  const p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const s = v.clone().normalize().multiplyScalar(0.62);
    v.lerp(s, 0.45).multiplyScalar(size);
    p.setXYZ(i, v.x, v.y, v.z);
  }
  g.computeVertexNormals();
  return g;
}
