# VoiceOver-Prüfliste (manuell, ca. 10 Minuten)

Vorbereitung: VoiceOver mit ⌘F5 einschalten, App starten (`-demo` für Beispieldaten ist nicht nötig). Mit VO = Control+Option bedienen.
Automatisch geprüft (`-axdump`): alle 57 bedienbaren Elemente haben Namen/Wert, Seitenleiste kommt vor dem Papier, Standardaktion einer Aufgabe wirkt.
**Nicht automatisch prüfbar** (hier bitte hören): Wortlaut, Reihenfolge der Ansagen, Fokusführung.

| Schritt | Erwartung |
|---|---|
| VO+→ vom Fenster aus | „Seitenleiste“ → „Suche, Suchfeld“ → „Listen“ → Listeneinträge („Erledigt“, „Aufgaben, ausgewählt“ …) |
| Weiter in den Kalender | „Kalender“, „Vorheriger Monat“, „Nächster Monat“, danach Tage mit vollem Datum, z. B. „Montag, 12. Oktober 2026, heute, hat Erinnerungen“ |
| Zu den drei Knöpfen | „Kompaktansicht“, „Kalender ein- oder ausblenden“, „Neue Liste“ (alle als Taste) |
| In den Bereich „Erinnerungen“ | Überschrift = Listenname, „Neue Erinnerung“, „Erledigt, 3, ausgeblendet“ |
| Auf eine Aufgabe | „Priorität Hoch, <Titel>“, „offen, überfällig, Gestern 21:29“ (Priorität/Überfällig sind Text, nicht nur Farbe) |
| VO+Leertaste auf der Aufgabe | Aufgabe wird erledigt; Ansage „Erledigt: <Titel>“ |
| VO+Befehl+Leertaste (Aktionenmenü) | „Informationen“, „Titel bearbeiten“, „Löschen“ |
| „Informationen“ ausführen | Popover öffnet; Fokus im Titelfeld („Titel“); weiter: „erinnern“, „An einem Tag, Schalter, aus“, „Priorität“, „Notiz“, „Fertig“ |
| Esc im Popover | schließt und speichert |
| ⌘N | „Neue Erinnerung“, Eingabefeld ist fokussiert |
| Tab / ⇧Tab | Zonenwechsel Suche → Listen → Kalender → Knöpfe → Plus → Papier (VO sagt jeweils den Namen) |

Abweichungen bitte mit Schritt-Nummer notieren – Fixes sitzen in `Paper.swift` (Aufgaben), `Views.swift` (Seitenleiste/Kalender), `Detail.swift` (Popover).
