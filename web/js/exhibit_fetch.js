// Loading a random live crystal structure for an exhibit room, as exhibit_dynamic.lua's request_structure does, through the site's api/mp.php (which adds the Materials Project key on the server): a random element, a list of structures whose name contains it, up to three of them checked in detail, until one fits a room. No DOM; tests/test_web.mjs runs it against a fake API.
import { prepare, forRoom, filterNameCandidates, similar } from "./exhibit_live.js";

export const API = "api/mp.php";
const MAX_LISTS = 30, MAX_DETAILS = 60, MAX_SECONDS = 60, PER_LIST = 3, NETWORK_ERRORS = 3;
// The errors that mean the Materials Project cannot be reached (api/mp.php's 502 answers): three in a row and the search stops, instead of sending up to 90 requests.
const NETWORK = new Set(["request failed", "http error", "timeout", "the Materials Project refused the key"]);

// The site's answer: GET api/mp.php?..., to { ok, status, body }. A failed request is { ok: false, status: 0 }.
export async function ask(query, fetchFn = fetch) {
  try {
    const res = await fetchFn(API + "?" + query, { headers: { Accept: "application/json" } });
    let body = null;
    try { body = await res.json(); } catch { body = null; }
    return { ok: res.ok && body !== null, status: res.status, body };
  } catch {
    return { ok: false, status: 0, body: null };
  }
}

// Whether this site serves live structures (a key is set and 'live_exhibits' is not off).
export async function liveOn(fetchFn = fetch) {
  const r = await ask("status", fetchFn);
  return r.ok && r.body.live === true;
}

// As exhibit_dynamic.lua's rejection_reason.
function reason(err) {
  if (!err) return "rejected";
  for (const [pattern, name] of [["request failed", "http error"], ["http error", "http error"], ["bad JSON", "bad JSON"], ["timeout", "timeout"], ["bulk", "slab"], ["atom count", "too many atoms"],
    ["grid cell", "grid collision"], ["disordered", "disorder"], ["unknown element", "unknown element"], ["footprint", "footprint"], ["tall", "too tall"], ["no bonds", "no bonds"], ["dots", "too many dots"]])
    if (err.includes(pattern)) return name;
  return "rejected";
}

function failure(rejections) {
  const text = Object.keys(rejections).sort().map((k) => rejections[k] + " " + k);
  return "No suitable structure found" + (text.length ? " (rejected: " + text.join(", ") + ")" : "");
}

// Finds a structure for a room. elements: data.museum.elements; excluded: fingerprints of what the other rooms show and of what this room showed last; shown: md5s already on show or baked in.
// onStage(stage, detail) follows the search as the game's loading notice does (exhibit_dynamic.lua update_notice): "searching", "checking", "building".
// Resolves to { structure } (ready for Museum.showExhibit) or { error, stop } (stop: the site refused, so do not ask again soon).
export async function loadStructure({ elements, excluded = [], shown = new Set(), fetchFn = fetch, random = Math.random, now = () => Date.now() / 1000, onStage = () => {} }) {
  const started = now(), names = Object.keys(elements), tried = new Set(), triedElements = new Set(), rejections = {};
  let lists = 0, details = 0, networkErrors = 0;
  const reject = (err) => { const r = reason(err); rejections[r] = (rejections[r] || 0) + 1; };
  const failed = () => ({ error: failure(rejections) });
  // A request that failed: refused by the site (limits, live off) ends the search; three network failures in a row too.
  const refused = (r) => r.status === 429 || r.status === 503 || r.status === 403;
  const errorOf = (r) => (r.body && r.body.error) || (r.status === 0 ? "request failed" : "http error");
  const networkDown = (err) => NETWORK.has(err) && ++networkErrors >= NETWORK_ERRORS;

  while (lists < MAX_LISTS && details < MAX_DETAILS && now() - started < MAX_SECONDS) {
    const choices = names.filter((e) => !triedElements.has(e));
    if (!choices.length) break;
    const element = choices[Math.floor(random() * choices.length)];
    triedElements.add(element);
    lists++;
    onStage("searching", "Searching list " + lists + " of up to " + MAX_LISTS);
    const r = await ask("element=" + encodeURIComponent(element), fetchFn);
    if (refused(r)) return { error: errorOf(r), stop: true };
    if (!r.ok) { const err = errorOf(r); reject(err); if (networkDown(err)) return failed(); continue; }
    networkErrors = 0;
    const list = Array.isArray(r.body.data) ? r.body.data : r.body;
    if (!Array.isArray(list)) { reject("bad JSON"); continue; }
    for (let i = list.length - 1; i >= 1; i--) { const j = Math.floor(random() * (i + 1)); [list[i], list[j]] = [list[j], list[i]]; }
    const [candidates, nSimilar] = filterNameCandidates(list, excluded, tried);
    for (const item of list) if (item && item.id) tried.add(item.id);
    for (let k = 0; k < nSimilar; k++) reject("similar");
    for (const candidate of candidates.slice(0, PER_LIST)) {
      if (details >= MAX_DETAILS || now() - started >= MAX_SECONDS) return failed();
      details++;
      onStage("checking", "Checking record " + details + " of up to " + MAX_DETAILS);
      const d = await ask("id=" + encodeURIComponent(candidate.id), fetchFn);
      if (refused(d)) return { error: errorOf(d), stop: true };
      if (!d.ok) { const err = errorOf(d); reject(err); if (networkDown(err)) return failed(); continue; }
      networkErrors = 0;
      const raw = d.body;
      const prepared = prepare(raw, elements);
      if (prepared.error) { reject(prepared.error); continue; }
      if (shown.has(raw.md5)) { reject("duplicate"); continue; }
      if (similar(raw, excluded)) { reject("similar"); continue; }
      onStage("building", "Building the exhibit room...");
      return { structure: forRoom(prepared) };
    }
  }
  return failed();
}

// The loading notice's two lines (exhibit_notice.lua): [title, status] while searching, checking or building, and when the room is ready or a built-in structure is shown instead.
export const NOTICE = { SUCCESS_SECONDS: 2, FAILURE_SECONDS: 4 };
const elapsedText = (t) => Math.max(0, Math.floor(t)) + " s";
export function noticeLines(stage, elapsed = 0, detail) {
  if (stage === "building") return ["Building the exhibit room...", elapsedText(elapsed)];
  if (stage === "checking") return ["Loading a random crystal structure", (detail || "Checking a record") + " " + elapsedText(elapsed)];
  return ["Loading a random crystal structure", "Searching the Materials Project" + ".".repeat(((Math.floor(elapsed) % 3) + 3) % 3 + 1) + " " + elapsedText(elapsed)];
}
export function noticeSuccess(name, room) {
  let n = String(name || "Live structure");
  if (n.length > 48) n = n.slice(0, 45) + "...";
  return ["Structure ready: " + n, "Entering exhibit room " + room];
}
export const noticeFailure = (reason) => ["Loading crystal structure", String(reason || "Could not load a new structure")];
