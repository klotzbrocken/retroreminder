#!/usr/bin/env python3
"""Vertikale Mittelwertprofile Referenz vs. App für Messstreifen (Verlaufsabgleich)."""
import sys
from PIL import Image
import numpy as np
snap = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ml"
ref = np.asarray(Image.open("/Users/maik/Downloads/Mountain Lion Reminder/2012-06-18-reminders.png").convert("RGB").crop((57,35,798,544))).astype(float)
app = np.asarray(Image.open(f"{snap}/ref_main.png").convert("RGB").crop((0,0,741,509))).astype(float)
pop_r = np.asarray(Image.open("/Users/maik/Downloads/Mountain Lion Reminder/2012-06-18-reminders.png").convert("RGB").crop((783,41,1047,268))).astype(float)
pop_a = np.asarray(Image.open(f"{snap}/ref_main.png.pop.png").convert("RGB")).astype(float)
S = [("Titelleiste x500-600", ref, app, (500,600), (0,26)),
     ("Suchfeld x60-140", ref, app, (60,140), (24,54)),
     ("Rot gewaehlt x100-190", ref, app, (100,190), (92,130)),
     ("Knoepfe x12-36", ref, app, (12,36), (478,508)),
     ("Paper-Kopf x400-600", ref, app, (400,600), (24,50)),
     ("Popover x150-250", pop_r, pop_a, (150,250), (0,227))]
for n, a, b, (x0,x1), (y0,y1) in S:
    A = a[y0:y1, x0:x1].mean(axis=(1,2)); B = b[y0:y1, x0:x1].mean(axis=(1,2))
    print(n); print(" y  ref  app  diff")
    for i in range(0, y1-y0, 2 if y1-y0 > 60 else 1):
        d = B[i]-A[i]; print(f"{y0+i:3d} {A[i]:5.1f} {B[i]:5.1f} {d:+5.1f}" + ("  <<" if abs(d) > 6 else ""))
