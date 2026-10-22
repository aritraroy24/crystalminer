// The block world: which block is where, drawn with one instanced mesh per kind of block, and the ray that finds the block the player is pointing at.
//
// Positions are the game's (x east, y up, z north; a block at x spans x - 0.5 to x + 0.5). three.js is right-handed with z towards the viewer, so a block at game (x, y, z) is drawn at (x, y, -z): north is the way the camera looks by default, and east is on its right.
import * as THREE from "three";

export const COLOURS = ["red", "orange", "yellow", "lime", "green", "cyan", "blue", "purple",
  "magenta", "pink", "light_blue", "brown", "black", "grey", "light_grey", "white"];
// See-through kinds: drawn after the solid ones, and the ray passes through them (the museum's glass roof and frames too).
const CLEAR = new Set(["frame", "glass", "crystalminer:frame", "crystalminer:roof_glass", "crystalminer:glass"]);

const key = (x, y, z) => x + "," + y + "," + z;
export { key };

export class Voxels {
  constructor(scene) {
    this.scene = scene;
    this.blocks = new Map();      // "x,y,z" -> kind
    this.param2 = new Map();      // "x,y,z" -> facedir, for blocks that have one
    // The shape of a kind for collisions (museum.js sets it for the museum's blocks): null for nothing, "full" for a whole block, or boxes around the block's centre.
    this.shape = () => "full";
    this.layers = new Map();      // kind -> { mesh, keys: [], index: Map key -> i }
    this.geometry = new THREE.BoxGeometry(1, 1, 1);
    this.loader = new THREE.TextureLoader();
    this.materials = new Map();
    this.matrix = new THREE.Matrix4();
    // Every world stands on ground at y = 0 (and below) that reaches as far as anyone can walk: solid, and something to build on, wherever no block replaces it.
    this.groundEverywhere = true;
  }

  material(kind) {
    if (!this.materials.has(kind)) {
      const tex = this.loader.load("textures/" + kind + ".png");
      tex.magFilter = THREE.NearestFilter;
      tex.minFilter = THREE.NearestMipmapLinearFilter;
      tex.colorSpace = THREE.SRGBColorSpace;
      const clear = CLEAR.has(kind);
      this.materials.set(kind, new THREE.MeshLambertMaterial({ map: tex, transparent: clear, opacity: clear ? 0.55 : 1, depthWrite: !clear }));
    }
    return this.materials.get(kind);
  }

  layer(kind, need) {
    let l = this.layers.get(kind);
    if (l && l.mesh.instanceMatrix.count >= need) return l;
    // Grow by doubling: an instanced mesh has a fixed capacity, so a bigger one replaces it.
    const capacity = Math.max(64, need * 2);
    const mesh = new THREE.InstancedMesh(this.geometry, this.material(kind), capacity);
    mesh.count = 0;
    mesh.frustumCulled = false;
    if (CLEAR.has(kind)) mesh.renderOrder = 1;
    if (l) {
      for (let i = 0; i < l.mesh.count; i++) {
        l.mesh.getMatrixAt(i, this.matrix);
        mesh.setMatrixAt(i, this.matrix);
      }
      mesh.count = l.mesh.count;
      this.scene.remove(l.mesh);
      l.mesh.dispose();
      l.mesh = mesh;
    } else {
      l = { mesh, keys: [], index: new Map() };
      this.layers.set(kind, l);
    }
    this.scene.add(mesh);
    return l;
  }

  get(x, y, z) { return this.blocks.get(key(x, y, z)); }

  param2Of(x, y, z) { return this.param2.get(key(x, y, z)) || 0; }

  // A block that something else draws (the museum's merged meshes): only known here, for collisions and pointing.
  setStatic(x, y, z, kind, param2) {
    const k = key(x, y, z);
    this.blocks.set(k, kind);
    if (param2) this.param2.set(k, param2); else this.param2.delete(k);
  }

