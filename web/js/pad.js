// The Try-it Pad in the Workshop, as in the game (init.lua: apply_lever and the prediction): build a shape in the glass box marked YOUR SHAPE, punch a lever (T slides, R turns half a turn, M mirrors, I inverts through the centre), guess whether the copy could be turned to match, and see the copy in the box marked COPY.
// Pure (no three.js), so that tests/test_web.mjs can load it.
import { detect } from "./symmetry.js";

export const SIZE = 5;

export function inBox(p, corner) {
  return p[0] >= corner.x && p[0] < corner.x + SIZE && p[1] >= corner.y && p[1] < corner.y + SIZE && p[2] >= corner.z && p[2] < corner.z + SIZE;
}

// The copy of a shape: each block at offset d from the build box's centre goes to the result box's centre plus w·d (w is the lever's diagonal, e.g. M = (-1, 1, 1)). blocks: Map "x,y,z" -> colour, inside the build box. Returns { copy: [[x, y, z, colour]], matches }: matches is whether the copy could be moved onto the shape without mirroring, which for M and I is so only if the shape has a mirror plane or a centre of its own.
export function applyLever(lever, blocks, pad) {
  const copy = [];
  const B = pad.build, R = pad.result;
  for (const [k, colour] of blocks) {
    const [x, y, z] = k.split(",").map(Number);
    const d = [x - B.x - 2, y - B.y - 2, z - B.z - 2];
    copy.push([R.x + 2 + lever.w[0] * d[0], R.y + 2 + lever.w[1] * d[1], R.z + 2 + lever.w[2] * d[2], colour]);
  }
  const improper = lever.w[0] * lever.w[1] * lever.w[2] < 0;
  if (!improper || blocks.size === 0) return { copy, matches: true };
  const d = detect(blocks, pad.detect);
  const det = (o) => o[0] * (o[4] * o[8] - o[5] * o[7]) - o[1] * (o[3] * o[8] - o[5] * o[6]) + o[2] * (o[3] * o[7] - o[4] * o[6]);
  return { copy, matches: d.ops.some((o) => det(o) < 0) };
}

// What the game says after the copy appears (init.lua, the "crystalminer:predict" form).
export function verdict(lever, predicted, matches) {
  const first = predicted === matches ? "Your guess was right. " : "Not what you guessed. ";
  if (lever.op === "translation" || lever.op === "rotation") {
    return first + "The copy could be turned back to match: " + (lever.op === "translation" ? "sliding" : "turning") + " only moves a shape, it never changes it.";
  }
  if (matches) {
    return first + "The copy matches this time, because your shape is symmetric itself: it has its own mirror or centre point, so its mirror twin is the same shape. Now try a lopsided shape with lever " + lever.letter + ".";
  }
  return first + "The copy is your shape's mirror twin, like your left hand and your right hand: no turning can make them match. Shapes like this are called chiral, from the Greek word for hand.";
}

