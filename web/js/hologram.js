// Gallery 2's six holograms (hologram.lua): over each pedestal, the structure its exhibit room shows, as still clouds of glowing dust, and a plaque in front. As in the game a new structure appears point by point behind a white scanner, the detail is lighter far away, and they are drawn only in and near Gallery 2. The points come from hologram_logic.js.
import * as THREE from "three";
import { points, lod, visible, plaqueText } from "./hologram_logic.js";
import { texture as signTexture } from "./sign_layout.js";
import { signMesh } from "./signs.js";

const PX = 0.15;            // Luanti particle size to nodes, as the worlds' markers
const REVEAL = 300;         // points a second while scanning (60 every 0.2 s in the game)
const SCANNER = [3.2 * PX, 36];

const VERTEX = `
attribute float size;
attribute vec3 colour;
varying vec3 vColour;
uniform float uScale;
void main() {
  vColour = colour;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = size * uScale / -mv.z;
  gl_Position = projectionMatrix * mv;
}`;
const FRAGMENT = `
varying vec3 vColour;
void main() {
  float d = length(gl_PointCoord - vec2(0.5));
  if (d > 0.5) discard;
  gl_FragColor = vec4(vColour, smoothstep(0.5, 0.25, d));
}`;

function material() {
  const m = new THREE.ShaderMaterial({ vertexShader: VERTEX, fragmentShader: FRAGMENT, uniforms: { uScale: { value: 400 } }, transparent: true, depthWrite: false });
  return m;
}

// A cloud of particles: each point of the hologram gets amount x exptime of them, alive at random spots in its little box.
class Cloud {
  constructor(pts) {
    this.pts = pts;
    this.of = [];          // particle index -> point index
    this.starts = [];      // point index -> its first particle
    pts.forEach((p, i) => { this.starts.push(this.of.length); for (let k = 0; k < Math.round(p.amount * p.exptime); k++) this.of.push(i); });
    this.starts.push(this.of.length);
    const n = this.of.length;
    this.pos = new Float32Array(n * 3);
    const colour = new Float32Array(n * 3), size = new Float32Array(n), c = new THREE.Color();
    this.of.forEach((i, k) => {
      const p = pts[i];
      this.place(k);
      c.set(p.colour);   // the shader writes colours as they are (sRGB), like the game's glowing particles
      colour.set([c.r, c.g, c.b], k * 3);
      size[k] = p.size * PX;
    });
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(this.pos, 3));
    g.setAttribute("colour", new THREE.BufferAttribute(colour, 3));
    g.setAttribute("size", new THREE.BufferAttribute(size, 1));
    this.mesh = new THREE.Points(g, material());
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 2;
    this.mesh.onBeforeRender = (renderer, scene, camera) => {
      this.mesh.material.uniforms.uScale.value = renderer.getDrawingBufferSize(TMP).y * camera.projectionMatrix.elements[5] / 2;
    };
  }

  place(k) {
    const p = this.pts[this.of[k]], s = p.spread;
    this.pos[k * 3] = p.pos[0] + (Math.random() * 2 - 1) * s;
    this.pos[k * 3 + 1] = p.pos[1] + (Math.random() * 2 - 1) * s;
    this.pos[k * 3 + 2] = -(p.pos[2] + (Math.random() * 2 - 1) * s);
  }

  // Particles die and are born elsewhere in their box: each lives exptime seconds.
  turn(dt) {
    const n = this.of.length;
    if (!n) return;
    const count = Math.min(n, Math.round(n * dt / this.pts[0].exptime));
    for (let j = 0; j < count; j++) this.place(Math.floor(Math.random() * n));
    this.mesh.geometry.attributes.position.needsUpdate = true;
  }

  // Shows the first `shown` points only.
  reveal(shown) { this.mesh.geometry.setDrawRange(0, this.starts[Math.min(shown, this.pts.length)]); }

  dispose() { this.mesh.geometry.dispose(); this.mesh.material.dispose(); }
}
const TMP = new THREE.Vector2();

