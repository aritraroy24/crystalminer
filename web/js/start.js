// The game needs a keyboard, a mouse and a window of at least 800 x 560 (below that the HUD, the panels and the start screen no longer fit). On anything smaller, or with only a touch screen, the page shows a message instead (#unsupported, css/style.css) and the game is not even downloaded; it starts as soon as the window is big enough, for example after resizing it or zooming out.
export const MIN_WIDTH = 800, MIN_HEIGHT = 560;
// The same query as in css/style.css.
const TOO_SMALL = matchMedia(`(max-width: ${MIN_WIDTH - 1}px), (max-height: ${MIN_HEIGHT - 1}px), not all and (any-pointer: fine)`);

const size = document.getElementById("unsupported-size");
function update() {
  if (size) size.textContent = "This window: " + innerWidth + " x " + innerHeight + (matchMedia("(any-pointer: fine)").matches ? "" : ", no mouse") + ". Needed: " + MIN_WIDTH + " x " + MIN_HEIGHT + " with a keyboard and mouse.";
}

if (TOO_SMALL.matches) {
  update();
  // Checked on every resize too: a query's change event is not always sent while a window is being resized.
  await new Promise((resolve) => {
    const check = () => {
      update();
      if (TOO_SMALL.matches) return;
      TOO_SMALL.removeEventListener("change", check);
      removeEventListener("resize", check);
      resolve();
    };
    TOO_SMALL.addEventListener("change", check);
    addEventListener("resize", check);
  });
}
await import("./main.js");
