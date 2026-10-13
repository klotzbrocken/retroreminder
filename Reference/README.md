# Referenzvergleich (Ars Technica, 18. Juni 2012)

Erzeugen:
```
./build.sh
"build/RetroReminder.app/Contents/MacOS/RetroReminder" -demo -ref -date=2012-06-18 -AppleLanguages "(en)" -AppleLocale en_US -snap=/tmp/ml/ref_main.png -pop -quit
python3 Reference/diff.py /tmp/ml      # Diff
python3 Reference/profile.py /tmp/ml   # Verlaufs-Zeilenprofile
python3 Reference/make_textures.py     # Texturen aus gemessenen Statistiken neu erzeugen
```
Ergebnis: `out/report.md`, je Komponente ein Blatt (Referenz | App | Überlagerung | Differenz ×4) in `out/`.

## Messmethodik
- Snapshots werden nach sRGB konvertiert (sonst verschiebt das Display-Farbprofil alle Grauwerte um 3–5 Stufen).
- Verläufe (Titelleiste, Suchfeld, Seitenleisten-Auswahl, Lederknöpfe, Popover) sind aus zeilenweisen Mittelwerten der Referenz abgeleitet (`profile.py`), Texturen aus Statistik (Mittel, Streuung, Autokorrelation) – es werden keine Referenzpixel kopiert.
- Referenzaufnahme zeigt das Fenster inaktiv (Popover ist Key); `-ref` rendert deshalb inaktiv.

## Stand (Pixel-Diff)
| Komponente | >8/255 roh % | >8/255 beste Ausrichtung % | mittl. Abw. | Versatz |
|---|---|---|---|---|
| Titelleiste | 15.8 | 15.7 | 7.5 | (1,0) |
| Suchfeld | 10.1 | 10.1 | 3.0 | (0,0) |
| Seitenleiste-Liste | 6.1 | 6.1 | 3.4 | (1,0) |
| Minikalender | 23.5 | 20.3 | 8.2 | (0,2) |
| Untere Knoepfe | 32.7 | 30.7 | 11.8 | (1,0) |
| Papier-Kopf (Titel+Plus) | 12.9 | 12.5 | 6.1 | (-2,0) |
| Zeile Completed | 8.8 | 8.8 | 5.3 | (0,0) |
| Aufgabenzeile | 28.1 | 25.7 | 10.9 | (-1,-2) |
| Leerzeilen/Randlinie | 4.8 | 3.2 | 3.0 | (-1,-2) |
| Gesamtfenster | 12.6 | 12.6 | 7.0 | (0,0) |
| Popover | 21.2 | 20.0 | 17.4 | (-1,-1) |

## Schrift (Tinten-Bounding-Box, `textbox.py`)
```
Element                      Ref x,y  B×H  Tinte        App x,y  B×H  Tinte         dx dy dB dH
Fenstertitel                 338,  5  65×11  162        338,  6  65×10  148         +0 +1 +0 -1
Seitenl. Completed            19, 71  63×12  139         20, 71  63×13  142         +1 +0 +0 +1
Seitenl. Tasks (gewaehlt)     19,104  33× 9  163         19,105  34×10  160         +0 +1 +1 +1
Kopf 'Tasks'                 221, 42  68×21  104        220, 42  67×20  122         -1 +0 -1 -1
Zeile '15'                   215, 75  25×27  187        215, 79  23×14  200         +0 +4 -2-13
Zeile 'Completed'            255, 83  62×13  111        255, 83  62×13  122         +0 +0 +0 +0
Aufgabentitel                256,111 126×10  113        255,111 127× 9  119         -1 +0 +1 -1
Aufgaben-Notiz               250,125 309×13  187        254,124 306×12  193         +4 -1 -3 -1
Kal. Monat 'June'             85,281  34×12  130         85,282  34×11  128         +0 +1 +0 -1
Kal. Wochentage               18,300 173× 8  121         18,301 173× 7  111         +0 +1 +0 -1
Kal. Zeile 24-30              16,425 176×10  144         15,427 177× 9  135         -1 +2 +1 -1
Kal. '18'                     44,397  14×12  167         42,400  16×10  156         -2 +3 +2 -2
Pop. Titel                    26, 19 167×12   50         26, 19 167×13   61         +0 +0 +0 +1
Pop. Beschriftung remind me   42, 56  59× 8  159         45, 53  54× 9  181         +3 -3 -5 +1
Pop. On a Day                126, 54  46×10   75        125, 53  46×11  126         -1 -1 +0 +1
Pop. Notiz                   110,133 108×52   77        110,132 107×50  108         +0 -1 -1 -2
```
Zeile '15' und Notizzeile der Aufgabe sind durch Linien in der Messbox verfälscht.
Fensterknöpfe: Ø 12 px, Mitte y=11, Abstand 20 px, Zeilenprofile (R/G/B) und Reflexion aus der Referenz gemessen; Fensterrand: weiche Lichtkante statt schwarzem Strich.
Kriterium Lastenheft 12.2 (≤ 1 %) bleibt nicht erfüllt.

**Referenzbild:** Der Screenshot `2012-06-18-reminders.png` (Ars Technica) ist nicht im Repo. Pfad per Umgebungsvariable angeben: `REF_IMAGE=/Pfad/zum/Bild.png python3 Reference/diff.py`.
