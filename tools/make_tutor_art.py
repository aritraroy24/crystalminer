"""Generates the art for Prism, the AI tutor at the museum's information desk (tutor_window.lua).

Needs Pillow. Writes, into mods/crystalminer/textures:
  crystalminer_tutor_avatar.png   portrait for the chat window (256 x 256)
  crystalminer_tutor_icon.png     Prism beside each answer (64 x 64)
  crystalminer_tutor_user.png     the student beside each question (64 x 64)
  crystalminer_tutor_prism.png, crystalminer_tutor_prism_face.png   the floating crystal (32 x 32)
  crystalminer_tutor_screen.png, crystalminer_tutor_case.png        the screen on the desk (32 x 32)
"""
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "mods", "crystalminer", "textures")

VIOLET = (176, 124, 255)
VIOLET_LIGHT = (214, 186, 255)
VIOLET_DARK = (104, 62, 186)
VIOLET_DEEP = (66, 36, 128)
CYAN = (120, 230, 255)
NAVY = (20, 26, 38)
INK = (30, 18, 56)


def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)


def face(d, cx, cy, s):
    """Two eyes with highlights and a smile, centred on (cx, cy); s is the eye radius."""
    for ex in (cx - 2.2 * s, cx + 2.2 * s):
        d.ellipse([ex - s, cy - 1.25 * s, ex + s, cy + 1.25 * s], fill=(255, 255, 255))
        d.ellipse([ex - 0.6 * s, cy - 0.55 * s, ex + 0.6 * s, cy + 0.95 * s], fill=INK)
        d.ellipse([ex - 0.15 * s, cy - 0.35 * s, ex + 0.3 * s, cy + 0.1 * s], fill=(255, 255, 255))
    w = 1.8 * s
    d.arc([cx - w, cy + 0.6 * s, cx + w, cy + 3.2 * s], start=20, end=160, fill=INK, width=max(2, int(0.45 * s)))
    for ex in (cx - 3.4 * s, cx + 3.4 * s):   # cheeks
        d.ellipse([ex - 0.7 * s, cy + 1.3 * s, ex + 0.7 * s, cy + 2.1 * s], fill=(255, 150, 200))


def sparkle(d, x, y, r, colour):
    d.polygon([(x, y - r), (x + r * 0.28, y - r * 0.28), (x + r, y), (x + r * 0.28, y + r * 0.28),
               (x, y + r), (x - r * 0.28, y + r * 0.28), (x - r, y), (x - r * 0.28, y - r * 0.28)], fill=colour)


def avatar(size=256):
    """Prism: an octahedral crystal seen corner-on, with a face, in a soft violet glow."""
    k = 4                                  # draw large, then shrink for smooth edges
    n = size * k
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(40, 0, -1):             # radial glow
        r = n * 0.48 * i / 40
        a = int(150 * (1 - i / 40) ** 1.5) + 10
        gd.ellipse([n / 2 - r, n / 2 - r, n / 2 + r, n / 2 + r], fill=(*VIOLET_DEEP, a))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    cx, cy = n / 2, n * 0.5
    top, bottom = (cx, n * 0.1), (cx, n * 0.9)
    left, right = (n * 0.17, cy), (n * 0.83, cy)
    front = (cx + n * 0.05, cy + n * 0.02)  # the near corner, a little off centre
    d.polygon([top, left, front], fill=VIOLET_LIGHT)
    d.polygon([top, front, right], fill=VIOLET)
    d.polygon([left, bottom, front], fill=VIOLET_DARK)
    d.polygon([front, bottom, right], fill=VIOLET_DEEP)
    edge = (240, 228, 255)
    for a, b in ((top, left), (top, right), (left, bottom), (right, bottom), (top, front), (left, front),
                 (right, front), (bottom, front)):
        d.line([a, b], fill=edge, width=k * 2)
    d.polygon([(cx - n * 0.05, n * 0.18), (cx - n * 0.02, n * 0.17), (n * 0.27, cy - n * 0.02),
               (n * 0.24, cy - n * 0.03)], fill=(255, 255, 255, 170))   # a glint on the upper face
    face(d, cx + n * 0.02, cy - n * 0.06, n * 0.04)
    sparkle(d, n * 0.84, n * 0.2, n * 0.05, (*CYAN, 255))
    sparkle(d, n * 0.16, n * 0.78, n * 0.035, (*CYAN, 230))
    sparkle(d, n * 0.78, n * 0.8, n * 0.025, (255, 255, 255, 220))
    return img.resize((size, size), Image.LANCZOS)


