// crystalminer in the browser: the Portal Hall and the symmetry worlds, built with three.js from data/crystalminer.json (made by tools/export_web.lua from the game's own engine and texts).
import * as THREE from "three";
import { Voxels, COLOURS, key } from "./voxels.js";
import { Player } from "./player.js";
import { Lessons, loadBuild, saveBuild } from "./lessons.js";
import { buildHall, buildWorld, markers } from "./worlds.js";
import { images, inside, detect } from "./symmetry.js";
import { UI } from "./ui.js";
import { Chat } from "./chat.js";

const params = new URLSearchParams(location.search);
// ?test=1 is for automated screenshots: no start screen, every world open (not saved), the world's showcase built. ?world=<id> starts in a world.
const TEST = params.get("test") === "1";
const REACH = 7;

const data = await (await fetch("data/crystalminer.json")).json();
const lessons = new Lessons(data);
if (TEST) { lessons.save = () => {}; lessons.progress.tier = 4; }

// ------------------------------------------------------------------ three.js

const canvas = document.getElementById("view");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: TEST });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
const scene = new THREE.Scene();
scene.background = new THREE.Color("#8FC9F0");
scene.fog = new THREE.Fog("#8FC9F0", 60, 220);
const camera = new THREE.PerspectiveCamera(72, 1, 0.05, 600);
scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8aa0, 2.2));
const sun = new THREE.DirectionalLight(0xffffff, 1.6);
sun.position.set(30, 60, 20);
scene.add(sun);
const voxels = new Voxels(scene);
const player = new Player();
// An outline round the block the player points at.
const cursor = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1.01, 1.01, 1.01)), new THREE.LineBasicMaterial({ color: 0x111111 }));
cursor.visible = false;
scene.add(cursor);

