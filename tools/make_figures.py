"""Pictures for the guide windows, the exhibit panels and the history timeline.

The symmetry pictures are drawn from data the game's own engine computes (tools/figure_data.lua),
so every copy shown is where the game puts it. Run from the repository root:

    luajit tools/figure_data.lua > /tmp/fig.json && python3 tools/make_figures.py /tmp/fig.json

Pictures of people are not included: only diagrams that can be drawn from the science itself.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "mods", "crystalminer", "textures")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

BG = (250, 246, 236)
INK = (40, 36, 30)
YOURS = (248, 197, 39)
COPY = (58, 120, 217)
GAME = {
    "white": (233, 236, 236), "light_grey": (142, 142, 134), "grey": (62, 68, 71), "black": (40, 41, 45),
    "brown": (114, 71, 40), "red": (190, 45, 38), "orange": (240, 118, 19), "yellow": (248, 197, 39),
    "lime": (112, 185, 25), "green": (84, 140, 27), "cyan": (21, 137, 145), "light_blue": (58, 175, 217),
    "blue": (53, 57, 157), "purple": (121, 42, 172),
}
ELEMENT_NAMES = {"cu": "copper", "fe": "iron", "na": "sodium", "cl": "chloride", "cs": "caesium",
                 "sr": "strontium", "ti": "titanium", "o": "oxygen", "c": "carbon"}


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


# ----------------------------------------------------------------------------- projections

# Camera above the north-east, turned off the cube's diagonals so that no axis is seen end-on.
_AZ, _EL = math.radians(36), math.radians(27)
CAM = (math.cos(_EL) * math.cos(_AZ), math.sin(_EL), math.cos(_EL) * math.sin(_AZ))
_r = (CAM[2], 0.0, -CAM[0])
_n = math.hypot(_r[0], _r[2])
RIGHT = (_r[0] / _n, 0.0, _r[2] / _n)
UP = (CAM[1] * RIGHT[2] - CAM[2] * RIGHT[1], CAM[2] * RIGHT[0] - CAM[0] * RIGHT[2], CAM[0] * RIGHT[1] - CAM[1] * RIGHT[0])


def iso(p):
    """World (x east, y up, z north) to screen, seen from above the north-east."""
    return (sum(a * b for a, b in zip(p, RIGHT)), -sum(a * b for a, b in zip(p, UP)))


def depth(p):
    return sum(a * b for a, b in zip(p, CAM))


class Frame:
    """Fits projected points into a box of the image."""

    def __init__(self, pts, box):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        self.x0, self.y0 = min(xs), min(ys)
        w, h = max(xs) - self.x0 or 1, max(ys) - self.y0 or 1
        bx0, by0, bx1, by1 = box
        self.s = min((bx1 - bx0) / w, (by1 - by0) / h)
        self.ox = bx0 + ((bx1 - bx0) - w * self.s) / 2
        self.oy = by0 + ((by1 - by0) - h * self.s) / 2

    def __call__(self, p):
        return (self.ox + (p[0] - self.x0) * self.s, self.oy + (p[1] - self.y0) * self.s)


def cube_faces(x, y, z):
    """The three faces of the unit cube at node (x, y, z) that face the viewer, with shading."""
    a = [(x - .5, y - .5, z - .5), (x + .5, y - .5, z - .5), (x + .5, y + .5, z - .5), (x - .5, y + .5, z - .5),
         (x - .5, y - .5, z + .5), (x + .5, y - .5, z + .5), (x + .5, y + .5, z + .5), (x - .5, y + .5, z + .5)]
    return [([a[3], a[2], a[6], a[7]], 1.0),   # top
            ([a[1], a[5], a[6], a[2]], 0.78),  # east
            ([a[4], a[5], a[6], a[7]], 0.62)]  # north


def draw_cubes(d, fr, blocks):
    for b in sorted(blocks, key=lambda b: depth(b[:3])):
        col = b[3]
        for face, f in cube_faces(b[0], b[1], b[2]):
            d.polygon([fr(iso(q)) for q in face], fill=shade(col, f), outline=shade(col, 0.45))


def box_edges(size):
    sx, sy, sz = size
    c = [(x, y, z) for x in (-.5, sx - .5) for y in (-.5, sy - .5) for z in (-.5, sz - .5)]
    return [(p, q) for i, p in enumerate(c) for q in c[i + 1:] if sum(a != b for a, b in zip(p, q)) == 1]


def legend(d, y, items, x=18, size=17, right=500):
    f = font(size)
    x0 = x
    for kind, col, text in items:
        if x + 24 + d.textlength(text, font=f) > right:
            x, y = x0, y + size + 9
        if kind == "box":
            d.rectangle((x, y + 2, x + 16, y + 18), fill=col, outline=shade(col, 0.5))
        elif kind == "dot":
            d.ellipse((x + 3, y + 5, x + 13, y + 15), fill=col, outline=INK)
        elif kind == "line":
            d.line((x, y + 10, x + 18, y + 10), fill=col, width=4)
        d.text((x + 24, y), text, font=f, fill=INK)
        x += 24 + d.textlength(text, font=f) + 22
    return y


def symbol_shape(d, c, sym, col, r=9):
    x, y = c
    s = sym.lstrip("-")
    if s == "2":
        d.ellipse((x - r, y - r * .55, x + r, y + r * .55), fill=col, outline=INK)
    elif s == "3":
        d.polygon([(x, y - r), (x + r * .87, y + r * .5), (x - r * .87, y + r * .5)], fill=col, outline=INK)
    elif s == "4":
        d.rectangle((x - r * .75, y - r * .75, x + r * .75, y + r * .75), fill=col, outline=INK)
    else:
        d.ellipse((x - r * .6, y - r * .6, x + r * .6, y + r * .6), fill=col, outline=INK)


# ----------------------------------------------------------------------------- guide pictures

def region_picture(rid, R, path):
    W = H = 512
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    size = list(R["size"])
    blocks = [(b[0], b[1], b[2], YOURS if b[3] else COPY) for b in R["blocks"]]
    dots = R["dots"]
    if R["top"] and R["cell"]:
        # Three by three tiles are enough to see the pattern.
        lim = [3 * R["cell"][0], size[1], 3 * R["cell"][2]]
        size = [min(size[0], lim[0]), size[1], min(size[2], lim[2])]
        blocks = [b for b in blocks if b[0] < size[0] and b[2] < size[2]]
    if R.get("order", 0) >= 24:
        dots = [t for t in dots if t[3] != "mirrors"]
    present = set()
    if R["top"]:
        # Seen from above: x east to the right, z north up.
        def tp(p):
            return (p[0], -p[2])
        pts = [tp((-.5, 0, -.5)), tp((size[0] - .5, 0, size[2] - .5))]
        fr = Frame(pts, (24, 24, W - 24, H - 70))
        x0, y0 = fr(tp((-.5, 0, size[2] - .5)))
        x1, y1 = fr(tp((size[0] - .5, 0, -.5)))
        d.rectangle((x0, y0, x1, y1), fill=(236, 232, 220), outline=(150, 145, 130), width=2)
        if R["cell"]:
            c = R["cell"]
            for i in range(0, size[0] + 1, c[0]):
                a, b = fr(tp((i - .5, 0, -.5))), fr(tp((i - .5, 0, size[2] - .5)))
                d.line((a, b), fill=(240, 140, 30), width=2)
            for j in range(0, size[2] + 1, c[2]):
                a, b = fr(tp((-.5, 0, j - .5))), fr(tp((size[0] - .5, 0, j - .5)))
                d.line((a, b), fill=(240, 140, 30), width=2)
            present.add("cells")
        for dot in dots:
            if dot[3] == "mirrors" and dot[0] <= size[0] and dot[2] <= size[2]:
                p = fr(tp((dot[0] - .5, 0, dot[2] - .5)))
                d.ellipse((p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2), fill=hexrgb(dot[5]))
                present.add("mirrors")
        sc = fr.s
        for b in blocks:
            p = fr(tp((b[0] - .5, 0, b[2] + .5)))
            d.rectangle((p[0] + 1, p[1] + 1, p[0] + sc - 1, p[1] + sc - 1), fill=b[3], outline=shade(b[3], .45))
        seen = set()
        for dot in dots:
            if dot[3] == "axes":
                p = fr(tp((dot[0] - .5, 0, dot[2] - .5)))
                k = (round(p[0]), round(p[1]))
                if k not in seen and dot[0] < size[0] + 1 and dot[2] < size[2] + 1:
                    seen.add(k)
                    symbol_shape(d, p, dot[4], hexrgb(dot[5]), 11)
                    present.add("axis" + dot[4])
            elif dot[3] == "centres":
                p = fr(tp((dot[0] - .5, 0, dot[2] - .5)))
                d.ellipse((p[0] - 7, p[1] - 7, p[0] + 7, p[1] + 7), fill=(255, 255, 255), outline=INK, width=2)
                present.add("centre")
        d.text((W - 92, 8), "N  ↑", font=font(16, True), fill=INK)
        caption = "Seen from above"
    else:
        corners = [iso(p) for e in box_edges(size) for p in e]
        fr = Frame(corners, (20, 20, W - 20, H - 70))
        for p, q in box_edges(size):
            d.line((fr(iso(p)), fr(iso(q))), fill=(160, 155, 140), width=1)
        for dot in dots:
            kind = dot[3]
            p = fr(iso((dot[0] - .5, dot[1] - .5, dot[2] - .5)))
            col = hexrgb(dot[5])
            if kind == "cells":
                d.ellipse((p[0] - 1.2, p[1] - 1.2, p[0] + 1.2, p[1] + 1.2), fill=col)
                present.add("cells")
            elif kind == "mirrors":
                d.ellipse((p[0] - 1.6, p[1] - 1.6, p[0] + 1.6, p[1] + 1.6), fill=col)
                present.add("mirrors")
            elif kind == "axes":
                d.ellipse((p[0] - 2.4, p[1] - 2.4, p[0] + 2.4, p[1] + 2.4), fill=col)
                present.add("axis" + dot[4])
        draw_cubes(d, fr, blocks)
        for dot in dots:
            if dot[3] == "centres":
                p = fr(iso((dot[0] - .5, dot[1] - .5, dot[2] - .5)))
                d.ellipse((p[0] - 7, p[1] - 7, p[0] + 7, p[1] + 7), fill=(255, 255, 255), outline=INK, width=2)
                present.add("centre")
        caption = "Seen from above the north-east corner"
    items = [("box", YOURS, "your block(s)"), ("box", COPY, "copies")]
    names = {"mirrors": ("dot", (64, 192, 255), "mirror"), "centre": ("dot", (255, 255, 255), "centre point"),
             "cells": ("line", (240, 140, 30), "box edges"), "axis2": ("dot", (255, 215, 0), "half-turn pole"),
             "axis3": ("dot", (50, 205, 50), "third-turn pole"), "axis4": ("dot", (255, 48, 48), "quarter-turn pole"),
             "axis-4": ("dot", (176, 64, 255), "-4 pole"), "axis-3": ("dot", (50, 205, 50), "-3 pole")}
    extra = [names[k] for k in ["axis2", "axis3", "axis-3", "axis4", "axis-4", "mirrors", "centre", "cells"] if k in present]
    if legend(d, H - 62, items + extra) == H - 62:
        d.text((18, H - 30), caption, font=font(15), fill=(110, 105, 95))
    img.save(path, optimize=True)


SOLID = [(0, 0, 0), (1, 0, 0), (2, 0, 0), (0, 1, 0), (0, 2, 0), (2, 0, 1)]


def gate_picture(path):
    """The four kinds of operation, each on the same lopsided shape (not the Gate's own displays)."""
    W, H = 512, 512
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    c = (1, 1, .5)   # centre of the shape's bounding box, for turning and inverting
    ops = [
        ("Translation: slide", lambda p: (p[0] + 5, p[1], p[2])),
        ("Rotation: half turn", lambda p: (2 * c[0] - p[0] + 5, p[1], 2 * c[2] - p[2])),
        ("Reflection: mirror", lambda p: (2 * c[0] - p[0] + 5, p[1], p[2])),
        ("Inversion: via a point", lambda p: (2 * c[0] - p[0] + 5, 2 * c[1] - p[1] + 1, 2 * c[2] - p[2])),
    ]
    for i, (title, f) in enumerate(ops):
        bx, by = (i % 2) * 256, (i // 2) * 256
        blocks = [(p[0], p[1] + (1 if i == 3 else 0), p[2], YOURS) for p in SOLID] + [(*f(p), COPY) for p in SOLID]
        pts = [iso(q) for b in blocks for q in [(b[0] - .5, b[1] - .5, b[2] - .5), (b[0] + .5, b[1] + .5, b[2] + .5),
                                                 (b[0] + .5, b[1] - .5, b[2] - .5), (b[0] - .5, b[1] + .5, b[2] + .5)]]
        fr = Frame(pts, (bx + 22, by + 44, bx + 234, by + 236))
        draw_cubes(d, fr, blocks)
        d.text((bx + 14, by + 10), title, font=font(17, True), fill=INK)
    d.line((256, 8, 256, 504), fill=(200, 192, 175), width=2)
    d.line((8, 256, 504, 256), fill=(200, 192, 175), width=2)
    legend(d, H - 26, [("box", YOURS, "original"), ("box", COPY, "copy")], x=150, size=15)
    img.save(path, optimize=True)


def tryit_picture(path):
    W, H = 512, 512
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    mine = [(p[0], p[1], p[2], YOURS) for p in SOLID]
    twin = [(10 - p[0], p[1], p[2], COPY) for p in SOLID]  # mirror in the plane x = 5
    allb = mine + twin
    pts = [iso(q) for b in allb for q in [(b[0] - .5, b[1] - .5, b[2] - .5), (b[0] + .5, b[1] + 1.5, b[2] + .5)]]
    fr = Frame(pts, (40, 60, W - 40, H - 140))
    mp = [(5, -.5, -1.5), (5, -.5, 2.5), (5, 3.5, 2.5), (5, 3.5, -1.5)]
    draw_cubes(d, fr, mine)
    d.polygon([fr(iso(p)) for p in mp], fill=(200, 230, 250), outline=(64, 160, 230))
    draw_cubes(d, fr, twin)
    f = font(19, True)
    d.text((24, 16), "Your shape and its mirror twin", font=f, fill=INK)
    d.text((24, H - 110), "Lever M makes the mirror twin. Like a left and a right\nhand, no turning makes the two match: "
           "the shape is chiral.", font=font(16), fill=INK)
    legend(d, H - 44, [("box", YOURS, "your shape"), ("box", COPY, "mirror twin"), ("dot", (64, 192, 255), "mirror")])
    img.save(path, optimize=True)


# ----------------------------------------------------------------------------- exhibit pictures

def cell_picture(eid, C, title, path):
    W, H = 512, 384
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    n = C["cell"]
    atoms = C["atoms"]
    # Crystal coordinates to world: x east, y up, z north.
    corners = [(x, y, z) for x in (0, n) for y in (0, n) for z in (0, n)]
    fr = Frame([iso(c) for c in corners], (64, 74, 316, H - 40))
    for i, p in enumerate(corners):
        for q in corners[i + 1:]:
            if sum(a != b for a, b in zip(p, q)) == 1:
                d.line((fr(iso(p)), fr(iso(q))), fill=(120, 115, 100), width=2)
    if eid == "diamond":
        for i, a in enumerate(atoms):
            for b in atoms[i + 1:]:
                if sum((a[k] - b[k]) ** 2 for k in range(3)) == 3:
                    d.line((fr(iso((a[0], a[2], a[1]))), fr(iso((b[0], b[2], b[1])))), fill=(90, 90, 90), width=4)
    r = fr.s * 0.27
    kinds = []
    for a in sorted(atoms, key=lambda a: depth((a[0], a[2], a[1]))):
        col = GAME.get(C["colours"][a[3]], (150, 150, 150))
        p = fr(iso((a[0], a[2], a[1])))
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=col, outline=shade(col, .45), width=2)
        d.ellipse((p[0] - r * .45, p[1] - r * .6, p[0] - r * .05, p[1] - r * .2), fill=shade(col, 1.35))
        if a[3] not in kinds:
            kinds.append(a[3])
    d.text((18, 12), title, font=font(18, True), fill=INK)
    y = 70
    for k in kinds:
        col = GAME.get(C["colours"][k], (150, 150, 150))
        d.ellipse((352, y, 372, y + 20), fill=col, outline=shade(col, .45), width=2)
        d.text((380, y), ELEMENT_NAMES.get(k, k), font=font(16), fill=INK)
        y += 32
    d.multiline_text((352, y + 10), "One unit cell.\nAtoms on corners\nand faces are\nshared with the\nneighbouring cells.",
                     font=font(14), fill=(100, 95, 85), spacing=3)
    img.save(path, optimize=True)


# The museum's plan. These numbers repeat those in mods/crystalminer/lobby.lua (outer walls, inner
# walls with their doorways) and furniture.lua; tests/test_guides.lua checks they agree.
PLAN = {
    "outer": (-60, 60, -50, 90),
    "walls": [("z", -30, -59, 59, [-1, -41, 39]), ("x", -21, -49, -31, [-41]), ("x", 21, -49, -31, [-41]),
              ("z", -4, -59, 59, [-41, 21]), ("x", -16, -3, 59, [20]), ("z", 60, -59, 59, [-41, 21])],
    "rooms": [("Foyer", 0, -40), ("Workshop", -40, -40), ("Information", 40, -40),
              ("Gallery 1: four kinds of symmetry", 0, -17), ("Gallery 2:\nhistory", -38, 28),
              ("Gallery 3: crystals at\nthe atomic scale", 22, 28), ("Portal Hall: to the symmetry worlds", 0, 75)],
}


def plan_picture(path):
    W, H = 512, 384
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    x0, x1, z0, z1 = PLAN["outer"]
    # North up, east to the right.
    sx = (W - 60) / (x1 - x0)
    sz = (H - 70) / (z1 - z0)
    s = min(sx, sz)
    ox = (W - (x1 - x0) * s) / 2
    oy = 44

    def p(x, z):
        return (ox + (x - x0) * s, oy + (z1 - z) * s)

    d.rectangle((*p(x0, z1), *p(x1, z0)), fill=(236, 232, 220), outline=INK, width=4)
    for axis, v, a, b, doors in PLAN["walls"]:
        t = a
        while t <= b:
            if any(t == dd or t == dd + 1 for dd in doors):
                t += 1
                continue
            q0 = p(t - .5, v) if axis == "z" else p(v, t - .5)
            q1 = p(t + .5, v) if axis == "z" else p(v, t + .5)
            d.line((q0, q1), fill=INK, width=3)
            t += 1
    f = font(13, True)
    for name, x, z in PLAN["rooms"]:
        c = p(x, z)
        d.multiline_text((c[0], c[1]), name, font=f, fill=INK, anchor="mm", align="center")
    # The plan hangs in the foyer, on the south wall just east of the entrance (furniture.lua).
    you = p(7, -47)
    d.ellipse((you[0] - 6, you[1] - 6, you[0] + 6, you[1] + 6), fill=(200, 40, 40))
    door = p(-0.5, z0)
    # Both labels sit below the south wall, side by side: "entrance" ends under the door, "you are here" starts under the dot.
    d.text((door[0] + 4, door[1] + 5), "entrance", font=font(12), fill=INK, anchor="rt")
    d.text((you[0] - 4, door[1] + 5), "you are here", font=font(12, True), fill=(200, 40, 40), anchor="lt")
    d.text((16, 10), "Plan of the museum", font=font(18, True), fill=INK)
    d.text((W - 60, 10), "N \u2191", font=font(16, True), fill=INK)
    img.save(path, optimize=True)


def main(data_path):
    data = json.load(open(data_path))
    os.makedirs(OUT, exist_ok=True)
    for rid, R in data["regions"].items():
        if R["blocks"]:
            region_picture(rid, R, os.path.join(OUT, "crystalminer_guide_%s.png" % rid))
    gate_picture(os.path.join(OUT, "crystalminer_guide_symmetry_gate.png"))
    tryit_picture(os.path.join(OUT, "crystalminer_guide_tryit_pad.png"))
    titles = {"copper": "Copper: face-centred cubic", "iron": "Iron: body-centred cubic",
              "rocksalt": "Rock salt (sodium chloride)", "cscl": "Caesium chloride",
              "perovskite": "Strontium titanate (perovskite)", "diamond": "Diamond"}
    for eid, C in data["cells"].items():
        cell_picture(eid, C, titles.get(eid, eid), os.path.join(OUT, "crystalminer_fig_%s.png" % eid))
    import history
    history.main(OUT, data)
    gate_picture(os.path.join(OUT, "crystalminer_art_four.png"))
    plan_picture(os.path.join(OUT, "crystalminer_art_plan.png"))
    # Pictures that hang in the museum get a wooden frame.
    for f in os.listdir(OUT):
        if f.startswith("crystalminer_fig_") or f.startswith("crystalminer_hist_") or f.startswith("crystalminer_art_"):
            path = os.path.join(OUT, f)
            im = Image.open(path).convert("RGB")
            framed = Image.new("RGB", (im.width + 24, im.height + 24), (110, 76, 44))
            ImageDraw.Draw(framed).rectangle((6, 6, im.width + 17, im.height + 17), fill=(150, 108, 64))
            framed.paste(im, (12, 12))
            framed.save(path, optimize=True)
    print("figures written")


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(__file__))
    main(sys.argv[1])
