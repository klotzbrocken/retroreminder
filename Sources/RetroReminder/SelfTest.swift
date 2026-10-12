import Foundation
import AppKit

/// `RetroReminder -selftest` : prüft Kernlogik (Datumsparser, Serien, Erledigen/Wiederöffnen). Exit 0 = ok.
enum SelfTest {
    static func run() -> Int32 {
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { fails += 1 } }
        let s = Store(demo: true)
        let l = s.sortedLists[0].id
        let cal = Calendar.current

        // Parser (Lastenheft 6.3): erkannter Teil wandert in die Fälligkeit, Rest bleibt Titel
        var t = Task(listID: l, title: isDE ? "Paket abholen morgen um 18:30" : "Call Alex tomorrow at 10am")
        s.parseDate(in: &t)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        check(t.due != nil && cal.isDate(t.due!, inSameDayAs: tomorrow), "Parser: Datum = morgen")
        check(t.hasTime && cal.component(.hour, from: t.due ?? Date()) == (isDE ? 18 : 10), "Parser: Uhrzeit erkannt")
        check(t.title == (isDE ? "Paket abholen" : "Call Alex"), "Parser: Titel ohne Zeitangabe (\(t.title))")
        var plain = Task(listID: l, title: "Milch kaufen"); s.parseDate(in: &plain)
        check(plain.due == nil && plain.title == "Milch kaufen", "Parser: ohne Datum unverändert")

        // Serie: Monatsende → gültiger Tag; genau ein Nachfolger; Wiederöffnen räumt auf
        var r = Task(listID: l, title: "Miete"); r.repeatRule = .monthly; r.hasTime = false
        r.due = cal.date(from: DateComponents(year: 2024, month: 1, day: 31, hour: 9))
        let id = s.addTask(in: l, title: "x"); var x = s.task(id)!; x.title = r.title; x.repeatRule = .monthly; x.due = r.due; x.hasTime = false; s.update(x)
        s.setDone(id, true)
        let open = s.tasks.filter { $0.title == "Miete" && !$0.done }
        check(open.count == 1, "Serie: genau ein Nachfolger")
        let od = open.first!.due!, dim = cal.range(of: .day, in: .month, for: od)!.count
        check(cal.component(.day, from: od) == min(31, dim), "Serie: Ankertag 31 bleibt 31 (bzw. letzter Tag des Monats), nicht auf 29 gedriftet")
        s.setDone(id, false)
        check(s.tasks.filter { $0.title == "Miete" }.count == 1, "Serie: Wiederöffnen entfernt Nachfolger (kein Duplikat)")

        // Alarm: Datum ohne Uhrzeit → 09:00, nie Mitternacht
        var d = Task(listID: l); d.due = cal.startOfDay(for: tomorrow); d.hasTime = false
        check(d.alarmDate.map { cal.component(.hour, from: $0) == 9 } == true, "Alarm: Datum ohne Zeit → 09:00")

