// Blocks drawn as Luanti draws them, from the definitions the game registered (recorded in data/museum.json by tools/cmdump): cubes with up to six tiles, see-through glass, node boxes with Luanti's texture mapping, plants as two crossed planes. A node box is turned by its facedir (param2 0 to 3) and scaled by its visual_scale.
//
// Positions are the game's (x east, y up, z north; see voxels.js): a node-box corner (x, y, z) inside a block is drawn at (x, y, -z).
import * as THREE from "three";

const BASE = "textures/game/";
// Tile order in a definition: +Y, -Y, +X, -X, +Z, -Z; a shorter list repeats its last tile.
const tileFor = (def, face) => def.tiles[Math.min(face, def.tiles.length - 1)];

export class NodeKinds {
  constructor(defs) {
    this.defs = defs;
    this.loader = new THREE.TextureLoader();
    this.textures = new Map();
    this.materials = new Map();
    this.geometries = new Map();
  }

  texture(name) {
    if (!this.textures.has(name)) {
      const t = this.loader.load(BASE + name);
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestMipmapLinearFilter;
      t.colorSpace = THREE.SRGBColorSpace;
      this.textures.set(name, t);
    }
    return this.textures.get(name);
  }

  def(name) { return this.defs[name] || { drawtype: "normal", tiles: [], walkable: true }; }

  // One material per face (six), for a kind of block.
  materials6(name) {
    if (!this.materials.has(name)) {
      const d = this.def(name);
      const glass = d.drawtype === "glasslike" || d.alpha === "blend";
      const clip = d.alpha === "clip" || d.drawtype === "plantlike";
      const lit = d.light_source ? new THREE.Color().setScalar(Math.min(1, d.light_source / 30)) : new THREE.Color(0, 0, 0);
      const mats = [0, 1, 2, 3, 4, 5].map((f) => new THREE.MeshLambertMaterial({
        map: d.tiles.length ? this.texture(tileFor(d, f)) : null, transparent: glass, depthWrite: !glass,
        alphaTest: clip ? 0.5 : 0, side: d.drawtype === "plantlike" ? THREE.DoubleSide : THREE.FrontSide, emissive: lit,
      }));
      this.materials.set(name, mats);
    }
    return this.materials.get(name);
  }

  // Whether a cube of this kind hides the faces of its neighbours.
  opaque(name) {
    const d = this.def(name);
    return d.drawtype === "normal" && d.alpha !== "blend" && d.alpha !== "clip";
  }

  // The boxes a node box is made of, in the block's own coordinates (-0.5 to 0.5), before facedir.
  boxes(name) {
    const d = this.def(name);
    if (d.drawtype === "nodebox" && d.node_box) return d.node_box;
    return [[-0.5, -0.5, -0.5, 0.5, 0.5, 0.5]];
  }

  // Geometry for a node box or a plant, one group per tile (material index 0 to 5).
  geometry(name) {
    if (this.geometries.has(name)) return this.geometries.get(name);
    const d = this.def(name);
    const s = d.visual_scale || 1;
    const b = new Builder();
    if (d.drawtype === "plantlike") {
      // Two planes crossing on the diagonals, standing on the block's floor, scaled by visual_scale.
      const h = s, r = 0.5 * s * Math.SQRT1_2 * 1.414;
      b.quad(0, [[-r, -0.5, -r], [r, -0.5, r], [r, -0.5 + h, r], [-r, -0.5 + h, -r]], [[0, 0], [1, 0], [1, 1], [0, 1]]);
      b.quad(0, [[-r, -0.5, r], [r, -0.5, -r], [r, -0.5 + h, -r], [-r, -0.5 + h, r]], [[0, 0], [1, 0], [1, 1], [0, 1]]);
    } else {
      for (const box of this.boxes(name)) b.box(box, s);
    }
    const g = b.build();
    this.geometries.set(name, g);
    return g;
  }
}

// Collects faces into one geometry with a group per tile. Coordinates in, game axes; out, three.js axes.
export class Builder {
  constructor() { this.faces = [[], [], [], [], [], []]; }

  quad(tile, corners, uvs, normal) {
    this.faces[tile].push({ corners, uvs, normal });
  }