export class Holograms {
  // H: data.museum.hologram; plaques: the dumped plaque signs, by pedestal number.
  constructor(H, elements, lettering, plaques) {
    this.H = H;
    this.elements = elements;
    this.lettering = lettering;
    this.plaques = plaques;
    this.group = new THREE.Group();
    this.slots = H.centres.map(() => ({ structure: null, cloud: null, tier: 0, shown: 0, plaque: null }));
    this.showing = false;
    this.scanner = new Cloud([{ pos: [0, 0, 0], colour: "#FFFFFF", kind: "atoms", size: SCANNER[0] / PX, spread: 0, amount: SCANNER[1] / 2, exptime: 2 }]);
    this.scanner.mesh.visible = false;
    this.group.add(this.scanner.mesh);
    for (let n = 1; n <= this.slots.length; n++) this.letter(n);
  }

  // Pedestal n (1 to 6) shows structure s (or nothing): a new plaque, and the hologram scans in again.
  set(n, s) {
    const slot = this.slots[n - 1];
    if (!slot || slot.structure === s) return;
    slot.structure = s;
    this.drop(slot);
    this.letter(n);
  }

  letter(n) {
    const slot = this.slots[n - 1], sign = this.plaques[n];
    if (!sign) return;
    if (slot.plaque) {
      this.group.remove(slot.plaque);
      slot.plaque.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material && o.material.map) o.material.map.dispose(); });
    }
    slot.plaque = signMesh({ pos: sign.pos, dir: sign.dir, texture: signTexture(this.lettering, "plaque", plaqueText(this.H, n, slot.structure)).texture });
    this.group.add(slot.plaque);
  }

  drop(slot) {
    if (slot.cloud) { this.group.remove(slot.cloud.mesh); slot.cloud.dispose(); }
    slot.cloud = null;
    slot.tier = 0;
  }

  build(slot, i, tier, scan) {
    this.drop(slot);
    const c = this.H.centres[i];
    slot.cloud = new Cloud(points(this.H, this.elements, slot.structure.grid, [c.x, this.H.hover_base, c.z], tier));
    slot.tier = tier;
    slot.shown = scan ? 0 : slot.cloud.pts.length;
    slot.cloud.reveal(slot.shown);
    this.group.add(slot.cloud.mesh);
  }

  // Each frame: shown only in and near Gallery 2; the detail by distance; scanning in; the dust's slow turnover.
  update(dt, pos) {
    const on = visible(this.H, pos, this.showing);
    if (on !== this.showing) {
      this.showing = on;
      if (!on) for (const slot of this.slots) this.drop(slot);
    }
    this.scanner.mesh.visible = false;
    if (!on) return;
    let budget = Math.ceil(REVEAL * dt);
    const order = this.slots.map((slot, i) => ({ slot, i, d: Math.hypot(pos[0] - this.H.centres[i].x, pos[2] - this.H.centres[i].z) })).sort((a, b) => a.d - b.d);
    for (const { slot, i, d } of order) {
      if (!slot.structure) continue;
      const tier = lod(d, slot.tier || undefined);
      if (!slot.cloud) this.build(slot, i, tier, true);
      else if (tier !== slot.tier) this.build(slot, i, tier, false);
      const cloud = slot.cloud;
      if (slot.shown < cloud.pts.length && budget > 0) {
        const step = Math.min(budget, cloud.pts.length - slot.shown);
        slot.shown += step;
        budget -= step;
        cloud.reveal(slot.shown);
        if (slot.shown < cloud.pts.length) {
          const p = cloud.pts[slot.shown - 1].pos;
          this.scanner.pts[0].pos = p;
          for (let k = 0; k < this.scanner.of.length; k++) this.scanner.place(k);
          this.scanner.mesh.geometry.attributes.position.needsUpdate = true;
          this.scanner.mesh.visible = true;
        }
      }
      cloud.turn(dt);
    }
  }
}