        // Undo stellt lokale Daten exakt wieder her
        let before = s.tasks.count; s.addTask(in: l, title: "tmp"); s.undo()
        check(s.tasks.count == before, "Undo: Aufgabe weg")
        // Kompaktmodus: Seiten = Erledigt + Listen; Wischen/Punkte wechseln, Ränder bleiben stehen, Tagesansicht → erste Liste
        let b = s.addList("B")
        let v = ViewState(store: s); v.sel = [l]; v.mode = .lists
        check(v.pages.count == 1 + s.lists.count, "Kompakt: Seitenzahl = Erledigt + \(s.lists.count) Listen")
        v.step(1); check(v.currentPage == .list(b) || v.currentPage == ViewState.Page.list(s.sortedLists[1].id), "Kompakt: Schritt vor → nächste Liste")
        v.step(1); v.step(1); v.step(1); check(v.currentPage == .list(s.sortedLists.last!.id), "Kompakt: am Ende bleibt es stehen")
        v.go(.completed); v.step(-1); check(v.currentPage == .completed, "Kompakt: am Anfang bleibt es stehen")
        v.mode = .day(Date()); v.step(1); check(v.currentPage != nil, "Kompakt: aus Tagesansicht zurück auf eine Seite")
        // Mitziehen: kurzes Wischen = Abbruch, langes = ganze Seite, an den Enden Gummiband
        v.go(.list(s.sortedLists[0].id)); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let p0 = v.currentPage
        v.swipeChanged(-30); check(v.dragX == -30, "Wischen: Seite folgt dem Finger")
        v.swipeEnded(-30); RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        check(v.currentPage == p0 && v.dragX == 0, "Wischen: unter Schwelle = Abbruch, Seite unverändert")
        v.swipeEnded(-100); RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        check(v.currentPage != p0 && v.dragX == 0, "Wischen: über Schwelle = nächste Seite, Versatz zurückgesetzt")
        v.go(.list(s.sortedLists.last!.id)); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        v.swipeChanged(-500); check(abs(v.dragX) <= 40, "Wischen: am Ende Gummiband statt freiem Mitziehen")
        v.swipeEnded(-500); RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        check(v.currentPage == .list(s.sortedLists.last!.id) && v.dragX == 0, "Wischen: am Ende kein Seitenwechsel, Rückfedern")
        // Listenfenster: gleicher Datenbestand in zwei Fenstern
        let w1 = ViewState(store: s), w2 = ViewState(store: s, single: true); w1.sel = [l]; w2.sel = [l]; w2.mode = .lists
        let nid = s.addTask(in: l, title: "geteilt")
        check(w1.flat.contains { $0.id == nid } && w2.flat.contains { $0.id == nid }, "Listenfenster: neue Aufgabe in beiden Fenstern")
        s.setDone(nid, true)
        check(!w1.flat.contains { $0.id == nid } && !w2.flat.contains { $0.id == nid }, "Listenfenster: Erledigen wirkt in beiden Fenstern")
        w2.sel = [b]; check(w1.effectiveSel == [l] && w2.effectiveSel == [b], "Listenfenster: Auswahl pro Fenster unabhängig")
        // App-Symbol-Einstellung: nur exakt 256×256-PNG wird angenommen; Zurücksetzen entfernt es
        _ = NSApplication.shared
        func png(_ w: Int, _ h: Int, jpeg: Bool = false) -> URL {
            let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("icon-\(w)x\(h).\(jpeg ? "jpg" : "png")")
            try? r.representation(using: jpeg ? .jpeg : .png, properties: [:])?.write(to: u); return u
        }
        AppIcon.override = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-AppIcon.png"); try? FileManager.default.removeItem(at: AppIcon.override!)
        check((try? AppIcon.validate(png(256, 256))) != nil, "Symbol: 256×256-PNG wird akzeptiert")
        check((try? AppIcon.validate(png(128, 128))) == nil, "Symbol: falsche Größe wird abgelehnt")
        check((try? AppIcon.validate(png(512, 256))) == nil, "Symbol: nicht quadratisch wird abgelehnt")
        check((try? AppIcon.validate(png(256, 256, jpeg: true))) == nil, "Symbol: JPEG mit 256×256 wird abgelehnt (kein PNG)")
        check((try? AppIcon.set(from: png(256, 256))) != nil && AppIcon.hasCustom, "Symbol: Übernahme legt Kopie an")
        try? AppIcon.set(from: png(100, 100)); check(AppIcon.hasCustom, "Symbol: fehlgeschlagene Auswahl lässt das bisherige Symbol unberührt")
        AppIcon.reset(); check(!AppIcon.hasCustom, "Symbol: Zurücksetzen entfernt das eigene Symbol")
        AppIcon.override = nil
        print(fails == 0 ? "ALLE TESTS OK" : "\(fails) FEHLER")
        return fails == 0 ? 0 : 1
    }
}
