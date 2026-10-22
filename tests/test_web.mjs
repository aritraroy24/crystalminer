// Checks the web version against the game's Lua engine: web/js/symmetry.js must make exactly the copies and detect exactly the symmetries that mods/crystalminer/symmetry.lua does, and web/data/crystalminer.json must be up to date with content.lua. Run from the repository root: node tests/test_web.mjs (needs luajit or lua5.1).
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
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

// The museum as the game builds it (web/data/museum.json, from tools/export_museum.sh).
const museum = JSON.parse(readFileSync("web/data/museum.json", "utf8"));
const blockAt = new Map();
for (let i = 0; i < museum.nodes.length; i += 5) blockAt.set(museum.nodes.slice(i, i + 3).join(","), museum.palette[museum.nodes[i + 3]]);

run("the museum: a clean build, players start on the foyer floor, every room is there", () => {
  eq(museum.checks.missing + museum.checks.emerge_late + museum.checks.emerge_gave_up, 0, "map blocks missing or written late");
  const [x, y, z] = museum.spawn.pos;
  eq(blockAt.has([x, y - 1, z].join(",")), true, "a floor under the spawn");
  // The foyer's red carpet runs through the spawn: a slab a sixteenth high, stood on, not in the way.
  const at = blockAt.get([x, y, z].join(","));
  eq(!at || at === "crystalminer:carpet", true, "room to stand at the spawn (" + at + ")");
  eq(blockAt.has([x, y + 1, z].join(",")), false, "head room at the spawn");
  eq(museum.rooms.map((r) => r.id).join(" "), "foyer workshop information gallery1 gallery2 gallery3 portal_hall");
  eq(museum.world_version.length > 0, true);
});

run("the museum's portals: one per world, one per exhibit room, each room's way back", () => {
  const targets = museum.meta.filter((m) => m.target).map((m) => m.target);
  for (const r of data.regions) eq(targets.includes(r.id), true, "a portal to " + r.id);
  for (const r of museum.exhibit_rooms) eq(targets.includes(r.id), true, "a portal to " + r.id);
  eq(targets.filter((t) => t === "portal_hall").length, museum.exhibit_rooms.length, "a way back from every exhibit room");
  for (const m of museum.meta.filter((m) => m.target)) eq(blockAt.get(m.pos.join(",")), "crystalminer:teleporter", "a teleporter at " + m.pos);
});

run("every clue crystal asks about an exhibit, every door has two halves, the levers are where the pad says", () => {
  const clues = museum.meta.filter((m) => m.exhibit);
  eq(clues.length, Object.keys(data.museum.clues).length, "one clue crystal per exhibit");
  for (const c of clues) eq(!!data.museum.clues[c.exhibit], true, "a question for " + c.exhibit);
  for (const [k, n] of blockAt) {
    if (!n.startsWith("crystalminer:door_bottom")) continue;
    const [x, y, z] = k.split(",").map(Number);
    eq((blockAt.get([x, y + 1, z].join(",")) || "").startsWith("crystalminer:door_top"), true, "the top half of the door at " + k);
  }
  for (const l of museum.pad.levers) eq(blockAt.get([l.x, 1, l.z].join(",")), "crystalminer:lever_" + l.letter, "lever " + l.letter);
});

run("every texture the museum draws is in web/textures/game, and every kind of block has a definition", () => {
  const have = new Set(readdirSync("web/textures/game"));
  const need = new Set();
  const take = (s) => { for (const m of String(s || "").matchAll(/[\w-]+\.png/g)) need.add(m[0]); };
  for (const name of museum.palette) {
    const d = museum.defs[name];
    eq(!!d && !d.unknown, true, "a definition for " + name);
    (d.tiles || []).forEach(take);
  }
  museum.signs.forEach((s) => take(s.texture));
  museum.pictures.forEach((p) => take(p.texture));
  museum.npcs.forEach((n) => (n.textures || []).forEach(take));
  data.museum.structures.forEach((s) => take(s.plaque.texture));
  const missing = [...need].filter((n) => !have.has(n));
  eq(missing.length, 0, "missing: " + missing.slice(0, 5).join(" "));
});

