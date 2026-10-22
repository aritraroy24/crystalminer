// The game's signs and pictures. A sign's texture is a Luanti recipe made by signs.lua (SG.texture): "[combine:WxH:x,y=base.png:x,y=letter.png:...", a background and one image per letter, rendered from DejaVu fonts by tools/make_glyphs.py. Drawing the same images at the same places on a canvas gives exactly the sign the game shows.
import * as THREE from "three";

const BASE = "textures/game/";
const images = new Map();     // file -> Promise<HTMLImageElement>

function image(file) {
  if (!images.has(file)) {
    images.set(file, new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => resolve(null);   // a missing letter leaves a gap rather than no sign
      img.src = BASE + file;
    }));
  }
  return images.get(file);
}

// A canvas texture drawn from a [combine recipe, blank until its images have loaded.
export function combine(recipe) {
  // "[combine", then "WxH", then the images.
  const [, size, ...parts] = recipe.split(":");
  const [w, h] = size.split("x").map(Number);
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.magFilter = THREE.LinearFilter;
  tex.anisotropy = 4;
  const items = parts.map((p) => {
    const eq = p.indexOf("=");
    const [x, y] = p.slice(0, eq).split(",").map(Number);
    return { x, y, file: p.slice(eq + 1) };
  });
  Promise.all(items.map((it) => image(it.file))).then((imgs) => {
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    imgs.forEach((img, i) => { if (img) ctx.drawImage(img, items[i].x, items[i].y); });
    tex.needsUpdate = true;
  });
  return { texture: tex, w, h };
}

const YAW = { s: 0, n: Math.PI, e: Math.PI / 2, w: -Math.PI / 2 };   // a plane faces three.js +z (game south) unless turned

function plane(map, w, h, back) {
  const g = new THREE.Group();
  const front = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshLambertMaterial({ map, transparent: true, alphaTest: 0.05 }));
  g.add(front);
  if (back) {
    const b = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshLambertMaterial({ map: back }));
    b.rotation.y = Math.PI;
    g.add(b);
  }
  return g;
}

let backTexture = null;
function back() {
  if (!backTexture) {
    backTexture = new THREE.TextureLoader().load(BASE + "crystalminer_sign_back.png");
    backTexture.colorSpace = THREE.SRGBColorSpace;
  }
  return backTexture;
}

// A sign as the museum recorded it: { pos, dir, texture (recipe) }; 128 px of texture per node, as signs.lua.
export function signMesh(s) {
  const { texture, w, h } = combine(s.texture);
  const g = plane(texture, w / 128, h / 128, back());
  g.position.set(s.pos[0], s.pos[1], -s.pos[2]);
  g.rotation.y = YAW[s.dir] ?? 0;
  return g;
}

// A framed picture: { pos, dir, texture, w, h } in nodes.
export function pictureMesh(p) {
  const tex = new THREE.TextureLoader().load(BASE + p.texture);
  tex.colorSpace = THREE.SRGBColorSpace;
  const g = plane(tex, p.w, p.h, back());
  g.position.set(p.pos[0], p.pos[1], -p.pos[2]);
  g.rotation.y = YAW[p.dir] ?? 0;
  return g;
}
