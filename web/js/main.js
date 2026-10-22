// crystalminer in the browser: the Museum of Crystals and Symmetry as the game builds it (data/museum.json, recorded by tools/export_museum.sh) and the symmetry worlds, with three.js, from data/crystalminer.json (made by tools/export_web.lua from the game's own engine and texts).
import * as THREE from "three";
import { Voxels, COLOURS, key } from "./voxels.js";
import { Player } from "./player.js";
import { Lessons, loadBuild, saveBuild } from "./lessons.js";
import { buildWorld, markers } from "./worlds.js";
import { Museum } from "./museum.js";
import { liveOn, loadStructure, noticeLines, noticeSuccess, noticeFailure, NOTICE } from "./exhibit_fetch.js";
import { inBox, applyLever, verdict } from "./pad.js";
import { images, inside, detect } from "./symmetry.js";
import { UI } from "./ui.js";
import { Chat } from "./chat.js";

const params = new URLSearchParams(location.search);
// ?test=1 is for automated screenshots: no start screen, every world open (not saved), the world's showcase built. ?world=<id> starts in a world, an exhibit room or a place in the museum.
const TEST = params.get("test") === "1";
const REACH = 7;
const CM = "crystalminer:";

const [data, dump] = await Promise.all([fetch("data/crystalminer.json").then((r) => r.json()), fetch("data/museum.json").then((r) => r.json())]);
const lessons = new Lessons(data);
if (TEST) { lessons.save = () => {}; lessons.progress.tier = 4; }
lessons.progress.discoveries = lessons.progress.discoveries || {};
const museum = new Museum(dump, data);

// ------------------------------------------------------------------ three.js

const canvas = document.getElementById("view");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: TEST });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
const scene = new THREE.Scene();
scene.background = new THREE.Color("#8FC9F0");
scene.fog = new THREE.Fog("#8FC9F0", 80, 260);
const camera = new THREE.PerspectiveCamera(72, 1, 0.05, 700);
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

let place = null;              // the current place: the museum, or a world (worlds.js)
let built = new Map();         // blocks the player built in the current world: "x,y,z" -> colour
const padBlocks = new Map();   // the shape in the Try-it Pad's build box: "x,y,z" -> colour (kept while the page is open)
const padCopy = new Map();     // the copy in its result box
let room = null;               // the museum room or exhibit room the player is in
let selected = 0;
let markersOn = true;
let pending = null;            // a first block waiting for its prediction
let pendingGuide = false;      // a guide to show once the start screen is closed
let billboard = { mode: "idle", fact: data.glossary[0] };
let factIndex = 0;
const keys = {};

const ui = new UI({ onClose: () => resume() });
const chat = new Chat(data.tutor, {
  context: () => ({ tier: lessons.progress.tier, place: placeName(), inWorld: !!(place && place.area) }),
  onClose: () => resume(),
  onAsked: (q) => setBoard({ mode: "thinking", q }),
  onAnswered: (q, a) => setBoard({ mode: "answer", q, a, at: Date.now() }),
  onFailed: () => setBoard({ mode: "idle", fact: data.glossary[factIndex] }),
});

function setBoard(s) {
  billboard = s;
  museum.billboard && museum.billboard.set(s);
}

const busy = () => ui.isOpen() || chat.isOpen();
const placeName = () => (place && place.area ? place.name : room ? room.name : "the Museum of Crystals and Symmetry");

// ------------------------------------------------------------------ places

function clearPlace() {
  if (!place) return;
  for (const o of place.objects) scene.remove(o);
  if (place.markers) scene.remove(place.markers);
  voxels.clear();
}

function regionFor(area) {
  if (!area.free) return area.region;
  return freeGroup(area).region;
}
function freeGroup(area) { return area.free_groups.find((f) => f.symbol === lessons.progress.freeSymbol) || area.free_groups[0]; }

// Where a teleport into the museum lands (lobby.lua and exhibits.lua on_teleport): the foyer, the Portal Hall, the Gate, the Try-it Pad, an exhibit room.
function museumArrival(id) {
  if (id === "portal_hall") return { pos: dump.portal_hall.pos, yaw: 0 };
  if (id === "symmetry_gate") return { pos: [0, 1, -12], yaw: Math.PI };
  if (id === "tryit_pad") return { pos: [dump.pad.result.x + 6, 1, dump.pad.levers[0].z + 2], yaw: Math.PI };
  const r = museum.room(id);
  if (r) return { pos: museum.arrival(r), yaw: 0, exhibit: r };
  return { pos: dump.spawn.pos, yaw: 0 };
}

