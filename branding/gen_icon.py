"""Generate Monolith app launcher icons matching the README now-playing logo:
a coral gradient tile with a white serif lowercase 'm' (Georgia Bold).

Outputs:
  branding/app_icon_source.png      full-bleed 1024 coral gradient + 'm' (iOS + legacy Android)
  branding/app_icon_foreground.png  transparent 1024 with a centered 'm' (Android adaptive foreground)
"""
import os
from PIL import Image, ImageDraw, ImageFont

S = 1024
C1 = (0xFF, 0x4D, 0x5E)  # coral top-left  (#FF4D5E)
C2 = (0xC2, 0x3A, 0x48)  # deep coral bottom-right (#C23A48)
FONT = r"C:\Windows\Fonts\georgiab.ttf"  # Georgia Bold (serif, matches hero)
HERE = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size):
    # Build a small gradient and upscale (smooth, fast).
    n = 256
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            px[x, y] = lerp(C1, C2, (x + y) / (2 * (n - 1)))
    return g.resize((size, size), Image.BILINEAR)


def fit_font(draw, target_w):
    # Pick a Georgia-Bold size so the 'm' glyph is ~target_w wide.
    size = 100
    f = ImageFont.truetype(FONT, size)
    b = draw.textbbox((0, 0), "m", font=f)
    w = b[2] - b[0]
    size = int(size * target_w / w)
    return ImageFont.truetype(FONT, size)


def draw_m(img, target_w, fill):
    draw = ImageDraw.Draw(img)
    font = fit_font(draw, target_w)
    b = draw.textbbox((0, 0), "m", font=font)
    w, h = b[2] - b[0], b[3] - b[1]
    x = (S - w) / 2 - b[0]
    y = (S - h) / 2 - b[1]
    draw.text((x, y), "m", font=font, fill=fill)


# Full-bleed icon (iOS rounds the corners itself; legacy Android uses as-is).
src = diagonal_gradient(S)
draw_m(src, target_w=int(S * 0.56), fill=(255, 255, 255))
src.save(os.path.join(HERE, "app_icon_source.png"))

# Adaptive foreground: just the glyph, kept inside the safe zone.
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_m(fg, target_w=int(S * 0.46), fill=(255, 255, 255, 255))
fg.save(os.path.join(HERE, "app_icon_foreground.png"))

print("wrote app_icon_source.png and app_icon_foreground.png")
