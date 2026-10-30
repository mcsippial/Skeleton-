#!/usr/bin/env python3
"""Draws the app icon (1024x1024) into the asset catalog: a black spine of rounded
vertebrae inside a thin iridescent ring on a near-white glow. Run: python3 tools/gen_icon.py"""
import math, pathlib
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # draw at 4x, downsample for smooth edges
img = Image.new("RGB", (S, S), (244, 244, 246))

# Soft white radial glow.
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((S * 0.12, S * 0.08, S * 0.88, S * 0.84), fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, glow)

# Iridescent ring (pink → amber → mint → sky → violet).
stops = [(255, 138, 138), (255, 210, 122), (159, 240, 184), (127, 214, 255), (183, 156, 255), (255, 158, 229), (255, 138, 138)]
def iridescent(t):
    t = t % 1 * (len(stops) - 1)
    i = int(t); f = t - i
    a, b = stops[i], stops[i + 1]
    return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))
ring = ImageDraw.Draw(img)
cx = cy = S / 2
r, w = S * 0.36, S * 0.016
for deg in range(0, 3600):
    a = math.radians(deg / 10)
    x, y = cx + r * math.cos(a), cy + r * math.sin(a)
    ring.ellipse((x - w, y - w, x + w, y + w), fill=iridescent(deg / 3600 + 0.1))

# Spine: stacked vertebrae with a gentle S-curve, widening toward the bottom.
d = ImageDraw.Draw(img)
n = 7
top, bottom = S * 0.27, S * 0.73
gap = S * 0.014
h = (bottom - top - gap * (n - 1)) / n
for i in range(n):
    t = i / (n - 1)
    y0 = top + i * (h + gap)
    x = cx + S * 0.03 * math.sin(t * math.pi * 1.5 - 0.3)
    half_w = S * (0.055 + 0.04 * t)
    d.rounded_rectangle((x - half_w, y0, x + half_w, y0 + h), radius=h * 0.42, fill=(11, 11, 12))
    # Transverse processes as small wings.
    wing_w, wing_h = S * 0.03, h * 0.38
    yc = y0 + h / 2
    d.rounded_rectangle((x - half_w - wing_w, yc - wing_h / 2, x - half_w + h * 0.3, yc + wing_h / 2), radius=wing_h / 2, fill=(11, 11, 12))
    d.rounded_rectangle((x + half_w - h * 0.3, yc - wing_h / 2, x + half_w + wing_w, yc + wing_h / 2), radius=wing_h / 2, fill=(11, 11, 12))

out = pathlib.Path(__file__).resolve().parent.parent / "App/Skeleton/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.resize((1024, 1024), Image.LANCZOS).save(out)
print("wrote", out)
