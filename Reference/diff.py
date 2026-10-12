#!/usr/bin/env python3
"""Pixel-Diff pro Komponente: Referenz (Ars Technica, 18.06.2012) gegen -ref-Snapshot der App.
Aufruf: python3 Reference/diff.py [ordner-mit-snapshots]   Ausgabe: Reference/out/*.png + report.md
Kriterium (Lastenheft 12.2): Anteil Pixel mit >8/255 Abweichung in einem Kanal je Komponente, Ausrichtung ±2 px frei."""
import sys, os
from PIL import Image, ImageChops
import numpy as np
REF = "/Users/maik/Downloads/Mountain Lion Reminder/2012-06-18-reminders.png"
snap = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ml"
out = os.path.join(os.path.dirname(__file__), "out"); os.makedirs(out, exist_ok=True)
ref_full = Image.open(REF).convert("RGB")
ref = ref_full.crop((57, 35, 798, 544))                      # Fenster, Ursprung links oben
app = Image.open(f"{snap}/ref_main.png").convert("RGB").crop((0, 0, 741, 509))
pop_ref = ref_full.crop((783, 41, 1047, 268))
pop_app = Image.open(f"{snap}/ref_main.png.pop.png").convert("RGB")
# (Name, Bild-Paar, Box x0,y0,x1,y1 im jeweiligen Koordinatensystem)
W = [("Titelleiste", ref, app, (0, 0, 741, 22)),
     ("Suchfeld", ref, app, (9, 27, 199, 50)),
     ("Seitenleiste-Liste", ref, app, (9, 59, 199, 261)),
     ("Minikalender", ref, app, (9, 272, 199, 473)),
     ("Untere Knoepfe", ref, app, (9, 481, 175, 505)),
     ("Papier-Kopf (Titel+Plus)", ref, app, (209, 25, 731, 71)),
     ("Zeile Completed", ref, app, (215, 72, 725, 104)),
     ("Aufgabenzeile", ref, app, (215, 105, 725, 138)),
     ("Leerzeilen/Randlinie", ref, app, (215, 140, 725, 492)),
     ("Gesamtfenster", ref, app, (0, 0, 741, 509)),
     ("Popover", pop_ref, pop_app, (0, 0, 264, 227))]
rows = []
def cmp(a, b, box, dx, dy):
    x0, y0, x1, y1 = box
    A = np.asarray(a.crop(box)).astype(int)
    B = np.asarray(b.crop((x0 + dx, y0 + dy, x1 + dx, y1 + dy))).astype(int)
    if A.shape != B.shape: return None
    d = np.abs(A - B).max(axis=2)
    return (d > 8).mean() * 100, np.abs(A - B).mean(), A, B
for name, r, a, box in W:
    best = None
    for dx in range(-2, 3):
        for dy in range(-2, 3):
            c = cmp(r, a, box, dx, dy)
            if c and (best is None or c[0] < best[0][0]): best = (c, dx, dy)
    c, dx, dy = best
    raw = cmp(r, a, box, 0, 0)
    rows.append((name, raw[0], c[0], c[1], dx, dy))
    x0, y0, x1, y1 = box
    ra, ap = r.crop(box), a.crop((x0 + dx, y0 + dy, x1 + dx, y1 + dy))
    diff = ImageChops.difference(ra, ap).point(lambda v: min(255, v * 4))
    ov = Image.blend(ra, ap, 0.5)
    sheet = Image.new("RGB", (ra.width * 4 + 30, ra.height), "white")
    for i, im in enumerate([ra, ap, ov, diff]): sheet.paste(im, (i * (ra.width + 10), 0))
    s = 2 if ra.width < 400 else 1
    sheet.resize((sheet.width * s, sheet.height * s), Image.NEAREST).save(f"{out}/{name.replace('/','_').replace(' ','_')}.png")
with open(f"{out}/report.md", "w") as f:
    f.write("| Komponente | >8/255 roh % | >8/255 beste Ausrichtung % | mittl. Abw. | Versatz |\n|---|---|---|---|---|\n")
    for n, raw, b, m, dx, dy in rows: f.write(f"| {n} | {raw:.1f} | {b:.1f} | {m:.1f} | ({dx},{dy}) |\n")
print(open(f"{out}/report.md").read())