// The crystal-exhibit rooms, as exhibit_dynamic.lua runs them. Punching an exhibit's portal starts a search for a new random structure from the Materials Project (through api/mp.php, when the site has a key), with the game's loading notice; the player enters when it is ready, or with the next built-in structure if none is found. Without a key the room shows the built-in structures in turn.
// ?test=1 leaves live structures off unless &live=1; a site that refuses (its hourly or daily limit) is not asked again while the page is open.
let live = TEST && params.get("live") !== "1" ? Promise.resolve(false) : liveOn();
let loadingRoom = null, lastEntry = -10, notice = null;
const clock = () => performance.now() / 1000;

function showNotice() {
  if (!notice) return ui.notice(null);
  const t = clock() - notice.started;
  if (notice.finished && t >= notice.removeAt) { notice = null; return ui.notice(null); }
  ui.notice(...(notice.finished ? (notice.ok ? noticeSuccess(notice.structure, notice.room) : noticeFailure(notice.reason)) : noticeLines(notice.stage, t, notice.detail)));
}
setInterval(showNotice, 1000);
function finishNotice(ok, structure, reason) {
  Object.assign(notice, { finished: true, ok, structure, reason, removeAt: clock() - notice.started + (ok ? NOTICE.SUCCESS_SECONDS : NOTICE.FAILURE_SECONDS) });
  showNotice();
}

async function visitExhibit(r) {
  if (loadingRoom) return ui.toast(loadingRoom === r.id ? "This exhibit is loading; you will enter when it is ready." : "Please try again in a moment.");
  if (clock() - lastEntry < 2) return ui.toast("Please try again in a moment.");
  lastEntry = clock();
  museum.startLoad(r);
  if (!(await live)) { museum.showExhibit(r, museum.fallbackFor(r)); return go(r.id); }
  loadingRoom = r.id;
  ui.toast("Loading a random crystal structure...");
  notice = { room: r.number, stage: "searching", started: clock() };
  showNotice();
  const got = await loadStructure({ elements: data.museum.elements, excluded: museum.exclusions(r), shown: museum.shownMd5(),
    onStage: (stage, detail) => { Object.assign(notice, { stage, detail }); showNotice(); } });
  loadingRoom = null;
  if (got.stop) live = Promise.resolve(false);
  if (got.structure) {
    museum.showExhibit(r, got.structure);
    finishNotice(true, got.structure.name);
  } else {
    console.info("crystalminer exhibits:", got.error);
    const s = museum.fallbackFor(r), why = got.stop ? got.error : "Could not load a new structure";
    museum.showExhibit(r, s);
    ui.toast(why + "; showing " + s.name + ".", "warn");
    finishNotice(false, null, why + "; showing " + s.name);
  }
  go(r.id);
}

// Arriving in an exhibit room: what it shows (the next built-in structure if it has never shown one).
function enterExhibit(r) {
  const s = museum.exhibitShown.get(r.id) || museum.fallbackFor(r);
  museum.showExhibit(r, s);
  ui.toast("Crystal exhibit " + r.number + ": " + s.name + ", a real structure from the Materials Project (MPContribs).");
}

