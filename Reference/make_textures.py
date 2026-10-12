#!/usr/bin/env python3
"""Erzeugt kachelbare Leder-/Papier-/Versenkungs-Texturen aus den GEMESSENEN Statistiken der Referenz
(Mittelwert, Streuung, Autokorrelation bei 1/2/3/5 px). Es werden keine Referenzpixel kopiert.
Ausgabe: Resources/leather.png, paper.png, pit.png (512 px = 256 pt @2x)."""
import numpy as np, os
from PIL import Image
REF = "/Users/maik/Downloads/Mountain Lion Reminder/2012-06-18-reminders.png"
R = np.asarray(Image.open(REF).convert("RGB")).astype(float)[35:544, 57:798].mean(axis=2)

def ac(p, ks=(1, 2, 3, 5)):
    m, s = p.mean(), p.std()
    return np.array([np.mean((p[:, :-k] - m) * (p[:, k:] - m)) / s**2 for k in ks])

def field(n, sigma, seed):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    if sigma > 0:
        f = np.fft.fftfreq(n)[:, None]**2 + np.fft.fftfreq(n)[None, :]**2
        w = np.fft.ifft2(np.fft.fft2(w) * np.exp(-2 * np.pi**2 * sigma**2 * f)).real
    return (w - w.mean()) / w.std()

def fit(target_ac, std, n=512, sigmas=(0, 0.7, 1.5, 3, 6, 12), seed=1):
    B = [field(n, s, seed + i) for i, s in enumerate(sigmas)]
    A = np.array([ac(b) for b in B]).T                      # 4 x k
    v, *_ = np.linalg.lstsq(A, target_ac, rcond=None); v = np.clip(v, 0, None)
    v = v / v.sum() * std**2
    out = sum(np.sqrt(vi) * b for vi, b in zip(v, B))
    return out, v

def patch(*boxes):
    return [R[y0:y1, x0:x1] for x0, y0, x1, y1 in boxes]

targets = {
  # Leder: Streifen unten + Lücken zwischen den Boxen (x0,y0,x1,y1 im Fensterkoordinatensystem)
  "leather": (patch((210, 503, 730, 508), (9, 262, 199, 270), (9, 52, 199, 58)), 48.3),
  # Papier: leere Zellen zwischen den Zeilenlinien
  "paper":   (patch((310, 178, 720, 200), (310, 244, 720, 266), (310, 310, 720, 332)), 238.9),
  # Versenkung (Seitenleistenliste, leere Zeilen)
  "pit":     (patch((14, 208, 195, 222), (14, 241, 195, 254)), 48.9),
}
os.makedirs("Resources", exist_ok=True)
for name, (ps, mean) in targets.items():
    s = np.mean([p.std() for p in ps]); a = np.mean([ac(p) for p in ps], axis=0)
    f, v = fit(a, s)
    img = mean + f
    if name == "paper":   # RGB leicht warm (Messung: 241/241/236)
        rgb = np.stack([img + 1.5, img + 1.5, img - 3.0], axis=2)
    else: rgb = np.stack([img] * 3, axis=2)
    Image.fromarray(np.clip(np.round(rgb), 0, 255).astype(np.uint8)).save(f"Resources/{name}.png", dpi=(144, 144))
    print(f"{name}: Ziel std {s:.2f} ac {np.round(a,2)} | erreicht std {img.std():.2f} ac {np.round(ac(img),2)}")
