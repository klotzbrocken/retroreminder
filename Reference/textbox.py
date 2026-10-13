#!/usr/bin/env python3
"""Tinten-Bounding-Box je Textelement: Referenz vs. App (Position, Breite, Höhe, mittlere Tintenfarbe)."""
import sys, os
from PIL import Image
import numpy as np
REF = os.environ.get("REF_IMAGE", "Reference/2012-06-18-reminders.png")   # Referenzscreenshot (nicht im Repo)
snap = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ml"
ref = np.asarray(Image.open(REF).convert("RGB").crop((57,35,798,544))).astype(float)
app = np.asarray(Image.open(f"{snap}/ref_main.png").convert("RGB").crop((0,0,741,509))).astype(float)
pr = np.asarray(Image.open(REF).convert("RGB").crop((783,41,1047,268))).astype(float)
pa = np.asarray(Image.open(f"{snap}/ref_main.png.pop.png").convert("RGB")).astype(float)
E = [("Fenstertitel", ref, app, (250,2,500,21), 40),
     ("Seitenl. Completed", ref, app, (12,62,190,92), 40),
     ("Seitenl. Tasks (gewaehlt)", ref, app, (12,96,190,126), 60),
     ("Kopf 'Tasks'", ref, app, (212,30,330,68), 60),
     ("Zeile '15'", ref, app, (213,75,253,102), 25),
     ("Zeile 'Completed'", ref, app, (255,75,450,102), 60),
     ("Aufgabentitel", ref, app, (250,108,420,124), 60),
     ("Aufgaben-Notiz", ref, app, (250,124,560,138), 25),
     ("Kal. Monat 'June'", ref, app, (80,277,150,298), 25),
     ("Kal. Wochentage", ref, app, (12,299,196,311), 25),
     ("Kal. Zeile 24-30", ref, app, (12,418,196,436), 40),
     ("Kal. '18'", ref, app, (38,390,62,410), 40),
     ("Pop. Titel", pr, pa, (10,15,250,38), 60),
     ("Pop. Beschriftung remind me", pr, pa, (10,50,108,66), 30),
     ("Pop. On a Day", pr, pa, (124,50,230,66), 60),
     ("Pop. Notiz", pr, pa, (110,120,250,185), 60)]
def ink(a, box, thr):
    x0,y0,x1,y1 = box; p = a[y0:y1, x0:x1].mean(axis=2)
    bg = np.median(p); m = np.abs(p - bg) > thr
    # kleine Ausreißer (Rauschen) ignorieren: Spalten/Zeilen mit <1 Treffer
    if m.sum() < 3: return None
    ys, xs = np.where(m)
    return xs.min()+x0, ys.min()+y0, xs.max()+x0, ys.max()+y0, p[m].mean()
print(f"{'Element':28s} {'Ref x,y  B×H  Tinte':26s} {'App x,y  B×H  Tinte':26s}  dx dy dB dH")
for n, a, b, box, thr in E:
    r, s = ink(a, box, thr), ink(b, box, thr)
    f = lambda t: "-" if t is None else f"{t[0]:3d},{t[1]:3d} {t[2]-t[0]+1:3d}×{t[3]-t[1]+1:2d} {t[4]:4.0f}"
    d = "" if r is None or s is None else f"{s[0]-r[0]:+3d}{s[1]-r[1]:+3d}{(s[2]-s[0])-(r[2]-r[0]):+3d}{(s[3]-s[1])-(r[3]-r[1]):+3d}"
    print(f"{n:28s} {f(r):26s} {f(s):26s} {d}")