function go(id) {
  clearPlace();
  pending = null;
  room = null;
  const region = data.regions.find((r) => r.id === id);
  if (!region) {
    museum.build(() => openChat());
    for (const v of museum.npcs) v.say = (msg) => ui.toast("Visitor: " + msg);
    museum.fill(voxels);
    for (const [k, c] of [...padBlocks, ...padCopy]) voxels.set(...k.split(",").map(Number), c);
    const at = museumArrival(id);
    place = { id: "museum", name: "Museum of Crystals and Symmetry", spawn: at.pos, yaw: at.yaw, objects: [museum.group], clickables: museum.clickables };
    museum.billboard.set(billboard);
    if (at.exhibit) enterExhibit(at.exhibit);
    ui.setLegend(false);
    built = new Map();
  } else {
    const area = region;
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
  updateRoom(true);
  hint();
  if (place.area) firstGuide(place.area.id);
}

// The guide to a place, the first time a player is there (guide_window.lua); it waits for the start screen.
function firstGuide(id) {
  if (TEST || lessons.progress.guided[id] || !guideFor(id)) return;
  lessons.progress.guided[id] = true;
  lessons.save();
  if (start.hidden && !busy()) showGuide(); else pendingGuide = true;
}

// The room the player is in, from the museum's room bounds and the exhibit rooms; updates the HUD.
function roomAt(p) {
  for (const r of dump.rooms) if (p[0] >= r.min[0] - 0.5 && p[0] <= r.max[0] + 0.5 && p[2] >= r.min[1] - 0.5 && p[2] <= r.max[1] + 0.5) return r;
  for (const r of dump.exhibit_rooms || []) {
    if (p[0] >= r.min[0] && p[0] < r.min[0] + r.size[0] && p[2] >= r.min[2] && p[2] < r.min[2] + r.size[2]) {
      const shown = museum.exhibitShown.get(r.id);
      return { id: r.id, name: "Crystal exhibit " + r.number + (shown ? ": " + shown.name : ""), exhibit: true };
    }
  }
  return null;
}

function updateRoom(force) {
  if (!place || place.area) return;
  const r = roomAt(player.pos);
  if (!force && (r && room && r.id === room.id || !r && !room)) return;
  room = r;
  ui.setPlace(r ? r.name : "Museum of Crystals and Symmetry", "Museum of Crystals and Symmetry · tier " + lessons.progress.tier);
  if (r && (r.id === "gallery1" || r.id === "workshop")) firstGuide(r.id === "gallery1" ? data.gate.id : "tryit_pad");
}

// What G and Q are about here: a world, the Symmetry Gate in Gallery 1, the Try-it Pad in the Workshop, else the museum.
function guideFor(id) {
  if (id === data.gate.id) return data.gate;
  if (id === "tryit_pad") return { id: "tryit_pad", name: "The Try-it Pad", guide: data.museum.guides.tryit_pad };
  return data.regions.find((r) => r.id === id) || null;
}
function currentArea() {
  if (place && place.area) return place.area;
  if (room && room.id === "workshop") return guideFor("tryit_pad");
  return data.gate;
}

function hint() {
  const next = lessons.nextArea();
  if (!next) ui.setHint("explore any world, or take on the challenges in the Free Lab (press L there).");
  else if (next.id === data.gate.id) ui.setHint("go north from the foyer into Gallery 1, look at the Symmetry Gate's four displays and press Q to say which operation made each copy.");
  else ui.setHint("answer the quiz in " + next.name + " (its portal is in the Portal Hall; or press I and Go there, then Q).");
}

// ------------------------------------------------------------------ building in the worlds

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
  // Signs, the billboard and the NPCs can be clicked too, when nearer than the block.
  const ray = new THREE.Raycaster(new THREE.Vector3(eye[0], eye[1], -eye[2]), new THREE.Vector3(dir[0], dir[1], -dir[2]), 0, REACH + 6);
  ray.camera = camera;   // sprites can only be hit with the camera known
  const meshes = (place.clickables || []).map((c) => c.mesh);
  const m = meshes.length ? ray.intersectObjects(meshes, false)[0] : null;
  if (m && (!hit || m.distance < hit.distance + 0.5)) return { clickable: place.clickables.find((c) => c.mesh === m.object) };
  return hit ? { hit } : null;
}

// What a museum block does when punched or right-clicked; true if it did something.
function museumUse(hit) {
  const { x, y, z } = hit;
  const name = voxels.get(x, y, z) || "";
  const meta = museum.meta.get(key(x, y, z));
  if (name.startsWith(CM + "door_")) { museum.toggleDoor(x, y, z, voxels); return true; }
  // A portal: a world, an exhibit room, or back to the Portal Hall.
  if (meta && meta.target) { const r = museum.room(meta.target); if (r) visitExhibit(r); else go(meta.target); return true; }
  if (meta && meta.exhibit) { clue(meta.exhibit); return true; }
  if (name.startsWith(CM + "lever_")) { lever(dump.pad.levers.find((l) => CM + "lever_" + l.letter === name)); return true; }
  if (name === CM + "tutor_screen" || name === CM + "tutor_prism") { openChat(); return true; }
  return false;
}

function punch() {
  const t = target();
  if (!t) return;
  if (t.clickable) return t.clickable.action();
  const { x, y, z } = t.hit;
  if (!place.area) {
    if (museumUse(t.hit)) return;
    const k = key(x, y, z);
    if (padBlocks.has(k)) { padBlocks.delete(k); voxels.remove(x, y, z); }
    return;
  }
  const portal = place.portals.get(key(x, y, z));
  if (portal) return go(portal);
  if (!built.has(key(x, y, z))) return;
  if (!lessons.unlocked(place.area)) return ui.toast("Building here opens at tier " + place.area.tier + ".", "warn");
  removeBlocks(x, y, z);
}

