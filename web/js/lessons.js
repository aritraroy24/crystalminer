// Tiers, quiz questions and explanations, as in mods/crystalminer/lessons.lua, and the player's progress, kept in this browser (localStorage). The questions and texts come from data/crystalminer.json.

const STORE = "crystalminer:progress:v1";

export class Lessons {
  constructor(data) {
    this.data = data;
    this.areas = [data.gate, ...data.regions];   // the gate first, as L.areas
    this.maxTier = Math.max(...Object.keys(data.tiers).map(Number));
    this.progress = this.load();
  }

  load() {
    let p = null;
    try { p = JSON.parse(localStorage.getItem(STORE) || "null"); } catch { p = null; }
    return Object.assign({ tier: 0, answered: {}, predicted: {}, guided: {}, challenge: 0, review: {}, freeSymbol: "1" }, p || {});
  }

  save() {
    try { localStorage.setItem(STORE, JSON.stringify(this.progress)); } catch { /* private window: progress lasts this visit only */ }
  }

  reset() {
    this.progress = Object.assign(this.load(), { tier: 0, answered: {}, predicted: {}, guided: {}, challenge: 0, review: {} });
    this.save();
  }

  area(id) { return this.areas.find((a) => a.id === id); }

  questions(area, tier) { return (area.quiz && area.quiz[String(tier)]) || []; }

  questionsForTier(tier) { return this.areas.flatMap((a) => this.questions(a, tier)); }

  remaining() { return this.questionsForTier(this.progress.tier).filter((q) => !this.progress.answered[q.id]).length; }

  // Open questions of one area at the player's tier.
  open(area) { return this.questions(area, this.progress.tier).filter((q) => !this.progress.answered[q.id]); }

  // The first area with open questions at the player's tier, for the "Next:" line.
  nextArea() { return this.areas.find((a) => this.open(a).length > 0) || null; }

  // Records a right answer; returns true if that finished the tier (which is then raised).
  recordCorrect(id) {
    this.progress.answered[id] = true;
    let up = false;
    if (this.progress.tier < this.maxTier && this.remaining() === 0) { this.progress.tier += 1; up = true; }
    this.save();
    return up;
  }

  // Questions a player may review in an area: every tier up to theirs, lowest first (L.review_questions). Never above their tier.
  reviewQuestions(area) {
    return Object.keys(area.quiz || {}).map(Number).sort((a, b) => a - b)
      .filter((t) => t <= this.progress.tier).flatMap((t) => this.questions(area, t));
  }

  nextReview(area) {
    const qs = this.reviewQuestions(area);
    if (qs.length === 0) return null;
    const k = this.progress.review[area.id] || 0;
    this.progress.review[area.id] = k + 1;
    this.save();
    return qs[k % qs.length];
  }

  unlocked(area) { return this.progress.tier >= (area.tier || 0); }

  // Explanation lines for every tier up to the player's (L.explanation).
  explanation(area) {
    return Object.keys(area.explain || {}).map(Number).sort((a, b) => a - b)
      .filter((t) => t <= this.progress.tier).flatMap((t) => area.explain[String(t)]);
  }
}

// What a player built in each world, kept in this browser so it is still there next time.
export function loadBuild(id) {
  try { return JSON.parse(localStorage.getItem("crystalminer:build:" + id) || "[]"); } catch { return []; }
}
export function saveBuild(id, blocks) {
  try { localStorage.setItem("crystalminer:build:" + id, JSON.stringify(blocks)); } catch { /* storage full or blocked */ }
}