const { applyLever } = await import("../web/js/pad.js");
run("the Try-it Pad: T slides a shape, M mirrors it, and a mirror image matches only a symmetric shape", () => {
  const pad = { build: museum.pad.build, result: museum.pad.result, detect: data.detect };
  const lever = (L) => museum.pad.levers.find((l) => l.letter === L);
  const B = pad.build, R = pad.result;
  // An L with a post: no symmetry of its own (gate.lua's motif).
  const chiral = new Map([[0, 0, 0], [1, 0, 0], [2, 0, 0], [2, 0, 1], [0, 1, 0], [0, 2, 0]].map(([dx, dy, dz]) => [[B.x + 1 + dx, B.y + dy, B.z + 1 + dz].join(","), "red"]));
  const t = applyLever(lever("T"), chiral, pad);
  eq(t.matches, true);
  eq(t.copy.map((c) => [c[0] - R.x, c[1] - R.y, c[2] - R.z].join(",")).sort().join(" "),
    [...chiral.keys()].map((k) => { const [x, y, z] = k.split(",").map(Number); return [x - B.x, y - B.y, z - B.z].join(","); }).sort().join(" "), "T copies the shape as it is");
  eq(applyLever(lever("M"), chiral, pad).matches, false, "the mirror twin of a chiral shape never matches");
  eq(applyLever(lever("I"), chiral, pad).matches, false, "nor does its inverse");
  const one = new Map([[[B.x + 2, B.y + 2, B.z + 2].join(","), "blue"]]);
  eq(applyLever(lever("M"), one, pad).matches, true, "one block is its own mirror image");
  // M is w = (-1, 1, 1) about the box centre: east and west swap, the rest stays.
  const m = applyLever(lever("M"), chiral, pad);
  eq(m.copy.map((c) => [c[0] - R.x, c[1] - R.y, c[2] - R.z].join(",")).sort().join(" "),
    [...chiral.keys()].map((k) => { const [x, y, z] = k.split(",").map(Number); return [4 - (x - B.x), y - B.y, z - B.z].join(","); }).sort().join(" "), "M mirrors east and west");
});

// The crystal exhibits' live pipeline, against exhibit_live.lua on the same records.
const Live = await import("../web/js/exhibit_live.js");
const ELEMENTS = data.museum.elements;

run("live exhibits: the same atoms, bonds and unit cell as the Lua pipeline, on the game's sample records", () => {
  ref.live.records.forEach((rec, i) => {
    const want = ref.live.prepared[i], got = Live.prepare(rec, ELEMENTS);
    const name = rec.name || rec.id;
    if (want.error) { eq(got.error, want.error, name); return; }
    eq(got.error, undefined, name + " was rejected: " + got.error);
    for (const k of ["atoms", "lo", "hi", "cell", "bonds"]) eq(JSON.stringify(got[k]), JSON.stringify(want[k]), name + " " + k);
    eq(got.formula, want.formula, name + " formula");
  });
});

run("live exhibits: rejects what the game rejects, with the same reasons", () => {
  for (const r of ref.live.rejected) eq(Live.prepare(r.record, ELEMENTS).error || "accepted", r.error, r.record.name);
});

run("live exhibits: the same fingerprints for records, names and formulas", () => {
  ref.live.records.forEach((rec, i) => {
    const fp = Live.fingerprint(rec);
    eq(fp.formula + " " + fp.anonymous, ref.live.fingerprints[i].join(" "), rec.name);
  });
  for (const [name, formula, anonymous] of ref.live.names) {
    const fp = name.startsWith("formula:") ? Live.fingerprintFormula(name.slice(8)) : Live.nameFingerprint(name);
    eq(fp ? fp.formula + " " + fp.anonymous : "none", formula === false ? "none" : formula + " " + anonymous, name);
  }
});

run("live exhibits: a prepared record has the shape of a baked one, and the baked ones round-trip", () => {
  const rec = ref.live.records[1];
  const room = Live.forRoom(Live.prepare(rec, ELEMENTS));
  const baked = data.museum.structures.find((s) => s.id === rec.id);
  eq(!!baked, true, "the baked SrTiO3");
  eq(JSON.stringify(room.atoms), JSON.stringify(baked.atoms), "atoms from the model's origin");
  eq(JSON.stringify(room.dots.map((d) => d.slice(0, 3))), JSON.stringify(baked.dots.map((d) => d.slice(0, 3))), "marker positions");
  // The panel's text follows plaque_text; a live record's formula is the game's reduced one (O3Sr1Ti1), where the baked record spells it SrTiO3.
  eq(room.plaque.text.split("\n")[0], baked.plaque.text.split("\n")[0], "the panel's title");
  eq(room.plaque.text.split("\n").slice(2).join("\n"), baked.plaque.text.split("\n").slice(2).join("\n"), "the panel's cell, atoms and source");
});