function use() {
  const t = target();
  if (!t) return;
  if (t.clickable) return t.clickable.action();
  const { x, y, z, normal } = t.hit;
  const p = [x + normal[0], y + normal[1], z + normal[2]];
  if (!place.area) {
    if (museumUse(t.hit)) return;
    // In the museum, only the Try-it Pad's build box takes blocks (lobby.lua: the museum is for looking).
    if (inBox(p, dump.pad.build)) {
      if (player.occupies(...p) || voxels.get(...p)) return;
      padBlocks.set(key(...p), COLOURS[selected]);
      voxels.set(...p, COLOURS[selected]);
      return;
    }
    return ui.toast("The museum is for looking: build in the Workshop's Try-it Pad, or in the worlds of the Portal Hall.", "warn");
  }
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

// ------------------------------------------------------------------ the museum's exhibits

// A clue crystal in Gallery 3 asks about its model (museum.lua); a right answer is a discovery.
function clue(id) {
  const c = data.museum.clues[id];
  if (!c) return;
  pause();
  ui.quiz("Clue crystal: " + c.name, { q: c.q, options: c.options, answer: c.answer, why: c.why, hint: "Count the neighbours of one atom in the model: fly round it and look along its rows." }, () => {
    const d = lessons.progress.discoveries;
    const fresh = !d[id];
    d[id] = true;
    lessons.save();
    if (fresh) {
      const n = Object.keys(d).length, total = Object.keys(data.museum.clues).length;
      setTimeout(() => ui.toast("Discovery! Clue crystals solved: " + n + " of " + total + ".", "right"), 300);
    }
  });
}

// A lever of the Try-it Pad: guess first, then the copy appears (init.lua's prediction form).
function lever(l) {
  if (!l) return;
  if (padBlocks.size === 0) return ui.toast("First build a shape in the glass box on the left, marked YOUR SHAPE: pick a block with keys 1 to 8 and right-click inside the box. Then punch a lever again.", "warn");
  pause();
  const answer = (predicted) => {
    ui.close();
    for (const k of padCopy.keys()) voxels.remove(...k.split(",").map(Number));
    padCopy.clear();
    const r = applyLever(l, padBlocks, { build: dump.pad.build, result: dump.pad.result, detect: data.detect });
    for (const [x, y, z, c] of r.copy) { padCopy.set(key(x, y, z), c); voxels.set(x, y, z, c); }
    ui.toast(verdict(l, predicted, r.matches), predicted === r.matches ? "right" : "warn");
  };
  ui.choose("Lever " + l.letter + ": " + l.text.replace(/^\w: /, ""),
    "Lever " + l.letter + " " + l.does + ". The copy will appear in the box on the right, marked COPY.\n\nGuess first: if you could pick the copy up and turn it any way you like, could you make it look exactly like your shape?",
    [["Yes, I could turn it to match", () => answer(true)], ["No, it could never match", () => answer(false)]]);
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
  const a = place.area || data.gate;
  const open = lessons.open(a);
  if (open.length) {
    const q = open[0];
    return ui.quiz(a.name + ": quiz", q, () => {
      const up = lessons.recordCorrect(q.id);
      hint();
      setTimeout(() => {
        if (up) { ui.close(); ui.toast("Tier " + lessons.progress.tier + " unlocked: " + data.tiers[String(lessons.progress.tier)] + "! New worlds are open for building in the Portal Hall.", "right"); if (place.area) go(place.id); }
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
  ui.progress(lessons, data, (id) => { ui.close(); go(id); }, () => {
    if (confirm("Start again from tier 0? Your answers and predictions are forgotten (your builds stay).")) { lessons.reset(); lessons.progress.discoveries = {}; ui.close(); go("foyer"); }
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
function paused() {
  start.classList.add("resume");
  start.hidden = false;
}
// After a panel closes, straight back into the game: browsers allow taking the mouse again during a click (a panel's button), not after Esc, which shows the pause screen instead.
function resume() {
  if (busy()) return;
  if (pendingGuide) { pendingGuide = false; return showGuide(); }
  if (TEST) return;
  try {
    const r = canvas.requestPointerLock();
    if (r && r.catch) r.catch(paused);
  } catch { paused(); }
}
document.addEventListener("pointerlockerror", () => { if (!busy()) paused(); });
document.getElementById("play").addEventListener("click", () => {
  start.hidden = true;
  if (pendingGuide) { pendingGuide = false; showGuide(); } else canvas.requestPointerLock();
});
canvas.addEventListener("click", () => { if (!busy() && !document.pointerLockElement) { start.hidden = true; canvas.requestPointerLock(); } });
// Losing the mouse (Esc, or leaving the window) pauses.
document.addEventListener("pointerlockchange", () => { if (!document.pointerLockElement && !busy()) paused(); else if (document.pointerLockElement) start.hidden = true; });
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
  else if (k === "KeyH") go("portal_hall");
  else if (k === "KeyM") { markersOn = !markersOn; if (place.markers) (markersOn ? scene.add(place.markers) : scene.remove(place.markers)); ui.setLegend(markersOn && !!place.area); }
  else if (k === "KeyL") showFreeLab();
  else if (k === "KeyX") whatSymmetry();
});
addEventListener("keyup", (e) => { keys[e.code] = false; });
addEventListener("blur", () => { for (const k in keys) keys[k] = false; });
document.querySelectorAll("[data-action]").forEach((b) => b.addEventListener("click", () => {
  ({ guide: showGuide, quiz: showQuiz, progress: showProgress, prism: () => openChat(), hall: () => go("portal_hall"), lab: showFreeLab })[b.dataset.action]();
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
  if (!place.area) { museum.updateNpcs(dt, now); museum.holograms.update(dt, player.pos); updateRoom(false); }
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
go(params.get("world") || "foyer");
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
  if (params.get("panel") === "clue") clue(params.get("id") || "copper");
  if (params.get("panel") === "lever") {
    // A lopsided shape in the build box, then lever M, answered "No" by the test.
    const B = dump.pad.build;
    for (const [dx, dy, dz] of [[0, 0, 0], [1, 0, 0], [2, 0, 0], [2, 0, 1], [0, 1, 0], [0, 2, 0]]) { const k = key(B.x + 1 + dx, B.y + dy, B.z + 1 + dz); padBlocks.set(k, "red"); voxels.set(B.x + 1 + dx, B.y + dy, B.z + 1 + dz, "red"); }
    lever(dump.pad.levers.find((l) => l.letter === params.get("letter") || l.letter === "M"));
    if (params.get("answer")) setTimeout(() => document.querySelectorAll(".options button")[params.get("answer") === "yes" ? 0 : 1].click(), 500);
  }
}
// ?fill=1: every exhibit room shows its next built-in structure (Gallery 2's holograms all filled); ?visit=exhibit_<n>: punch that exhibit's portal.
if (TEST && params.get("fill") === "1") for (const r of dump.exhibit_rooms) museum.showExhibit(r, museum.fallbackFor(r));
if (TEST && params.get("visit")) setTimeout(() => visitExhibit(museum.room(params.get("visit"))), 300);
if (TEST && params.get("debug") === "door") setTimeout(() => {
  // The front door (lobby.lua: x -1 and 0 on the south wall), punched once.
  const before = voxels.get(-1, 1, -50) + "/" + voxels.get(-1, 2, -50);
  museumUse({ x: -1, y: 1, z: -50 });
  const after = voxels.get(-1, 1, -50) + "/" + voxels.get(-1, 2, -50);
  const blocked = (z) => player.blocked([-1, 0.5, z], voxels);
  document.title = "door " + before + " -> " + after + "; can walk through: " + !blocked(-50);
}, 3000);
requestAnimationFrame(frame);
if (TEST && params.get("debug") === "target") setTimeout(() => {
  try { target(); document.title = "target ok"; } catch (e) { document.title = "target error: " + e.message; }
}, 2000);
if (TEST && params.get("debug") === "nan") setTimeout(() => {
  const bad = [];
  scene.traverse((o) => {
    const a = o.geometry && o.geometry.attributes.position;
    if (a && a.array.some((v) => Number.isNaN(v))) bad.push(o.type + ":" + (Array.isArray(o.material) ? o.material[0].map?.image?.src || "" : o.material.map?.image?.src || "").split("/").pop());
  });
  document.title = "nan: " + bad.length + " " + bad.slice(0, 8).join(" ");
}, 4000);
window.crystalminer = { data, dump, lessons, player, go, voxels, museum };
