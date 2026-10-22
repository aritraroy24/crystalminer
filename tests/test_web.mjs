// Checks the web version against the game's Lua engine: web/js/symmetry.js must make exactly the copies and detect exactly the symmetries that mods/crystalminer/symmetry.lua does, and web/data/crystalminer.json must be up to date with content.lua. Run from the repository root: node tests/test_web.mjs (needs luajit or lua5.1).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { images, detect } from "../web/js/symmetry.js";

let passed = 0, failed = 0;
function run(name, fn) {
  try { fn(); passed++; console.log("  ok    " + name); }
  catch (e) { failed++; console.log("  FAIL  " + name + "\n        " + e.message); }
}
function eq(a, b, msg) { if (a !== b) throw new Error((msg || "") + ": expected " + b + ", got " + a); }

function lua(args) {
  for (const bin of ["luajit", "lua5.1"]) {
    try { return execFileSync(bin, args, { encoding: "utf8", maxBuffer: 64 << 20 }); } catch (e) { if (e.code !== "ENOENT") throw e; }
  }
  throw new Error("luajit or lua5.1 is needed");
}

console.log("web");
const data = JSON.parse(readFileSync("web/data/crystalminer.json", "utf8"));
const ref = JSON.parse(lua(["tests/web_vectors.lua"]));
const byId = new Map(data.regions.map((r) => [r.id, r]));

run("every world copies blocks exactly as the Lua engine does", () => {
  for (const c of ref.images) {
    const r = byId.get(c.id).region;
    const got = images(r, ...c.at).map((p) => p.join(",")).sort();
    eq(got.join(" "), c.images.join(" "), c.id + " at " + c.at);
  }
});

run("/whatsymmetry finds the same point group as the Lua engine", () => {
  for (const c of ref.detect) {
    const blocks = new Map(c.blocks.map((e) => { const [k, v] = e.split("="); return [k, v]; }));
    const d = detect(blocks, data.detect);
    eq(d.entry ? d.entry.symbol : "?", c.symbol, c.blocks.join(" "));
    eq(d.ops.length, c.order, c.blocks.join(" "));
  }
});

run("every Free Lab group copies a block into as many places as its order (or fewer, on an element)", () => {
  const lab = byId.get("free_lab");
  for (const g of lab.free_groups) {
    const n = images(g.region, 3, g.region.ground + 2, 7).length;
    if (n < 1 || n > g.region.ops.length) throw new Error(g.symbol + ": " + n);
  }
});

run("the exported data is up to date (run luajit tools/export_web.lua after changing content.lua)", () => {
  const before = readFileSync("web/data/crystalminer.json", "utf8");
  const prompt = readFileSync("web/api/prompt.txt", "utf8");
  lua(["tools/export_web.lua"]);
  eq(readFileSync("web/data/crystalminer.json", "utf8") === before, true, "web/data/crystalminer.json changed");
  eq(readFileSync("web/api/prompt.txt", "utf8") === prompt, true, "web/api/prompt.txt changed");
});

// The symbol is named in the catalogue of all 32 point groups like any other, and its quiz has to carry the answer, as every quiz in the browser does; what must not happen is the world itself saying it.
run("the Mystery Lab does not say its symmetry, apart from its quiz", () => {
  const lab = byId.get("mystery_lab");
  eq(lab.symbol, "?");
  const hidden = lua(["-e", 'package.path="mods/crystalminer/?.lua;"..package.path; for _, a in ipairs(require("content").regions) do if a.hidden then io.write(a.hidden) end end']).trim();
  eq(hidden.length > 0, true, "the Mystery Lab has a hidden symbol in content.lua");
  const { quiz, ...rest } = lab;
  eq(JSON.stringify(rest).includes('"' + hidden + '"'), false, "the Mystery Lab names " + hidden);
});

// The browser's lessons follow the game's rules (lessons.lua). There is no localStorage in Node, so progress lasts the test only.
const { Lessons } = await import("../web/js/lessons.js");

run("answering every tier-0 question opens tier 1, and tiers stop at the top", () => {
  const L = new Lessons(data);
  eq(L.progress.tier, 0);
  const gate = L.area("symmetry_gate");
  eq(L.unlocked(L.area("mirror_plaza")), false, "Mirror Plaza is locked at tier 0");
  const qs = L.open(gate);
  eq(qs.length > 0, true, "the Gate has questions at tier 0");
  let up = false;
  for (const q of L.questionsForTier(0)) up = L.recordCorrect(q.id) || up;
  eq(up, true, "the last answer raised the tier");
  eq(L.progress.tier, 1);
  eq(L.unlocked(L.area("mirror_plaza")), true, "Mirror Plaza opens at tier 1");
  for (let t = 1; t <= L.maxTier; t++) for (const q of L.questionsForTier(L.progress.tier)) L.recordCorrect(q.id);
  eq(L.progress.tier, L.maxTier);
  eq(L.nextArea(), null, "nothing is left at the top tier");
});