  // A box (x1, y1, z1, x2, y2, z2) in game axes, its texture taken from where it lies in the block, as Luanti maps node boxes. scale: visual_scale, about the block's centre.
  box([x1, y1, z1, x2, y2, z2], scale = 1, at = [0, 0, 0], skip = null) {
    const [ax, ay, az] = at;
    const S = (v) => v * scale;
    const P = (x, y, z) => [ax + S(x), ay + S(y), az + S(z)];
    // Texture rows run from the top of the image down; u across, as seen from outside the face.
    const uv = (u, row) => [u, 1 - row];
    if (!skip || !skip[0]) this.quad(0, [P(x1, y2, z1), P(x2, y2, z1), P(x2, y2, z2), P(x1, y2, z2)],                 // +Y, seen from above, north up
      [uv(x1 + 0.5, 0.5 - z1), uv(x2 + 0.5, 0.5 - z1), uv(x2 + 0.5, 0.5 - z2), uv(x1 + 0.5, 0.5 - z2)], [0, 1, 0]);
    if (!skip || !skip[1]) this.quad(1, [P(x1, y1, z2), P(x2, y1, z2), P(x2, y1, z1), P(x1, y1, z1)],                 // -Y
      [uv(x1 + 0.5, z2 + 0.5), uv(x2 + 0.5, z2 + 0.5), uv(x2 + 0.5, z1 + 0.5), uv(x1 + 0.5, z1 + 0.5)], [0, -1, 0]);
    if (!skip || !skip[2]) this.quad(2, [P(x2, y1, z1), P(x2, y1, z2), P(x2, y2, z2), P(x2, y2, z1)],                 // +X, seen from the east
      [uv(z1 + 0.5, 0.5 - y1), uv(z2 + 0.5, 0.5 - y1), uv(z2 + 0.5, 0.5 - y2), uv(z1 + 0.5, 0.5 - y2)], [1, 0, 0]);
    if (!skip || !skip[3]) this.quad(3, [P(x1, y1, z2), P(x1, y1, z1), P(x1, y2, z1), P(x1, y2, z2)],                 // -X, seen from the west
      [uv(0.5 - z2, 0.5 - y1), uv(0.5 - z1, 0.5 - y1), uv(0.5 - z1, 0.5 - y2), uv(0.5 - z2, 0.5 - y2)], [-1, 0, 0]);
    if (!skip || !skip[4]) this.quad(4, [P(x2, y1, z2), P(x1, y1, z2), P(x1, y2, z2), P(x2, y2, z2)],                 // +Z, seen from the north
      [uv(0.5 - x2, 0.5 - y1), uv(0.5 - x1, 0.5 - y1), uv(0.5 - x1, 0.5 - y2), uv(0.5 - x2, 0.5 - y2)], [0, 0, 1]);
    if (!skip || !skip[5]) this.quad(5, [P(x1, y1, z1), P(x2, y1, z1), P(x2, y2, z1), P(x1, y2, z1)],                 // -Z, seen from the south
      [uv(x1 + 0.5, 0.5 - y1), uv(x2 + 0.5, 0.5 - y1), uv(x2 + 0.5, 0.5 - y2), uv(x1 + 0.5, 0.5 - y2)], [0, 0, -1]);
  }

  build() {
    const pos = [], nor = [], uvs = [], idx = [];
    const g = new THREE.BufferGeometry();
    this.faces.forEach((faces, tile) => {
      const first = idx.length;
      for (const f of faces) {
        const base = pos.length / 3;
        // Game (x, y, z) to three.js (x, y, -z).
        const c = f.corners.map((p) => [p[0], p[1], -p[2]]);
        const e1 = [c[1][0] - c[0][0], c[1][1] - c[0][1], c[1][2] - c[0][2]];
        const e2 = [c[2][0] - c[0][0], c[2][1] - c[0][1], c[2][2] - c[0][2]];
        const cross = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
        const n = f.normal ? [f.normal[0], f.normal[1], -f.normal[2]] : cross;
        for (const p of c) pos.push(p[0], p[1], p[2]);
        const len = Math.hypot(...n) || 1;
        for (let i = 0; i < 4; i++) nor.push(n[0] / len, n[1] / len, n[2] / len);
        for (const u of f.uvs) uvs.push(u[0], u[1]);
        // three.js draws a triangle's front where its corners run anticlockwise; the order is chosen so that the front faces the face's outward normal.
        const forward = cross[0] * n[0] + cross[1] * n[1] + cross[2] * n[2] >= 0;
        if (forward) idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
        else idx.push(base, base + 2, base + 1, base, base + 3, base + 2);
      }
      if (idx.length > first) g.addGroup(first, idx.length - first, tile);
    });
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute("normal", new THREE.Float32BufferAttribute(nor, 3));
    g.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
    g.setIndex(idx);
    return g;
  }
}

// facedir 0 to 3 turns a block about the vertical, 0 facing north; in three.js axes that is a turn of -n quarter turns.
export function facedirMatrix(x, y, z, param2) {
  const m = new THREE.Matrix4().makeRotationY(-(param2 % 4) * Math.PI / 2);
  m.setPosition(x, y, -z);
  return m;
}

// The boxes of a block in the game's axes, turned by its facedir, for collisions: [x1, y1, z1, x2, y2, z2] relative to its centre.
export function turnedBoxes(boxes, param2) {
  const n = param2 % 4;
  return boxes.map(([x1, y1, z1, x2, y2, z2]) => {
    let a = [x1, z1], b = [x2, z2];
    // facedir 1 turns north to east: (x, z) -> (z, -x).
    for (let i = 0; i < n; i++) { a = [a[1], -a[0]]; b = [b[1], -b[0]]; }
    return [Math.min(a[0], b[0]), y1, Math.min(a[1], b[1]), Math.max(a[0], b[0]), y2, Math.max(a[1], b[1])];
  });
}