  set(x, y, z, kind) {
    const k = key(x, y, z);
    const old = this.blocks.get(k);
    if (old === kind) return;
    if (old) this.remove(x, y, z);
    const l = this.layer(kind, (this.layers.get(kind)?.keys.length || 0) + 1);
    const i = l.keys.length;
    l.keys.push(k);
    l.index.set(k, i);
    this.matrix.makeTranslation(x, y, -z);
    l.mesh.setMatrixAt(i, this.matrix);
    l.mesh.count = i + 1;
    l.mesh.instanceMatrix.needsUpdate = true;
    this.blocks.set(k, kind);
  }

  remove(x, y, z) {
    const k = key(x, y, z);
    const kind = this.blocks.get(k);
    if (!kind) return;
    const l = this.layers.get(kind);
    if (!l || !l.index.has(k)) { this.blocks.delete(k); this.param2.delete(k); return; }
    const i = l.index.get(k);
    const last = l.keys.length - 1;
    // Move the last instance into the gap.
    if (i !== last) {
      const lk = l.keys[last];
      l.mesh.getMatrixAt(last, this.matrix);
      l.mesh.setMatrixAt(i, this.matrix);
      l.keys[i] = lk;
      l.index.set(lk, i);
    }
    l.keys.pop();
    l.index.delete(k);
    l.mesh.count = l.keys.length;
    l.mesh.instanceMatrix.needsUpdate = true;
    this.blocks.delete(k);
  }

  clear() {
    for (const l of this.layers.values()) { this.scene.remove(l.mesh); l.mesh.dispose(); }
    this.layers.clear();
    this.blocks.clear();
    this.param2.clear();
    this.shape = () => "full";
  }

  // Whether the block at (x, y, z) overlaps a box [x1, y1, z1, x2, y2, z2] in world coordinates (the player).
  collides(x, y, z, box) {
    const kind = this.blocks.get(key(x, y, z));
    if (!kind) return y <= 0;   // the ground
    const shape = this.shape(kind, this.param2Of(x, y, z));
    if (shape === null) return false;
    if (shape === "full") return true;
    for (const b of shape) {
      if (box[0] < x + b[3] && box[3] > x + b[0] && box[1] < y + b[4] && box[4] > y + b[1] && box[2] < z + b[5] && box[5] > z + b[2]) return true;
    }
    return false;
  }

  solid(x, y, z) {
    // Everything at or below the ground (y = 0) is solid, wherever no block was placed: the world's ground.
    if (y <= 0 && !this.blocks.has(key(x, y, z))) return y < 0 || this.groundEverywhere;
    return this.blocks.has(key(x, y, z));
  }

  // The first block a ray from `from` (game coordinates) along `dir` meets within `reach`, and the face it enters through: { x, y, z, kind, normal: [nx, ny, nz], distance } or null. See-through blocks are passed through.
  raycast(from, dir, reach) {
    let x = Math.round(from[0]), y = Math.round(from[1]), z = Math.round(from[2]);
    const step = dir.map((d) => (d > 0 ? 1 : d < 0 ? -1 : 0));
    const next = [0, 1, 2].map((a) => {
      const c = [x, y, z][a];
      if (dir[a] === 0) return Infinity;
      const edge = c + 0.5 * step[a];
      return (edge - from[a]) / dir[a];
    });
    const delta = dir.map((d) => (d === 0 ? Infinity : Math.abs(1 / d)));
    let normal = [0, 0, 0];
    let t = 0;
    while (t <= reach) {
      const kind = this.blocks.get(key(x, y, z));
      if (kind && !CLEAR.has(kind)) return { x, y, z, kind, normal, distance: t };
      // The ground below y = 0 counts as a hit too, so blocks can be placed on it.
      if (!kind && y <= 0 && this.groundEverywhere) return { x, y, z, kind: "ground", normal, distance: t };
      const a = next[0] < next[1] ? (next[0] < next[2] ? 0 : 2) : (next[1] < next[2] ? 1 : 2);
      t = next[a];
      next[a] += delta[a];
      if (a === 0) x += step[0]; else if (a === 1) y += step[1]; else z += step[2];
      normal = [0, 0, 0];
      normal[a] = -step[a];
    }
    return null;
  }
}