// A live panel is lettered in the browser: the same [combine recipe as SG.texture, for the baked panels and for texts with quotes, minus signs, letters outside ASCII and too much text.
const { texture: signTexture } = await import("../web/js/sign_layout.js");
run("live exhibits: a panel's lettering is the game's, letter for letter", () => {
  for (const s of data.museum.structures) eq(signTexture(data.museum.lettering, "panel", s.plaque.text).texture, s.plaque.texture, s.name);
  for (const s of ref.live.signs) {
    const got = signTexture(data.museum.lettering, "panel", s.text);
    eq(got.texture, s.texture, s.text.slice(0, 30));
    eq(got.fits + " " + got.w + "x" + got.h, s.fits + " " + s.w + "x" + s.h, "fit and size of " + s.text.slice(0, 30));
  }
  const live = Live.forRoom(Live.prepare(ref.live.records[0], ELEMENTS));
  eq(signTexture(data.museum.lettering, "panel", live.plaque.text).fits, true, "a live panel fits");
});

// Gallery 2's holograms, against hologram_logic.lua.
const HL = await import("../web/js/hologram_logic.js");
const HOLO = data.museum.hologram;
run("holograms: the same points as the Lua, for every level of detail, and the same plaque", () => {
  let thinned = false;
  for (const h of ref.live.holograms) {
    const got = HL.points(HOLO, ELEMENTS, h.grid, [-47, 4, 30], h.tier);
    eq(got.length, h.points.length, "points at tier " + h.tier);
    got.forEach((p, i) => {
      const w = h.points[i];
      for (let a = 0; a < 3; a++) if (Math.abs(p.pos[a] - w[a]) > 1e-9) throw new Error("point " + i + " axis " + a + ": " + p.pos[a] + " vs " + w[a]);
      eq([p.colour, p.kind, p.size.toFixed(6), p.spread.toFixed(6), p.amount, p.exptime].join(" "), [w[3], w[4], w[5].toFixed(6), w[6].toFixed(6), w[7], w[8]].join(" "), "point " + i);
    });
    const raw = h.grid.atoms.length + h.grid.bonds.length + h.grid.cell.length;
    if (h.tier === 1 && raw > HOLO.max_points) thinned = true;
    eq(HL.plaqueText(HOLO, 3, Object.assign({ grid: h.grid }, h.record)), h.plaque, "plaque");
    eq(signTexture(data.museum.lettering, "plaque", h.plaque).fits, true, "the plaque fits: " + h.plaque.split("\n")[0]);
  }
  eq(thinned, true, "a sample big enough to be thinned");
  for (const [d, ...tiers] of ref.live.lod) eq([HL.lod(d), HL.lod(d, 1), HL.lod(d, 2), HL.lod(d, 3)].join(","), tiers.join(","), "level of detail at " + d);
  for (const [p, off, on] of ref.live.visible) eq(HL.visible(HOLO, p, false) + " " + HL.visible(HOLO, p, true), off + " " + on, "visible at " + p);
  const plaques = museum.signs.filter((s) => s.holo).map((s) => s.holo).sort().join(",");
  eq(plaques, "1,2,3,4,5,6", "a plaque for each pedestal in the museum");
});

const Fetch = await import("../web/js/exhibit_fetch.js");
run("the loading notice says what the game's says", () => {
  for (const c of ref.live.notice) {
    if (c[0] === "lines") eq(Fetch.noticeLines(c[1], c[2], c[3] || undefined).join(" | "), c[4] + " | " + c[5], c[1] + " at " + c[2]);
    else if (c[0] === "success") eq(Fetch.noticeSuccess(c[1], 4).join(" | "), c[2] + " | " + c[3], "ready");
    else eq(Fetch.noticeFailure(c[1] || undefined).join(" | "), c[2] + " | " + c[3], "failure");
  }
  eq(Fetch.NOTICE.SUCCESS_SECONDS + " " + Fetch.NOTICE.FAILURE_SECONDS, ref.live.notice_seconds.join(" "), "how long it stays");
});

