// Prism's chat window, as in the game (tutor_window.lua): bubbles, suggested questions for the player's tier, the conversation remembered until "New chat". Questions go to api/chat.php, which holds the API key and Prism's grounding text; the browser never sees either.
import { el } from "./ui.js";

export class Chat {
  constructor(tutor, { context, onClose, onAsked, onAnswered, onFailed }) {
    this.t = tutor;
    this.context = context;             // () => { tier, place, inWorld }
    this.onClose = onClose;
    this.onAsked = onAsked;
    this.onAnswered = onAnswered;
    this.onFailed = onFailed;
    this.root = document.getElementById("chat");
    this.msgs = [];
    try { this.msgs = JSON.parse(sessionStorage.getItem("crystalminer:chat") || "[]"); } catch { this.msgs = []; }
    this.waiting = false;
    this.notice = null;
    this.service = null;
  }

  isOpen() { return !this.root.hidden; }

  open(question) {
    this.root.hidden = false;
    this.render();
    if (question) this.ask(question);
  }

  close() {
    if (this.root.hidden) return;
    this.root.hidden = true;
    this.onClose();
  }

  remember() { try { sessionStorage.setItem("crystalminer:chat", JSON.stringify(this.msgs.slice(-40))); } catch { /* ignore */ } }

  // **bold** in the model's answer is kept; everything else is text.
  rich(text) {
    const p = el("p");
    String(text).split(/(\*\*[^*]+\*\*)/).forEach((part) => {
      if (part.startsWith("**") && part.endsWith("**")) p.append(el("b", {}, part.slice(2, -2)));
      else p.append(document.createTextNode(part.replace(/^#+\s*/gm, "").replace(/`/g, "")));
    });
    return p;
  }

  bubble(role, text, extra = "") {
    const who = role === "user" ? "You" : this.t.name;
    return el("div", { class: "msg " + role + " " + extra },
      el("img", { src: role === "user" ? "textures/tutor_user.png" : "textures/tutor_icon.png", alt: "" }),
      el("div", { class: "bubble" }, role === "user" ? null : el("div", { class: "who" }, who), role === "user" ? el("p", {}, text) : this.rich(text)));
  }

  render() {
    const ctx = this.context();
    const list = el("div", { class: "msgs" },
      this.bubble("assistant", this.t.welcome.replace("%s", "there")),
      ...this.msgs.map((m) => this.bubble(m.role === "error" ? "assistant" : m.role, m.text, m.role === "error" ? "error" : "")),
      this.waiting ? this.bubble("assistant", this.t.thinking, "thinking") : null,
      this.notice ? this.bubble("assistant", this.notice, "error") : null);
    const tier = Math.max(0, Math.min(4, ctx.tier));
    const sugg = [...(this.t.suggestions[String(tier)] || this.t.suggestions["0"])];
    if (ctx.inWorld) sugg[0] = this.t.here;
    const input = el("input", { type: "text", maxlength: String(this.t.max_chars), placeholder: "Ask Prism about symmetry, crystals or this museum...", autocomplete: "off" });
    input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") this.ask(input.value);
      if (e.key === "Escape") this.close();
    });
    this.root.replaceChildren(el("div", { class: "chatbox" },
      el("aside", {},
        el("img", { class: "avatar", src: "textures/tutor_avatar.png", alt: "Prism" }),
        el("h2", {}, this.t.name), el("p", { class: "role" }, this.t.role), el("p", {}, this.t.about),
        el("p", {}, el("b", {}, "Your tier: "), String(ctx.tier)), el("p", {}, el("b", {}, "You are in: "), ctx.place),
        el("button", { onclick: () => { if (!this.waiting) { this.msgs = []; this.notice = null; this.remember(); this.render(); } } }, "New chat"),
        el("button", { class: "secondary", onclick: () => this.close() }, "Close (Esc)")),
      el("section", {}, list,
        el("div", { class: "suggest" }, ...sugg.map((s) => el("button", { onclick: () => this.ask(s) }, s))),
        el("div", { class: "ask" }, input, el("button", { class: "send", onclick: () => this.ask(input.value) }, "Send")),
        el("p", { class: "note" }, this.t.disclaimer + (this.service ? " Powered by " + this.service + "." : "")))));
    list.scrollTop = list.scrollHeight;
    if (!this.waiting) setTimeout(() => input.focus(), 30);
  }

  async ask(text) {
    text = String(text || "").trim();
    if (!text || this.waiting) return;
    if (text.length > this.t.max_chars) { this.notice = "That is too long for the tutor. Please keep it under " + this.t.max_chars + " characters."; this.render(); return; }
    const ctx = this.context();
    // Answered questions only, each with its answer, the last few (tutor.lua's chat_request does the same on the server).
    const history = [];
    for (let i = 0; i + 1 < this.msgs.length; i++) {
      if (this.msgs[i].role === "user" && this.msgs[i + 1].role === "assistant") history.push(this.msgs[i], this.msgs[i + 1]);
    }
    this.msgs.push({ role: "user", text });
    this.waiting = true;
    this.notice = null;
    this.render();
    this.onAsked(text);
    let answer = null, error = null;
    try {
      const res = await fetch("api/chat.php", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question: text, history: history.slice(-this.t.history), tier: ctx.tier, place: ctx.place }),
      });
      const out = await res.json().catch(() => ({}));
      if (out.answer) { answer = out.answer; this.service = out.service || this.service; } else error = out.error || "Prism could not be reached (" + res.status + ").";
    } catch {
      error = "Prism could not be reached. The chat needs the site's PHP part (api/chat.php) to be online.";
    }
    this.waiting = false;
    if (answer) { this.msgs.push({ role: "assistant", text: answer }); this.onAnswered(text, answer); }
    else { this.msgs.push({ role: "error", text: error }); this.onFailed(); }
    this.remember();
    if (this.isOpen()) this.render();
  }
}