def user_icon(size=64):
    k = 4
    n = size * k
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, n - 1, n - 1], fill=(48, 92, 140))
    d.ellipse([n * 0.33, n * 0.17, n * 0.67, n * 0.51], fill=(159, 216, 255))   # head
    d.pieslice([n * 0.16, n * 0.56, n * 0.84, n * 1.24], 180, 360, fill=(159, 216, 255))  # shoulders
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, n - 1, n - 1], fill=255)
    img.putalpha(Image.composite(img.getchannel("A"), mask, mask))
    return img.resize((size, size), Image.LANCZOS)


def facet_texture(with_face):
    """32 x 32 pixel art for the crystal node: banded violet facets with a glint."""
    img = Image.new("RGBA", (32, 32))
    px = img.load()
    for y in range(32):
        for x in range(32):
            t = (x + y) / 62
            c = tuple(int(VIOLET_LIGHT[i] * (1 - t) + VIOLET_DARK[i] * t) for i in range(3))
            if (x - y) % 11 == 0:
                c = tuple(min(255, v + 18) for v in c)
            if x in (0, 31) or y in (0, 31):
                c = (240, 228, 255)
            px[x, y] = (*c, 255)
    d = ImageDraw.Draw(img)
    d.line([(4, 9), (9, 4)], fill=(255, 255, 255), width=2)
    if with_face:
        # Kept to rows 10 to 21: the crystal's middle band (tutor_window.lua) shows rows 9 to 23.
        for ex in (10, 19):
            d.rectangle([ex, 10, ex + 3, 14], fill=(255, 255, 255))
            d.rectangle([ex + 1, 11, ex + 2, 14], fill=INK)
            d.point((ex + 1, 11), fill=(255, 255, 255))
        d.line([(12, 18), (14, 20), (17, 20), (19, 18)], fill=INK, width=1)
        d.rectangle([7, 16, 8, 17], fill=(255, 150, 200))
        d.rectangle([23, 16, 24, 17], fill=(255, 150, 200))
    return img


def screen_texture():
    """The desk screen: a dark display with Prism's speech bubble and a question mark."""
    img = Image.new("RGBA", (32, 32), (58, 62, 74, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([2, 2, 29, 29], fill=NAVY)
    d.rounded_rectangle([5, 6, 26, 21], radius=3, fill=VIOLET)
    d.polygon([(9, 21), (14, 21), (9, 25)], fill=VIOLET)
    q = [".###.", "#...#", "...#.", "..#..", ".....", "..#.."]
    for gy, row in enumerate(q):
        for gx, ch in enumerate(row):
            if ch == "#":   # each row of the glyph is two pixels high
                d.point((13 + gx, 8 + gy * 2), fill=(255, 255, 255))
                d.point((13 + gx, 9 + gy * 2), fill=(255, 255, 255))
    d.rectangle([20, 25, 26, 26], fill=(120, 230, 255))  # a cursor-like status light
    return img


def case_texture():
    img = Image.new("RGBA", (32, 32), (70, 74, 86, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, 32, 4):
        d.line([(0, y), (31, y)], fill=(78, 82, 95))
    d.rectangle([0, 0, 31, 31], outline=(44, 47, 56))
    return img


if __name__ == "__main__":
    a = avatar()
    save(a, "crystalminer_tutor_avatar.png")
    save(a.crop((20, 20, 236, 236)).resize((64, 64), Image.LANCZOS), "crystalminer_tutor_icon.png")
    save(user_icon(), "crystalminer_tutor_user.png")
    save(facet_texture(False), "crystalminer_tutor_prism.png")
    save(facet_texture(True), "crystalminer_tutor_prism_face.png")
    save(screen_texture(), "crystalminer_tutor_screen.png")
    save(case_texture(), "crystalminer_tutor_case.png")
    print("wrote the tutor art to", os.path.normpath(OUT))