// The loader (exhibit_fetch.js, as exhibit_dynamic.lua's request_structure) against a fake api/mp.php serving the sample records.
const { loadStructure } = await import("../web/js/exhibit_fetch.js");
async function runAsync(name, fn) {
  try { await fn(); passed++; console.log("  ok    " + name); }
  catch (e) { failed++; console.log("  FAIL  " + name + "\n        " + e.message); }
}
function fakeApi(answer) {
  const asked = [];
  const fetchFn = async (url) => {
    const q = new URLSearchParams(url.split("?")[1]);
    asked.push(q.toString());
    const [status, body] = answer(q);
    if (status === 0) throw new Error("offline");
    return { ok: status < 400, status, json: async () => body };
  };
  return { fetchFn, asked };
}
const RECORDS = ref.live.records;
const serve = (q) => q.has("element") ? [200, { data: RECORDS.map((r) => ({ id: r.id, name: r.name })) }]
  : [200, RECORDS.find((r) => r.id === q.get("id"))];
const accepted = new Set(RECORDS.filter((r) => !Live.prepare(r, ELEMENTS).error).map((r) => r.id));
await runAsync("live loader: finds a structure the pipeline accepts, in the shape of a baked one", async () => {
  const api = fakeApi(serve);
  const stages = [];
  const got = await loadStructure({ elements: ELEMENTS, fetchFn: api.fetchFn, onStage: (st, d) => stages.push(st + ": " + d) });
  eq(!!got.structure, true, "a structure (" + got.error + ")");
  eq(accepted.has(got.structure.id), true, "an accepted record");
  eq(got.structure.live && !!got.structure.plaque.text && !!got.structure.fingerprint && !!got.structure.grid, true, "live, with a panel text, a fingerprint and a grid");
  eq(api.asked[0].startsWith("element="), true, "a list first");
  eq(stages[0] + " / " + stages[stages.length - 1], "searching: Searching list 1 of up to 30 / building: Building the exhibit room...", "the notice's stages");
  eq(stages.some((x) => x.startsWith("checking: Checking record 1 of up to 60")), true, "checking a record");
});
await runAsync("live loader: never shows what is already on show, or what is like it", async () => {
  const api = fakeApi(serve);
  const got = await loadStructure({ elements: ELEMENTS, fetchFn: api.fetchFn, shown: new Set(RECORDS.map((r) => r.md5)) });
  // As in the game, a duplicate or a similar structure counts as plainly "rejected" in the message.
  eq(!got.structure && got.error.startsWith("No suitable structure found"), true, "every record already on show: " + got.error);
  eq(api.asked.filter((q) => q.startsWith("id=")).length <= 3, true, "each record checked once");
  const fps = RECORDS.map((r) => Live.fingerprint(r));
  const none = await loadStructure({ elements: ELEMENTS, fetchFn: fakeApi(serve).fetchFn, excluded: fps });
  eq(!!none.error, true, "every record is like one on show");
});
await runAsync("live loader: gives up after three network errors, and at once when the site refuses", async () => {
  const offline = fakeApi(() => [0]);
  const got = await loadStructure({ elements: ELEMENTS, fetchFn: offline.fetchFn });
  eq(offline.asked.length, 3, "requests sent offline");
  eq(got.error, "No suitable structure found (rejected: 3 http error)", "the message");
  const down = fakeApi(() => [502, { error: "timeout" }]);
  await loadStructure({ elements: ELEMENTS, fetchFn: down.fetchFn });
  eq(down.asked.length, 3, "requests sent while the Materials Project times out");
  const limited = fakeApi(() => [429, { error: "That is a lot of crystal structures for one hour." }]);
  const stop = await loadStructure({ elements: ELEMENTS, fetchFn: limited.fetchFn });
  eq(limited.asked.length + " " + stop.stop + " " + stop.error, "1 true That is a lot of crystal structures for one hour.", "a refusal");
});

console.log(passed + " passed, " + failed + " failed");
if (failed > 0) process.exit(1);
