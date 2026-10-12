#!/usr/bin/env python3
"""Window captures: rounded corners + soft shadow on transparent background; popover: shadow around the shape."""
import sys, os
from PIL import Image, ImageDraw, ImageFilter
src = sys.argv[1]; out = os.path.join(os.path.dirname(__file__), "screenshots")
def shadowed(im, radius):
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    im.putalpha(mask)
    pad = 60; canvas = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0)); sh.paste((0, 0, 0, 120), (pad, pad + 14), mask)
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(22)))
    canvas.alpha_composite(im, (pad, pad)); return canvas
for n in ("hero", "german-ui", "completed", "lists", "search", "compact", "list-window", "settings"):
    f = f"{src}/{n}.png"
    if os.path.exists(f): shadowed(Image.open(f), 24).save(f"{out}/{n}.png", optimize=True)
p = f"{src}/popover.png.pop.png"
if os.path.exists(p):
    im = Image.open(p).convert("RGBA"); pad = 40
    canvas = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0)); canvas.alpha_composite(im, (pad, pad))
    canvas.save(f"{out}/popover.png", optimize=True)