function resize() {
  renderer.setSize(innerWidth, innerHeight, false);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
addEventListener("resize", resize);
resize();

// ------------------------------------------------------------------ state

let place = null;              // the current place (worlds.js)
let built = new Map();         // blocks the player built in the current world: "x,y,z" -> colour
let selected = 0;
let markersOn = true;
let pending = null;            // a first block waiting for its prediction
let pendingGuide = false;      // a guide to show once the start screen is closed
let billboard = { mode: "idle", fact: data.glossary[0] };
let factIndex = 0;
const keys = {};

const ui = new UI({ onClose: () => resume() });
const chat = new Chat(data.tutor, {
  context: () => ({ tier: lessons.progress.tier, place: place && place.area ? place.name : "the Museum of Crystals and Symmetry", inWorld: !!(place && place.area) }),
  onClose: () => resume(),
  onAsked: (q) => setBoard({ mode: "thinking", q }),
  onAnswered: (q, a) => setBoard({ mode: "answer", q, a, at: Date.now() }),
  onFailed: () => setBoard({ mode: "idle", fact: data.glossary[factIndex] }),
});

function setBoard(s) {
  billboard = s;
  if (place && place.billboard) place.billboard.set(s);
}

const busy = () => ui.isOpen() || chat.isOpen();

// ------------------------------------------------------------------ places

function clearPlace() {
  if (!place) return;
  for (const o of place.objects) scene.remove(o);
  if (place.markers) scene.remove(place.markers);
  voxels.clear();
}

function regionFor(area) {
  if (!area.free) return area.region;
  const g = area.free_groups.find((f) => f.symbol === lessons.progress.freeSymbol) || area.free_groups[0];
  return g.region;
}

function go(id) {
  clearPlace();
  pending = null;
  if (id === "hall") {
    place = buildHall(voxels, data, lessons, () => openChat());
    place.billboard.set(billboard);
    built = new Map();
    ui.setPlace("Portal Hall", "Museum of Crystals and Symmetry · tier " + lessons.progress.tier);
    ui.setLegend(false);
  } else {
    const area = data.regions.find((r) => r.id === id);
    if (!area) return go("hall");
    const shown = area.free ? Object.assign({}, area, { region: regionFor(area), dots: freeGroup(area).dots }) : area;
    place = buildWorld(voxels, shown, lessons);
    built = new Map();
    for (const [x, y, z, c] of loadBuild(id)) { voxels.set(x, y, z, c); built.set(key(x, y, z), c); }
    ui.setPlace(area.name, (area.hidden ? "Symmetry hidden" : "Symmetry " + (area.free ? lessons.progress.freeSymbol : area.symbol)) + " · tier " + area.tier
      + (lessons.unlocked(area) ? "" : " · locked: building opens at tier " + area.tier));
    if (markersOn) scene.add(place.markers);
    ui.setLegend(markersOn);
    if (area.region.ground > 1) ui.toast("The build space floats above the ground: press K to fly, then Space to rise.");
    // Showcase blocks are offsets from the build space's corner (lessons.lua), so their height counts from its floor.
    if (TEST) for (const [x, y, z, c] of area.showcase.blocks || []) placeBlocks(x, place.region.ground + y, z, c, true);
  }
  for (const o of place.objects) scene.add(o);
  player.place(place.spawn, place.yaw);
  hint();
  if (!TEST && !lessons.progress.guided[guideId()]) {
    lessons.progress.guided[guideId()] = true;
    lessons.save();
    // On a first visit the start screen is still up: the guide waits for Play instead of covering it.
    if (start.hidden) showGuide(); else pendingGuide = true;
  }
}

function freeGroup(area) { return area.free_groups.find((f) => f.symbol === lessons.progress.freeSymbol) || area.free_groups[0]; }
const currentArea = () => (place && place.area) || data.gate;
const guideId = () => currentArea().id;

function hint() {
  const next = lessons.nextArea();
  if (!next) ui.setHint("explore any world, or take on the challenges in the Free Lab (press L there).");
  else if (next.id === data.gate.id) ui.setHint("in the Portal Hall, look at the Symmetry Gate's four displays and press Q to say which operation made each copy.");
  else ui.setHint("answer the quiz in " + next.name + " (press I and Go there, then Q).");
}

// ------------------------------------------------------------------ building

function placeBlocks(x, y, z, colour, quiet) {
  const r = place.region;
  const imgs = images(r, x, y, z);
  let n = 0;
  for (const [px, py, pz] of imgs) {
    if (player.occupies(px, py, pz) && !quiet) continue;
    voxels.set(px, py, pz, colour);
    built.set(key(px, py, pz), colour);
    n++;
  }
  if (!quiet) { ui.toast(n === 1 ? "1 block: it lies on every symmetry element." : n + " blocks: yours and " + (n - 1) + " cop" + (n === 2 ? "y" : "ies") + "."); store(); }
  return imgs.length;
}

function removeBlocks(x, y, z) {
  for (const [px, py, pz] of images(place.region, x, y, z)) {
    if (built.has(key(px, py, pz))) { voxels.remove(px, py, pz); built.delete(key(px, py, pz)); }
  }
  store();
}

let storeTimer = null;
function store() {
  clearTimeout(storeTimer);
  const id = place.id, blocks = [...built].map(([k, c]) => [...k.split(",").map(Number), c]);
  storeTimer = setTimeout(() => saveBuild(id, blocks), 400);
}

function target() {
  const eye = player.eye(), dir = player.look();
  const hit = voxels.raycast(eye, dir, REACH);
  // Signs, Prism and the billboard can be clicked too, when nearer than the block.
  const ray = new THREE.Raycaster(new THREE.Vector3(eye[0], eye[1], -eye[2]), new THREE.Vector3(dir[0], dir[1], -dir[2]), 0, REACH + 6);
  // A sprite (Prism) can only be hit with the camera known: it always faces the camera.
  ray.camera = camera;
  const meshes = (place.clickables || []).map((c) => c.mesh);
  const m = meshes.length ? ray.intersectObjects(meshes, false)[0] : null;
  if (m && (!hit || m.distance < hit.distance + 0.5)) return { clickable: place.clickables.find((c) => c.mesh === m.object) };
  return hit ? { hit } : null;
}

function punch() {
  const t = target();
  if (!t) return;
  if (t.clickable) return t.clickable.action();
  const { x, y, z } = t.hit;
  const portal = place.portals.get(key(x, y, z));
  if (portal) return go(portal);
  if (!place.area) return;
  if (!built.has(key(x, y, z))) return;
  if (!lessons.unlocked(place.area)) return ui.toast("Building here opens at tier " + place.area.tier + ".", "warn");
  removeBlocks(x, y, z);
}

function use() {
  const t = target();
  if (!t) return;
  if (t.clickable) return t.clickable.action();
  if (!place.area) return ui.toast("The museum is for looking: build in the worlds. Punch a portal on the north wall to travel.", "warn");
  const { x, y, z, normal } = t.hit;
  const p = [x + normal[0], y + normal[1], z + normal[2]];
  if (!inside(place.region, ...p)) return ui.toast("Build inside the coloured border: only there does the symmetry copy your blocks.", "warn");
  if (!lessons.unlocked(place.area)) return ui.toast("You can look around now. Building here opens at tier " + place.area.tier + ": answer the quiz questions of the places you have unlocked.", "warn");
  if (player.occupies(...p)) return;
  const colour = COLOURS[selected];
  if (!lessons.progress.predicted[place.id] && !place.area.hidden && !TEST) {
    pending = [...p, colour];
    pause();
    return ui.predict((n) => {
      lessons.progress.predicted[place.id] = true;
      lessons.save();
      const [px, py, pz, c] = pending;
      pending = null;
      ui.close();
      const real = placeBlocks(px, py, pz, c);
      ui.toast(n === real ? "You predicted " + n + ": exactly right!" : "You predicted " + n + "; there are " + real + ". " + (real === 1 ? "A block on a symmetry element is its own copy." : "Count the operations of the group."), n === real ? "right" : "warn");
    });
  }
  placeBlocks(...p, colour);
}

// ------------------------------------------------------------------ panels

function showGuide() {
  pause();
  const a = currentArea();
  const locked = place.area && !lessons.unlocked(a) ? "You can look around now. Building here opens at tier " + a.tier + ": answer the quiz questions of the places you have already unlocked." : null;
  ui.guide(a, a.guide, lessons, locked);
}

function showQuiz() {
  pause();
  const a = currentArea();
  const open = lessons.open(a);
  if (open.length) {
    const q = open[0];
    return ui.quiz(a.name + ": quiz", q, () => {
      const up = lessons.recordCorrect(q.id);
      hint();
      setTimeout(() => {
        if (up) { ui.close(); ui.toast("Tier " + lessons.progress.tier + " unlocked: " + data.tiers[String(lessons.progress.tier)] + "! New worlds are open for building.", "right"); go(place.id); }
        else if (lessons.open(a).length) showQuiz();
        else { ui.close(); ui.toast("You have answered every question here for your tier.", "right"); }
      }, 1800);
    });
  }
  if (lessons.progress.tier < (a.tier || 0)) { ui.close(); return ui.toast("This world's questions open at tier " + a.tier + ". " + document.getElementById("hint").textContent, "warn"); }
  const r = lessons.nextReview(a);
  if (!r) { ui.close(); return ui.toast("No questions here. " + document.getElementById("hint").textContent); }
  ui.quiz(a.name + ": review", r, () => {}, { review: true });
}

function showProgress() {
  pause();
  ui.progress(lessons, data, (id) => { ui.close(); go(id === data.gate.id ? "hall" : id); }, () => {
    if (confirm("Start again from tier 0? Your answers and predictions are forgotten (your builds stay).")) { lessons.reset(); ui.close(); go("hall"); }
  });
}

function showFreeLab() {
  if (!place.area || !place.area.free) return ui.toast("The Free Lab's controls work in the Free Lab (tier 4).");
  pause();
  const a = place.area;
  const ch = (a.challenges || [])[lessons.progress.challenge];
  ui.freeLab(a.free_groups, lessons.progress.freeSymbol, ch, (symbol) => {
    lessons.progress.freeSymbol = symbol;
    lessons.save();
    // Keep what was built; only the symmetry and its markers change.
    place.region = freeGroup(a).region;
    if (place.markers) scene.remove(place.markers);
    place.markers = markers(freeGroup(a).dots);
    if (markersOn) scene.add(place.markers);
    ui.setPlace(a.name, "Symmetry " + symbol + " · tier " + a.tier);
    ui.close();
    ui.toast("The Free Lab now has symmetry " + symbol + ". Blocks already in the lab were not changed.", "right");
  }, () => { ui.close(); whatSymmetry(); });
}

function whatSymmetry() {
  if (!place.area || !place.area.free) return ui.toast("What symmetry? works on builds in the Free Lab.");
  if (built.size === 0) return ui.toast("Build something in the lab first.", "warn");
  const d = detect(built, data.detect);
  const sym = d.entry ? d.entry.symbol : "?";
  const a = place.area;
  const ch = (a.challenges || [])[lessons.progress.challenge];
  let msg = "Your build has symmetry " + sym + (d.entry ? " (" + d.entry.system + ", " + d.ops.length + " operation" + (d.ops.length === 1 ? "" : "s") + ")." : ".");
  if (ch && sym === ch.target) { lessons.progress.challenge += 1; lessons.save(); msg += " Challenge complete!"; }
  else if (ch) msg += " The challenge asks for " + ch.target + ".";
  ui.toast(msg, ch && sym === ch.target ? "right" : "");
}

function openChat(q) { pause(); chat.open(q); }

// ------------------------------------------------------------------ input

const start = document.getElementById("start");
function pause() { if (document.pointerLockElement) document.exitPointerLock(); }
function resume() {
  if (busy()) return;
  start.classList.add("resume");
  start.hidden = false;
}
document.getElementById("play").addEventListener("click", () => {
  start.hidden = true;
  if (pendingGuide) { pendingGuide = false; showGuide(); } else canvas.requestPointerLock();
});
canvas.addEventListener("click", () => { if (!busy() && !document.pointerLockElement) { start.hidden = true; canvas.requestPointerLock(); } });
document.addEventListener("pointerlockchange", () => { if (!document.pointerLockElement && !busy()) resume(); });
document.addEventListener("mousemove", (e) => { if (document.pointerLockElement === canvas) player.turn(e.movementX, e.movementY); });
canvas.addEventListener("mousedown", (e) => {
  if (document.pointerLockElement !== canvas) return;
  if (e.button === 0) punch(); else if (e.button === 2) use();
});
canvas.addEventListener("contextmenu", (e) => e.preventDefault());
addEventListener("wheel", (e) => {
  if (document.pointerLockElement !== canvas) return;
  selected = (selected + (e.deltaY > 0 ? 1 : COLOURS.length - 1)) % 8;
  ui.hotbar(COLOURS.slice(0, 8), selected);
});
addEventListener("keydown", (e) => {
  if (e.key === "Escape") { if (chat.isOpen()) chat.close(); else if (ui.isOpen()) ui.close(); return; }
  if (busy()) return;
  keys[e.code] = true;
  const k = e.code;
  if (k.startsWith("Digit")) { const n = Number(k.slice(5)); if (n >= 1 && n <= 8) { selected = n - 1; ui.hotbar(COLOURS.slice(0, 8), selected); } }
  else if (k === "KeyK") { player.flying = !player.flying; ui.toast(player.flying ? "Flying: Space to rise, Shift to sink. K again to land." : "Walking."); }
  else if (k === "KeyJ") { player.fast = !player.fast; ui.toast(player.fast ? "Fast." : "Normal speed."); }
  else if (k === "KeyG") showGuide();
  else if (k === "KeyQ") showQuiz();
  else if (k === "KeyI" || k === "Tab") { e.preventDefault(); showProgress(); }
  else if (k === "KeyP" || k === "Slash") { e.preventDefault(); openChat(); }
  else if (k === "KeyH") go("hall");
  else if (k === "KeyM") { markersOn = !markersOn; if (place.markers) (markersOn ? scene.add(place.markers) : scene.remove(place.markers)); ui.setLegend(markersOn && !!place.area); }
  else if (k === "KeyL") showFreeLab();
  else if (k === "KeyX") whatSymmetry();
});
addEventListener("keyup", (e) => { keys[e.code] = false; });
addEventListener("blur", () => { for (const k in keys) keys[k] = false; });
document.querySelectorAll("[data-action]").forEach((b) => b.addEventListener("click", () => {
  ({ guide: showGuide, quiz: showQuiz, progress: showProgress, prism: () => openChat(), hall: () => go("hall"), lab: showFreeLab })[b.dataset.action]();
}));

// ------------------------------------------------------------------ loop

let last = performance.now();
let factTimer = 0;
let reported = false;
// The next frame is asked for first, so that an error in one frame (reported once, in the console and on screen) never stops the game.
function frame(now) {
  requestAnimationFrame(frame);
  try { step(now); } catch (e) {
    if (!reported) { reported = true; console.error(e); ui.toast("Something went wrong: " + e.message + ". Reloading the page may help.", "warn"); }
  }
}
function step(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (document.pointerLockElement === canvas && !busy()) player.update(dt, keys, voxels);
  if (player.pos[1] < -30) player.place(place.spawn, place.yaw);
  const eye = player.eye(), dir = player.look();
  camera.position.set(eye[0], eye[1], -eye[2]);
  camera.lookAt(eye[0] + dir[0], eye[1] + dir[1], -(eye[2] + dir[2]));
  const t = place && document.pointerLockElement ? target() : null;
  cursor.visible = !!(t && t.hit && t.hit.kind !== "ground");
  if (cursor.visible) cursor.position.set(t.hit.x, t.hit.y, -t.hit.z);
  for (const o of place.objects) if (o.userData.bob) o.position.y = 4.4 + Math.sin(now / 700) * 0.18;
  // Between conversations the billboard shows the words to know, one every 20 seconds; an answer stays up for five minutes.
  factTimer += dt;
  if (factTimer > 20 && (billboard.mode === "idle" || (billboard.mode === "answer" && Date.now() - billboard.at > 300000))) {
    factTimer = 0;
    factIndex = (factIndex + 1) % data.glossary.length;
    setBoard({ mode: "idle", fact: data.glossary[factIndex] });
  }
  renderer.render(scene, camera);
}

ui.hotbar(COLOURS.slice(0, 8), selected);
go(params.get("world") || "hall");
if (TEST) {
  if (params.get("start") !== "1") start.hidden = true;
  if (params.get("yaw")) player.yaw = Number(params.get("yaw"));
  if (params.get("pos")) { const p = params.get("pos").split(",").map(Number); player.pos = p; }
  if (params.get("pitch")) player.pitch = Number(params.get("pitch"));
  if (params.get("panel") === "guide") showGuide();
  if (params.get("panel") === "chat") openChat(params.get("ask") || undefined);
  if (params.get("panel") === "quiz") { lessons.progress.tier = Number(params.get("tier") || 0); showQuiz(); }
  if (params.get("panel") === "progress") showProgress();
  if (params.get("panel") === "lab") showFreeLab();
}
requestAnimationFrame(frame);
if (TEST && params.get("debug") === "target") setTimeout(() => {
  try { target(); document.title = "target ok"; } catch (e) { document.title = "target error: " + e.message; }
}, 2000);
if (TEST && params.get("debug") === "1") setTimeout(() => {
  const b = place.billboard && place.billboard.mesh;
  document.title = JSON.stringify(b ? { inScene: b.parent === scene, pos: b.position.toArray(), rot: b.rotation.y, w: b.geometry.parameters.width, h: b.geometry.parameters.height, mapW: b.material.map.image.width } : { none: true });
}, 2000);
window.crystalminer = { data, lessons, player, go, voxels };
