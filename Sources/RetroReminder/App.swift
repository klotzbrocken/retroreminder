import SwiftUI
import AppKit

/// Wiederherstellung (LIS-05): Fensterrahmen, Kompaktmodus, gewählte Liste(n)/Ansicht je Fenster.
struct WinState: Codable {
    var frame: String, compact: Bool, normalWidth: Double?, mode: String, sel: [UUID], showDone: Bool
}
struct AppState: Codable { var main: WinState?; var lists: [WinState] = [] }

final class MLWindow: NSWindow {
    // SwiftUI (NSHostingView) setzt min/maxSize des Fensters selbst zurück – deshalb eigene Grenzen, vom Delegate erzwungen.
    var minLimit = NSSize(width: 0, height: 0), maxLimit = NSSize(width: 10000, height: 10000)
    var restoreFrame: NSRect?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Fensterinhalt als sRGB-PNG, immer 1 Pixel je Punkt (unabhängig vom Bildschirm), für Referenzvergleiche.
func snapshotPNG(_ v: NSView, to path: String) {
    let sc = CommandLine.arguments.first(where: { $0.hasPrefix("-scale=") }).flatMap { Int($0.dropFirst(7)) } ?? 1     // -scale=2 für Retina-Bilder (README)
    let w = Int(v.bounds.width.rounded()) * sc, h = Int(v.bounds.height.rounded()) * sc
    guard let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    r.size = v.bounds.size
    v.cacheDisplay(in: v.bounds, to: r)
    try? (r.converting(to: .sRGB, renderingIntent: .default) ?? r).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var store: Store!
    var main: (NSWindow, ViewState)?
    var others: [(NSWindow, ViewState)] = []
    var quitting = false
    private var saveItem: DispatchWorkItem?
    var normalWidth: CGFloat = 741
    let demo = CommandLine.arguments.contains("-demo")
    let testState = CommandLine.arguments.contains("-teststate")      // Selbsttest der Wiederherstellung: eigener Schlüssel, auch im Demo-Modus
    var persist: Bool { !demo || testState }
    var stateKey: String { testState ? "windows-test" : "windows" }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: u) { NSApp.applicationIconImage = img }   // Dock sofort, unabhängig vom Icon-Cache
        AppIcon.apply()                                                                                                                       // eigenes 256×256-PNG aus den Einstellungen, falls gewählt
        store = Store(demo: demo)
        buildMenu()
        openMain()
        if persist, let st = loadState() {
            for l in st.lists { let nv = ViewState(store: store, single: true); restore(l, into: nv); openListWindow(nv, frame: NSRectFromString(l.frame)) }
        }
        NSApp.activate(ignoringOtherApps: true)
        // Tab / ⇧Tab: Zonenwechsel in Fenstern der App (nicht im Popover – dort gilt die normale Feldfolge)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 48, e.modifierFlags.intersection([.command, .option, .control]).isEmpty, let w = e.window, let vs = self?.vsFor(w) else { return e }
            vs.tab(back: e.modifierFlags.contains(.shift)); return nil
        }
        if let a = CommandLine.arguments.first(where: { $0.hasPrefix("-snap=") }) {   // Entwickler-Hilfe: Fensterinhalt als PNG
            let path = String(a.dropFirst(6))
            if CommandLine.arguments.contains("-ref") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in main?.1.active = false } }   // Referenz: Fenster inaktiv (Popover ist Key)
            if let m = CommandLine.arguments.first(where: { $0.hasPrefix("-mode=") }), let vs = main?.1 {   // Aufnahme-Hilfe: Ansicht vorwählen
                switch m.dropFirst(6) { case "completed": vs.mode = .completed; case "day": vs.mode = .day(shownToday); case "search": vs.query = "Mil"; case "multi": vs.sel = Set(store.lists.map(\.id)); case "done": vs.showDone = true; default: break }
            }
            if CommandLine.arguments.contains("-active") { NSApp.activate(ignoringOtherApps: true); main?.0.makeKeyAndOrderFront(nil) }   // Ampel farbig (aktives Fenster)
            if CommandLine.arguments.contains("-keytest") { runKeyTest(); return }
            if CommandLine.arguments.contains("-axdump") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.axDump() }; return }
            if CommandLine.arguments.contains("-listwindow") { newListWindow() }
            if CommandLine.arguments.contains("-prefs") { showPreferences() }
            if CommandLine.arguments.contains("-compact") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in main?.1.compact = true } }
            if CommandLine.arguments.contains("-popfull"), let t = store.tasks.first {
                var x = t; x.due = Date(); x.hasTime = true; x.repeatRule = .weekly; x.locationOn = true; x.address = "Hauptstraße 1, Berlin"; store.update(x)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (CommandLine.arguments.contains("-compact") ? 2.5 : 1.5)) { [self] in
                if testState { print("STATE main", main!.0.frame, "compact", main!.1.compact, "mode", main!.1.mode, "sel", main!.1.sel.count, "| listenfenster", others.map { ($0.0.frame, $0.1.mode) }) }
                if CommandLine.arguments.contains("-limits"), let w = main?.0 {
                    print("DELEGATE", w.delegate as AnyObject, "MIN", w.minSize, "MAX", w.maxSize, "resizable", w.styleMask.contains(.resizable))
                    print("WILLRESIZE", w.delegate?.windowWillResize?(w, to: NSSize(width: 50, height: 50)) as Any)
                    print("FRAME0", w.frame)
                    w.zoom(nil); RunLoop.current.run(until: Date().addingTimeInterval(1)); print("ZOOM1", w.frame, w.isZoomed)
                    w.zoom(nil); RunLoop.current.run(until: Date().addingTimeInterval(1)); print("ZOOM2", w.frame, w.isZoomed)
                }
                if let v = (CommandLine.arguments.contains("-prefs") ? prefsWindow : CommandLine.arguments.contains("-listwindow") ? others.last?.0 : main?.0)?.contentView?.superview ?? main?.0.contentView { snapshotPNG(v, to: path) }
                if CommandLine.arguments.contains("-pop"), let vs = main?.1, let t = store.tasks.first, let w = main?.0 {
                    PopoverController.shared.show(taskID: t.id, store: store, vs: vs, rowFrame: CGRect(x: 0, y: 143, width: 721, height: 33))
                    _ = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if let v = PopoverController.shared.snapshotView { snapshotPNG(v, to: path + ".pop.png") }
                        if CommandLine.arguments.contains("-quit") { NSApp.terminate(nil) }
                    }
                    return
                }
                if CommandLine.arguments.contains("-quit") { NSApp.terminate(nil) }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.store.alarms.rescheduleAll(self?.store.tasks ?? [])   // nach Aufwachen/Reaktivieren abgleichen
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { if !f { openMain() }; return true }

    func makeWindow(_ vs: ViewState, size: NSSize, autosave: String?) -> NSWindow {
        // Echtes Systemfenster: native Ampel (Größe/Verhalten wie im System), Inhalt reicht unter die transparente Titelleiste.
        let w = MLWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        // Systemampel unverändert (Hover-Symbole, Größe, Zustände): Platzierung übernimmt das System über einen leeren Toolbar-Stil
        let tb = NSToolbar(identifier: "main"); tb.allowsUserCustomization = false; tb.displayMode = .iconOnly
        w.toolbar = tb; w.toolbarStyle = .unifiedCompact
        w.backgroundColor = NSColor(white: 48 / 255, alpha: 1)
        w.delegate = self
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: RootView(vs: vs, store: store))
        host.sceneBridgingOptions = []
        host.sizingOptions = []                                   // SwiftUI soll die Fenstergröße nicht bestimmen
        w.contentView = host
        w.setFrame(NSRect(origin: .zero, size: size), display: false)   // Fenstergröße = Inhaltsgröße (Inhalt reicht unter die Titelleiste)
        applyLimits(w, compact: vs.compact)
        vs.window = w
        if let a = autosave, !w.setFrameUsingName(a) { w.center() } else if autosave == nil { w.center() }
        if let a = autosave { w.setFrameAutosaveName(a) }
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { _ in vs.active = true }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { _ in vs.active = false }
        nc.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in w.invalidateShadow(); self?.scheduleSave() }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in self?.scheduleSave() }
        vs.objectWillChange.debounce(for: .milliseconds(400), scheduler: DispatchQueue.main).sink { [weak self] _ in self?.scheduleSave() }.store(in: &bag)
        return w
    }

    // Größenbegrenzung: Lastenheft 12.2 (Testgrößen 600×450 … 1000×700); Kompaktmodus ist ein schmales Einzelspaltenfenster.
    // ponytail: Werte sind Testvorgaben, nicht am Original gemessen (M1) – hier zentral anpassen.
    static let normalMin = NSSize(width: 440, height: 450), normalMax = NSSize(width: 1000, height: 700)
    static let compactMin = NSSize(width: 300, height: 300), compactMax = NSSize(width: 360, height: 700)
    func applyLimits(_ w: NSWindow, compact: Bool) {
        // Fenster == Inhalt (fullSizeContentView), daher Rahmen-Grenzen
        let lo = compact ? Self.compactMin : Self.normalMin, hi = compact ? Self.compactMax : Self.normalMax
        w.minSize = lo; w.maxSize = hi
        if let m = w as? MLWindow { m.minLimit = lo; m.maxLimit = hi; m.restoreFrame = nil }
    }
    func windowWillResize(_ w: NSWindow, to s: NSSize) -> NSSize {      // harte Grenzen, auch wenn das System minSize/maxSize nicht greift
        guard let m = w as? MLWindow else { return s }
        return NSSize(width: min(max(s.width, m.minLimit.width), m.maxLimit.width), height: min(max(s.height, m.minLimit.height), m.maxLimit.height))
    }
    /// Grüner Knopf: zwischen Benutzergröße und Maximalgröße umschalten (Rückkehr zum vorherigen Zustand).
    func windowShouldZoom(_ w: NSWindow, toFrame f: NSRect) -> Bool {
        guard let m = w as? MLWindow else { return true }
        if let r = m.restoreFrame, abs(w.frame.width - m.maxLimit.width) < 2 || abs(w.frame.height - m.maxLimit.height) < 2 {
            m.restoreFrame = nil; w.setFrame(r, display: true, animate: true); return false
        }
        m.restoreFrame = w.frame
        let scr = (w.screen ?? NSScreen.main)!.visibleFrame
        var r = w.frame
        r.size = NSSize(width: min(m.maxLimit.width, scr.width), height: min(m.maxLimit.height, scr.height))
        r.origin.y = max(scr.minY, w.frame.maxY - r.height); r.origin.x = min(r.origin.x, scr.maxX - r.width)
        w.setFrame(r, display: true, animate: true); return false
    }
    func vsFor(_ w: NSWindow) -> ViewState? { main?.0 === w ? main?.1 : others.first { $0.0 === w }?.1 }
    func windowDidBecomeKey(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        // (nur wenn noch keine Zone aktiv ist) Tastaturfokus gehört der Liste (Pfeile, Leertaste), nicht automatisch dem Suchfeld
        DispatchQueue.main.async { [weak self] in if let vs = self?.vsFor(w), vs.editing == nil, vs.zone == nil, !(w.firstResponder is NSText) { vs.focusPaperTick += 1 } }
    }
    func openMain() {
        if let (w, _) = main { w.makeKeyAndOrderFront(nil); return }
        let vs = ViewState(store: store)
        if UserDefaults.standard.object(forKey: "showCal") != nil { vs.showCal = UserDefaults.standard.bool(forKey: "showCal") }
        var sz = NSSize(width: 741, height: 509)
        if let a = CommandLine.arguments.first(where: { $0.hasPrefix("-size=") }) { let p = a.dropFirst(6).split(separator: "x").compactMap { Double($0) }; if p.count == 2 { sz = NSSize(width: p[0], height: p[1]) } }
        var restored: NSRect?
        if persist, !CommandLine.arguments.contains(where: { $0.hasPrefix("-size=") }), let st = loadState()?.main {
            restore(st, into: vs); normalWidth = st.normalWidth ?? 741
            let r = NSRectFromString(st.frame); if r.width > 100 { sz = r.size; restored = r }
        }
        let w = makeWindow(vs, size: sz, autosave: nil)
        if let r = restored { place(w, r) }
        main = (w, vs)
        vs.$showCal.dropFirst().sink { UserDefaults.standard.set($0, forKey: "showCal") }.store(in: &bag)
        vs.$compact.dropFirst().sink { [weak self, weak w] c in
            guard let w else { return }
            var f = w.frame
            if c { self?.normalWidth = f.width; f.size.width = 320 } else { f.size.width = self?.normalWidth ?? 741 }
            self?.applyLimits(w, compact: c)
            DispatchQueue.main.async { w.setFrame(f, display: true, animate: true) }
        }.store(in: &bag)
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { vs.focusPaperTick += 1 }
    }
    var bag = Set<AnyCancellable>()

    // MARK: Menü
    /// ViewState des aktiven Fensters – Menübefehle folgen dem Fenster, nicht immer dem Hauptfenster.
    var key: ViewState? {
        if let kw = NSApp.keyWindow {
            if main?.0 === kw { return main?.1 }
            if let o = others.first(where: { $0.0 === kw }) { return o.1 }
        }
        return main?.1
    }
    func validateMenuItem(_ i: NSMenuItem) -> Bool {
        if i.action == #selector(toggleSystem) { i.state = store.ek.enabled ? .on : .off }
        let vs = key, hasTask = vs?.selected.flatMap { store.task($0) } != nil
        switch i.action {
        case #selector(showInfo), #selector(deleteTask), #selector(toggleDone): return hasTask && vs?.editing == nil
        case #selector(renameList): return vs?.currentListID != nil && vs?.compact == false
        case #selector(deleteList): return vs?.currentListID != nil && store.lists.count > 1
        case #selector(find): return vs?.single == false
        case #selector(prevList), #selector(nextList): return vs.map { $0.neighbor(i.action == #selector(nextList) ? 1 : -1) != nil } ?? false
        case #selector(undo): return NSApp.keyWindow?.firstResponder is NSText || store.canUndo
        case #selector(redo): return NSApp.keyWindow?.firstResponder is NSText || store.canRedo
        default: return true
        }
    }
    func buildMenu() {
        let m = NSMenu()
        func add(_ menu: NSMenu, _ t: String, _ sel: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: k); i.keyEquivalentModifierMask = mods; i.target = target ?? self; menu.addItem(i)
        }
        func sub(_ t: String) -> NSMenu { let i = NSMenuItem(); let s = NSMenu(title: t); i.submenu = s; m.addItem(i); return s }
        let app = sub("App")
        add(app, L("About RetroReminder", "Über RetroReminder"), #selector(showAbout))
        app.addItem(.separator())
        add(app, L("Settings …", "Einstellungen …"), #selector(showPreferences), ",")
        app.addItem(.separator())
        add(app, L("Hide RetroReminder", "RetroReminder ausblenden"), #selector(NSApplication.hide(_:)), "h", target: NSApp)
        app.addItem(.separator())
        add(app, L("Quit RetroReminder", "RetroReminder beenden"), #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = sub(L("File", "Ablage"))
        add(file, L("New Reminder", "Neue Erinnerung"), #selector(newTask), "n")
        add(file, L("New List", "Neue Liste"), #selector(newList), "l")
        add(file, L("Rename List", "Liste umbenennen"), #selector(renameList), "r")
        add(file, L("Delete List", "Liste löschen"), #selector(deleteList), "\u{8}", [.command, .shift])
        add(file, L("Open List in New Window", "Liste in neuem Fenster öffnen"), #selector(newListWindow), "\r")
        file.addItem(.separator())
        add(file, L("Export as .ics…", "Als .ics exportieren …"), #selector(exportICS), "e", [.command, .shift])
        add(file, L("Use System Reminders", "Systemerinnerungen verwenden"), #selector(toggleSystem))
        add(file, L("Close Window", "Fenster schließen"), #selector(closeWin), "w")
        let edit = sub(L("Edit", "Bearbeiten"))
        add(edit, L("Undo", "Widerrufen"), #selector(undo), "z")
        add(edit, L("Redo", "Wiederholen"), #selector(redo), "Z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, L("Cut", "Ausschneiden"), #selector(NSText.cut(_:)), "x", target: nil)
        add(edit, L("Copy", "Kopieren"), #selector(NSText.copy(_:)), "c", target: nil)
        add(edit, L("Paste", "Einsetzen"), #selector(NSText.paste(_:)), "v", target: nil)
        add(edit, L("Select All", "Alles auswählen"), #selector(NSText.selectAll(_:)), "a", target: nil)
        edit.addItem(.separator())
        add(edit, L("Show Info", "Informationen"), #selector(showInfo), "i")
        add(edit, L("Mark as Completed", "Als erledigt markieren"), #selector(toggleDone), "e")
        let mv = NSMenuItem(title: L("Move to List", "In Liste verschieben"), action: nil, keyEquivalent: ""); let mvm = NSMenu(); mvm.delegate = self; mv.submenu = mvm; edit.addItem(mv)
        add(edit, L("Delete Reminder", "Erinnerung löschen"), #selector(deleteTask), "\u{8}")
        add(edit, L("Find", "Suchen"), #selector(find), "f")
        let view = sub(L("View", "Darstellung"))
        add(view, L("Go to Today", "Heute anzeigen"), #selector(today), "t")
        add(view, L("Previous List", "Vorherige Liste"), #selector(prevList), "[")
        add(view, L("Next List", "Nächste Liste"), #selector(nextList), "]")
        add(view, L("Show/Hide Calendar", "Kalender ein-/ausblenden"), #selector(toggleCal), "k", [.command, .option])
        add(view, L("Show/Hide Lists", "Listen ein-/ausblenden"), #selector(toggleSidebar), "s", [.command, .option])
        let win = sub(L("Window", "Fenster"))
        add(win, L("Minimize", "Im Dock ablegen"), #selector(miniWin), "m")
        add(win, L("Zoom", "Zoomen"), #selector(zoomWin), "")
        add(win, "RetroReminder", #selector(showMain), "0")
        NSApp.mainMenu = m
        NSApp.windowsMenu = win
    }
    // MARK: Tastatur-Selbsttest (`-keytest`): synthetische Tastenereignisse durchs echte Fenster
    func key(_ w: NSWindow, _ code: UInt16, _ ch: String, _ mods: NSEvent.ModifierFlags = []) {
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) { NSApp.sendEvent(e) }
        }
    }
    func runKeyTest() {
        guard let (w, vs) = main else { return }
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { fails += 1 } }
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!), up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let open = { self.store.open(in: vs.effectiveSel).map(\.id) }
        let steps: [(String, () -> Void, () -> Void)] = [
            ("↓ wählt erste Aufgabe", { self.key(w, 125, down) }, { check(vs.selected == open().first, "↓ → erste Aufgabe ausgewählt") }),
            ("↓ zweite", { self.key(w, 125, down) }, { check(vs.selected == open().dropFirst().first, "↓ → zweite Aufgabe") }),
            ("↑ erste", { self.key(w, 126, up) }, { check(vs.selected == open().first, "↑ → zurück zur ersten") }),
            ("Return → Bearbeiten", { self.key(w, 36, "\r") }, { check(vs.editing == vs.selected && vs.editing != nil, "Return startet Bearbeitung") }),
            ("Leertaste im Textfeld", { self.key(w, 49, " ") }, { check(self.store.task(vs.selected ?? UUID())?.done == false, "Leertaste im Textfeld erledigt NICHT") }),
            ("Esc bricht Bearbeitung ab", { self.key(w, 53, "\u{1b}") }, { check(vs.editing == nil, "Esc beendet Bearbeitung") }),
            ("Leertaste → erledigt", { self.key(w, 49, " ") }, { check(self.store.task(vs.selected ?? UUID())?.done == true || vs.selected != nil && self.store.tasks.contains { $0.done && $0.title.hasPrefix("Review") }, "Leertaste erledigt ausgewählte Aufgabe") }),
            ("⌘Z macht rückgängig", { self.undo() }, { check(self.store.tasks.contains { !$0.done && $0.title.hasPrefix("Review") }, "⌘Z öffnet die Aufgabe wieder") }),
            ("⌘F Fokus Suche", { let t = vs.focusSearchTick; self.find(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { check(vs.focusSearchTick == t + 1, "⌘F fordert Suchfokus an") } }, {}),
            ("Kompakt → → nächste Seite", { vs.compact = true; vs.go(.list(self.store.sortedLists[0].id)) }, {}),
            ("→", { self.key(w, 124, right) }, { check(vs.currentPage == .list(self.store.sortedLists[1].id), "→ im Kompaktmodus: nächste Liste") }),
            ("←", { self.key(w, 123, left) }, { check(vs.currentPage == .list(self.store.sortedLists[0].id), "← im Kompaktmodus: vorherige Liste") }),
            ("⌘] nächste Liste", { self.nextList() }, { check(vs.currentPage == .list(self.store.sortedLists[1].id), "⌘] nächste Liste") }),
            ("⌘N neue Erinnerung", { self.newTask() }, { check(vs.editing != nil, "⌘N legt Aufgabe an und bearbeitet sie") }),
            ("Esc", { self.key(w, 53, "\u{1b}") }, { check(vs.editing == nil, "Esc beendet neue Aufgabe") }),
            ("normal", { vs.compact = false; vs.showCal = true; vs.mode = .lists; vs.sel = [self.store.sortedLists[0].id] }, {}),
            ("Zone Papier", { vs.requestZone(.paper) }, { check(vs.zone == .paper, "Start: Zone Papier") }),
            ("Tab → Suche", { self.key(w, 48, "\t") }, { check(vs.zone == .search, "Tab: Papier → Suche (Umlauf) (Zone \(String(describing: vs.zone)))") }),
            ("Tab → Listen", { self.key(w, 48, "\t") }, { check(vs.zone == .lists, "Tab: Suche → Listen (Zone \(String(describing: vs.zone)), FR \(String(describing: w.firstResponder).prefix(50)))") }),
            ("↓ in Listen", { self.key(w, 125, down) }, { check(vs.currentPage != nil && vs.currentPage != .list(self.store.sortedLists[0].id) || vs.currentPage == .completed, "↓ in der Listenzone wechselt die Liste") }),
            ("Tab → Kalender", { self.key(w, 48, "\t") }, { check(vs.zone == .calendar, "Tab: Listen → Kalender") }),
            ("→ Tag", { vs.calCursor = shownToday; self.key(w, 124, right) }, { check(Calendar.current.isDate(vs.calCursor, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: shownToday)!), "→ im Kalender: nächster Tag") }),
            ("↓ Woche", { self.key(w, 125, down) }, { check(Calendar.current.isDate(vs.calCursor, inSameDayAs: Calendar.current.date(byAdding: .day, value: 8, to: shownToday)!), "↓ im Kalender: +7 Tage") }),
            ("Bild↓ Monat", { let m = vs.month; self.key(w, 121, String(UnicodeScalar(NSPageDownFunctionKey)!)); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { check(!Calendar.current.isDate(vs.month, equalTo: m, toGranularity: .month), "Bild↓ im Kalender: nächster Monat") } }, {}),
            ("Return Tag wählen", { self.key(w, 36, "\r") }, { if case .day = vs.mode { check(true, "Return im Kalender wählt den Tag") } else { check(false, "Return im Kalender wählt den Tag") } }),
            ("⇧Tab zurück", { self.key(w, 48, "\t", .shift) }, { check(vs.zone == .lists, "⇧Tab: Kalender → Listen") }),
            ("Tab ×4 → Plus", { for i in 0..<5 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(i)) { self.key(w, 48, "\t") } } }, { check(vs.zone == .plus || vs.zone == .btnNewList || vs.zone == .btnCalendar || vs.zone == .btnSidebar, "Tab erreicht die unteren Knöpfe/Plus (Zone: \(String(describing: vs.zone)))") }),
        ]
        func run(_ i: Int) {
            if i == steps.count { print(fails == 0 ? "ALLE TASTATUR-TESTS OK" : "\(fails) FEHLER"); NSApp.terminate(nil); return }
            if !w.isKeyWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil) }     // Fokus-Wechsel gelten nur im Schlüsselfenster
            steps[i].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { steps[i].2(); run(i + 1) }
        }
        vs.requestZone(.paper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { run(0) }     // Fokus-Anforderung braucht ein Runloop-Intervall nach der Aktivierung
    }
    // MARK: Bedienungshilfen-Prüfung (`-axdump`): listet bedienbare Elemente des Fensters mit Rolle/Name und meldet unbenannte
    func axDump() {
        guard let (w, _) = main, let root = w.contentView else { return }
        var unnamed = 0, total = 0
        func walk(_ e: Any, _ depth: Int) {
            guard let el = e as? NSAccessibilityElementProtocol else { return }
            let o = el as AnyObject
            let role = (o.accessibilityRole?() ?? nil)?.rawValue ?? "?", label = (o.accessibilityLabel?() ?? nil) ?? "", title = (o.accessibilityTitle?() ?? nil) ?? ""
            let value = String(describing: (o.accessibilityValue?() ?? nil) as Any), help = (o.accessibilityHelp?() ?? nil) ?? ""
            let interactive = ["AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXPopUpButton", "AXTextArea", "AXMenuButton", "AXRow", "AXCell"].contains(role)
            if interactive || !label.isEmpty { total += interactive ? 1 : 0
                let name = label.isEmpty ? title : label
                if interactive && name.isEmpty && value == "nil" { unnamed += 1 }
                print(String(repeating: "  ", count: min(depth, 6)) + "\(role) “\(name)” value=\(value.prefix(60))")
            }
            for c in (o.accessibilityChildren?() ?? nil) ?? [] { walk(c, depth + 1) }
        }
        walk(root, 0)
        // Reihenfolge: gesamte Seitenleiste vor dem Papier; Standardaktion einer Aufgabe wirkt
        func flat(_ e: Any, _ out: inout [AnyObject]) { guard let o = e as AnyObject? else { return }; out.append(o); for c in (o.accessibilityChildren?() ?? nil) ?? [] { flat(c, &out) } }
        var all: [AnyObject] = []; flat(root, &all)
        let names = all.compactMap { ($0.accessibilityLabel?() ?? nil) }
        let iSide = names.firstIndex(of: L("Sidebar", "Seitenleiste")) ?? -1, iPaper = names.firstIndex(of: L("Reminders", "Erinnerungen")) ?? -1
        print("AX Reihenfolge: Seitenleiste@\(iSide) vor Papier@\(iPaper):", iSide >= 0 && iSide < iPaper ? "OK" : "FALSCH")
        if let row = all.first(where: { (($0.accessibilityLabel?() ?? nil) ?? "").hasPrefix("Review") }) {
            let before = store.tasks.first { $0.title.hasPrefix("Review") }?.done
            let ok = row.accessibilityPerformPress?() ?? false
            for a in (row.accessibilityCustomActions?() ?? []) { print("  Aktion:", a.name) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {      // (GCD-Hauptqueue läuft nicht verschachtelt – deshalb nach Rückkehr prüfen)
                let after = self.store.tasks.first { $0.title.hasPrefix("Review") }?.done
                print("AX Standardaktion (Drücken): press=\(ok), Review erledigt \(String(describing: before)) → \(String(describing: after))", before == false && after == true ? "OK" : "FALSCH")
                NSApp.terminate(nil)
            }
            print("AX: \(total) bedienbare Elemente, ohne Namen/Wert: \(unnamed)")
            return
        }
        print("AX: \(total) bedienbare Elemente, ohne Namen/Wert: \(unnamed)")
    }
    // MARK: Über / Einstellungen
    var prefsWindow: NSWindow?
    @objc func showAbout() {
        let text = L("Design inspired by OS X 10.8. RetroReminder is an independent open-source project (MIT License) and is not affiliated with, authorized or endorsed by Apple Inc. Apple, Mac, macOS, OS X and Mountain Lion are trademarks of Apple Inc.",
                     "Design inspiriert von OS X 10.8. RetroReminder ist ein unabhängiges Open-Source-Projekt (MIT-Lizenz) und steht in keiner Verbindung zu Apple Inc., wird weder von Apple autorisiert noch unterstützt. Apple, Mac, macOS, OS X und Mountain Lion sind Marken von Apple Inc.")
        NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]), .applicationName: "RetroReminder"])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showPreferences() {
        if prefsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            w.title = L("Settings", "Einstellungen"); w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false; w.center()
            prefsWindow = w
        }
        prefsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func closeWin() { NSApp.keyWindow?.close() }
    @objc func zoomWin() { NSApp.keyWindow?.zoom(nil) }
    @objc func miniWin() { NSApp.keyWindow?.miniaturize(nil) }
    @objc func newTask() { key?.newTask() }
    @objc func newList() { key?.newList() }
    @objc func newListWindow() {
        guard let vs = key else { return }
        let nv = ViewState(store: store, single: true)
        nv.mode = vs.mode; nv.sel = vs.effectiveSel
        openListWindow(nv, frame: nil)
    }
    func openListWindow(_ nv: ViewState, frame: NSRect?) {
        let w = makeWindow(nv, size: frame?.size ?? NSSize(width: 330, height: 420), autosave: nil)
        if let f = frame { place(w, f) } else { w.setFrameTopLeftPoint(NSPoint(x: (main?.0.frame.maxX ?? 400) + 12, y: (main?.0.frame.maxY ?? 600))) }
        others.append((w, nv)); w.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            guard let self, !self.quitting else { return }
            self.others.removeAll { $0.0 === w }; self.scheduleSave()
        }
        scheduleSave()
    }
    // MARK: Wiederherstellung
    func place(_ w: NSWindow, _ r: NSRect) {
        let ok = NSScreen.screens.contains { $0.visibleFrame.intersects(r.insetBy(dx: 40, dy: 40)) }     // Bildschirm kann fehlen (Monitor abgesteckt)
        if ok, let m = w as? MLWindow {
            let s = NSSize(width: min(max(r.width, m.minLimit.width), m.maxLimit.width), height: min(max(r.height, m.minLimit.height), m.maxLimit.height))
            w.setFrame(NSRect(x: r.minX, y: r.maxY - s.height, width: s.width, height: s.height), display: false)
        } else { w.center() }
    }
    func loadState() -> AppState? { UserDefaults.standard.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(AppState.self, from: $0) } }
    func capture(_ w: NSWindow, _ vs: ViewState) -> WinState {
        let m: String
        switch vs.mode { case .lists: m = "lists"; case .completed: m = "completed"; case .day: m = "lists" }   // Tag wird nicht wiederhergestellt
        return WinState(frame: NSStringFromRect(w.frame), compact: vs.compact, normalWidth: vs.single ? nil : Double(normalWidth), mode: m, sel: Array(vs.sel), showDone: vs.showDone)
    }
    func restore(_ st: WinState, into vs: ViewState) {
        vs.compact = st.compact && !vs.single || vs.single
        vs.mode = st.mode == "completed" ? .completed : .lists
        if !st.sel.isEmpty { vs.sel = Set(st.sel) }
        vs.showDone = st.showDone
    }
    func scheduleSave() {
        guard persist else { return }
        saveItem?.cancel()
        let it = DispatchWorkItem { [weak self] in self?.saveState() }
        saveItem = it; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: it)
    }
    func saveState() {
        guard persist else { return }
        let st = AppState(main: main.map { capture($0.0, $0.1) }, lists: others.map { capture($0.0, $0.1) })
        if let d = try? JSONEncoder().encode(st) { UserDefaults.standard.set(d, forKey: stateKey) }
    }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply { quitting = true; saveState(); return .terminateNow }
    @objc func toggleSystem() {
        let on = !store.ek.enabled
        store.ek.setEnabled(on)
        if on { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { let a = NSAlert(); a.messageText = self.store.ek.status; a.runModal() } }
    }
    @objc func exportICS() { key?.exportICS() }
    // Im Texteingabefeld gilt der Textverlauf, sonst der Datenbestand (sonst würde ⌘Z beim Tippen Aufgaben löschen)
    @objc func undo() { if let t = NSApp.keyWindow?.firstResponder as? NSText { t.undoManager?.undo() } else { store.undo() } }
    @objc func redo() { if let t = NSApp.keyWindow?.firstResponder as? NSText { t.undoManager?.redo() } else { store.redo() } }
    @objc func showInfo() { if let vs = key, let id = vs.selected { NotificationCenter.default.post(name: .init("MLInfo"), object: id, userInfo: ["vs": vs]) } }
    @objc func toggleDone() { key?.toggleSelected() }
    @objc func renameList() { if let vs = key, let id = vs.currentListID { vs.renaming = id } }
    @objc func deleteList() { if let vs = key, let id = vs.currentListID { vs.deleteList(id) } }
    @objc func prevList() { key?.step(-1) }
    @objc func nextList() { key?.step(1) }
    @objc func moveTaskTo(_ s: NSMenuItem) { if let vs = key, let t = vs.selected, let l = s.representedObject as? UUID { store.move(t, to: l) } }
    // Untermenü „In Liste verschieben“ wird beim Öffnen mit den Listen gefüllt
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let cur = key?.selected.flatMap { store.task($0)?.listID }
        for l in store.writableLists {
            let i = NSMenuItem(title: l.name, action: #selector(moveTaskTo(_:)), keyEquivalent: ""); i.target = self; i.representedObject = l.id; i.isEnabled = cur != nil && l.id != cur; m.addItem(i)
        }
    }
    @objc func deleteTask() { key?.deleteSelectedTask() }
    @objc func find() {
        guard let vs = key, !vs.single else { return }
        if vs.compact { vs.compact = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { vs.focusSearchTick += 1 } } else { vs.focusSearchTick += 1 }
    }
    @objc func today() { key?.mode = .day(Date()); key?.month = Date() }
    @objc func toggleCal() { key?.showCal.toggle() }
    @objc func toggleSidebar() { key?.compact.toggle() }
    @objc func showMain() { openMain() }
}

import Combine
@main
struct RetroReminderApp {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("-selftest") { exit(SelfTest.run()) }
        let d = AppDelegate()
        app.delegate = d
        app.run()
    }
}