run("review questions never come from above the player's tier, and cycle", () => {
  const L = new Lessons(data);
  L.progress.tier = 1;
  const plaza = L.area("mirror_plaza");
  const qs = L.reviewQuestions(plaza);
  eq(qs.length > 0, true);
  for (const q of qs) eq(Number(q.id.split(".")[1]) <= 1, true, q.id);
  const first = L.nextReview(plaza).id;
  for (let i = 1; i < qs.length; i++) L.nextReview(plaza);
  eq(L.nextReview(plaza).id, first, "the review wraps round");
  eq(L.nextReview(L.area("screw_hall")), null, "a tier-4 world has nothing to review at tier 1");
});

run("every quiz answer points at one of its options", () => {
  for (const a of [data.gate, ...data.regions])
    for (const [t, qs] of Object.entries(a.quiz || {}))
      for (const q of qs) eq(Number.isInteger(q.answer) && q.answer >= 0 && q.answer < q.options.length, true, a.id + " tier " + t + ": " + q.q);
});

// Movement, with a stand-in for voxels.js: the ground everywhere (y <= 0) and the blocks in `walls`.
const { Player } = await import("../web/js/player.js");
function world(walls = []) {
  const set = new Set(walls.map((p) => p.join(",")));
  return { solid: (x, y, z) => y <= 0 || set.has([x, y, z].join(",")) };
}
function simulate(p, keys, seconds, w) { for (let t = 0; t < seconds; t += 1 / 60) p.update(1 / 60, keys, w); }

run("walking: W goes the way the player faces, on the ground, at walking speed", () => {
  const p = new Player();
  p.place([0, 1, 6], Math.PI);        // facing south, as in the Portal Hall
  simulate(p, { KeyW: true }, 1, world());
  eq(Math.abs(p.pos[1] - 0.5) < 1e-9, true, "stays on the ground (y " + p.pos[1] + ")");
  eq(p.pos[2] < 6 - 4 && p.pos[2] > 6 - 5, true, "moved about 4.4 south (z " + p.pos[2].toFixed(2) + ")");
  eq(Math.abs(p.pos[0]) < 1e-6, true, "did not drift sideways");
  const q = new Player();
  q.place([0, 1, 0], 0);
  simulate(q, { KeyD: true }, 1, world());
  eq(q.pos[0] > 4, true, "D goes east when facing north (x " + q.pos[0].toFixed(2) + ")");
});

run("the mouse turns the player, and looking up is limited", () => {
  const p = new Player();
  p.turn(-628, 0);                   // mouse to the left turns left, by 1.57 rad
  eq(Math.abs(p.yaw - 1.57) < 1e-9, true, "yaw " + p.yaw);
  p.turn(0, -100000);
  eq(p.pitch <= 1.55 && p.pitch > 1.5, true, "pitch " + p.pitch);
});

run("walls stop the player, jumping and flying lift it", () => {
  const wall = [];
  for (let x = -3; x <= 3; x++) for (let y = 1; y <= 3; y++) wall.push([x, y, 3]);
  const p = new Player();
  p.place([0, 1, 0], 0);
  simulate(p, { KeyW: true }, 2, world(wall));
  eq(p.pos[2] < 2.5 && p.pos[2] > 2, true, "stopped at the wall (z " + p.pos[2].toFixed(2) + ")");
  const j = new Player();
  j.place([0, 1, 0], 0);
  let top = 0;
  for (let t = 0; t < 1; t += 1 / 60) { j.update(1 / 60, { Space: true }, world()); top = Math.max(top, j.pos[1]); }
  eq(top > 1.5, true, "jumped (top " + top.toFixed(2) + ")");
  const f = new Player();
  f.place([0, 1, 0], 0);
  f.flying = true;
  simulate(f, { Space: true }, 1, world());
  eq(f.pos[1] > 7, true, "flew up (y " + f.pos[1].toFixed(2) + ")");
});

console.log(passed + " passed, " + failed + " failed");
if (failed > 0) process.exit(1);
