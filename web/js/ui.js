// The screen around the 3D view: where you are, the "Next:" line, the hotbar, messages, and the panels (guide, quiz, progress board, prediction, Free Lab). Text is always set with textContent, never as HTML.

export function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null && v !== false) e.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) if (c !== null && c !== undefined && c !== false) e.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return e;
}

const $ = (id) => document.getElementById(id);

export class UI {
  constructor({ onClose }) {
    this.onClose = onClose;
    this.panel = $("panel");
    this.toastTimer = null;
  }

  isOpen() { return !this.panel.hidden; }

  open(title, body, { wide = false, buttons = [] } = {}) {
    this.panel.replaceChildren(el("div", { class: "card" + (wide ? " wide" : "") },
      el("h2", {}, title), body,
      el("div", { class: "buttons" }, ...buttons, el("button", { class: "secondary", onclick: () => this.close() }, "Close (Esc)"))));
    this.panel.hidden = false;
  }

  close() {
    if (this.panel.hidden) return;
    this.panel.hidden = true;
    this.panel.replaceChildren();
    this.onClose();
  }

  toast(text, kind = "") {
    const t = $("toast");
    t.textContent = text;
    t.className = "show " + kind;
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => (t.className = ""), 4200);
  }

  setPlace(name, sub) { $("place-name").textContent = name; $("place-sub").textContent = sub || ""; }
  setHint(text) { $("hint").textContent = text ? "Next: " + text : ""; }
  setLegend(on) { $("legend").hidden = !on; }

  hotbar(colours, selected) {
    $("hotbar").replaceChildren(...colours.map((c, i) => el("div", { class: "slot" + (i === selected ? " on" : ""), title: c.replace("_", " ") },
      el("img", { src: "textures/" + c + ".png", alt: c }), el("span", {}, String(i + 1)))));
  }

  // The guide to a place (guides.lua), its explanation for the player's tier, and a note when it is locked.
  guide(area, guide, lessons, locked) {
    const body = el("div", { class: "guide" });
    const text = el("div", { class: "text" });
    if (guide) {
      if (locked) text.append(el("p", { class: "warn" }, locked));
      text.append(el("p", {}, guide.what), el("h3", {}, "What to do"));
      text.append(el("ol", {}, ...(guide.steps || []).map((s) => el("li", {}, webSteps(s)))));
      text.append(el("h3", {}, "What you will see"), el("p", {}, guide.see));
      if (guide.example) text.append(el("h3", {}, "In the real world"), el("p", {}, guide.example));
      text.append(el("h3", {}, "The word for it"), el("p", {}, guide.word));
    }
    const more = lessons.explanation(area);
    if (more.length) text.append(el("h3", {}, "For your tier"), el("ul", {}, ...more.map((l) => el("li", {}, webSteps(l)))));
    const pic = el("img", { class: "pic", src: "textures/guide_" + area.id + ".png", alt: "" });
    pic.onerror = () => pic.remove();
    body.append(pic, text);
    this.open(guide ? guide.title : area.name, body, { wide: true });
  }

  // One quiz question. A wrong option is greyed out and the hint shown; a right one shows why. onRight(question) runs once.
  quiz(title, q, onRight, { review = false } = {}) {
    const status = el("p", { class: "status" });
    const opts = el("div", { class: "options" });
    let done = false;
    q.options.forEach((o, i) => {
      const b = el("button", {
        onclick: () => {
          if (done || b.disabled) return;
          if (i === q.answer) {
            done = true;
            b.classList.add("right");
            status.className = "status right";
            status.textContent = "Right! " + (q.why || "");
            onRight(q, status);
          } else {
            b.disabled = true;
            status.className = "status wrong";
            status.textContent = "Not quite. " + (q.hint || "Look again, and think about what each operation does.");
          }
        },
      }, o);
      opts.append(b);
    });
    this.open(title, el("div", { class: "quiz" }, review ? el("p", { class: "note" }, "Review: this question does not change your tier.") : null,
      el("p", { class: "question" }, q.q), opts, status));
  }

  // The progress board (the game's inventory screen): tier, questions left in each place, a button to go to each.
  progress(lessons, data, go, reset) {
    const p = lessons.progress;
    const rows = lessons.areas.map((a) => {
      const qs = lessons.questions(a, p.tier);
      if (qs.length === 0) return null;
      const done = qs.filter((q) => p.answered[q.id]).length;
      return el("tr", {}, el("td", {}, a.name), el("td", { class: done === qs.length ? "done" : "todo" }, done === qs.length ? "done" : done + " of " + qs.length),
        el("td", {}, el("button", { onclick: () => go(a.id) }, "Go there")));
    }).filter(Boolean);
    const body = el("div", {},
      el("p", {}, "Tier " + p.tier + ": " + (data.tiers[String(p.tier)] || "") + " (" + lessons.remaining() + " question(s) left)"),
      rows.length ? el("table", { class: "board" }, ...rows) : el("p", {}, "No questions at this tier. Try the challenges in the Free Lab."),
      el("h3", {}, "All worlds"),
      el("div", { class: "worlds" }, ...data.regions.map((r) => el("button", { class: lessons.unlocked(r) ? "" : "locked", onclick: () => go(r.id), title: "Tier " + r.tier },
        r.name + " (" + r.symbol + ")"))));
    this.open("Your progress", body, { wide: true, buttons: [el("button", { class: "secondary", onclick: reset }, "Start again")] });
  }

  // Predict before you see: how many blocks will one block become here?
  predict(onAnswer) {
    const input = el("input", { type: "number", min: "1", max: "999", value: "", placeholder: "How many?" });
    const go = () => { const n = parseInt(input.value, 10); if (n > 0) onAnswer(n); };
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") go(); e.stopPropagation(); });
    this.open("Predict first", el("div", {}, el("p", {}, "You are about to place your first block in this world. Counting yours, how many blocks will there be once the symmetry has made its copies?"),
      input), { buttons: [el("button", { onclick: go }, "That many")] });
    setTimeout(() => input.focus(), 50);
  }

  // The Free Lab: choose its symmetry, check a build's symmetry, the challenges.
  freeLab(groups, current, challenge, pick, detect) {
    const systems = [...new Set(groups.map((g) => g.system))];
    const body = el("div", { class: "freelab" },
      el("p", {}, "Give the lab any symmetry that fits the block grid. Blocks already in the lab stay as they are."),
      ...systems.map((s) => el("div", { class: "system" }, el("span", {}, s),
        ...groups.filter((g) => g.system === s).map((g) => el("button", { class: g.symbol === current ? "on" : "", onclick: () => pick(g.symbol) }, g.symbol)))),
      challenge ? el("p", { class: "challenge" }, "Challenge: " + challenge.text + " (choose symmetry 1 to build without copies, then check it).") : el("p", {}, "You have done every challenge!"));
    this.open("Free Lab: symmetry " + current, body, { wide: true, buttons: [el("button", { onclick: detect }, "What symmetry is my build?")] });
  }
}

// The game's texts name its commands and keys; in the browser some keys differ.
export function webSteps(text) {
  return String(text).replace(/Press T, type \/quiz and press Enter/g, "Press Q").replace(/type \/quiz/g, "press Q").replace(/\/explain/g, "G")
    .replace(/Press K to fly/g, "Press K to fly (Space up, Shift down)");
}
