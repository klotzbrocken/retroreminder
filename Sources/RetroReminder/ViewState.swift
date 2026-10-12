import SwiftUI
import AppKit

/// VoiceOver-Ansage (z. B. nach Erledigen), ohne Fokuswechsel
func announce(_ s: String) {
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: s, .priority: NSAccessibilityPriorityLevel.high.rawValue])
}

enum Mode: Equatable { case lists, completed, day(Date) }
/// Tab-Zonen eines Fensters in Reihenfolge: Suche → Listen → Kalender → untere Knöpfe → Plus → Papier
enum Zone: Hashable { case search, lists, calendar, btnSidebar, btnCalendar, btnNewList, plus, paper }

struct Sec: Identifiable { let id: String; let title: String?; let tasks: [Task] }
struct Content { var header: String; var secs: [Sec]; var doneCount: Int?; var showDoneRow: Bool }

/// Zustand eines Fensters (Hauptfenster oder separates Listenfenster); die Daten liegen im gemeinsamen Store.
final class ViewState: ObservableObject {
    let store: Store
    @Published var mode: Mode = .lists
    @Published var sel: Set<UUID> = []
    @Published var query = ""
    @Published var showCal = true
    @Published var compact = false { didSet { if compact != oldValue { DispatchQueue.main.async { self.focusPaperTick += 1 } } } }
    @Published var month = shownToday
    @Published var selected: UUID?
    @Published var editing: UUID?
    @Published var renaming: UUID?
    @Published var showDone = false
    @Published var active = true
    let single: Bool                     // separates Listenfenster: nie mit Seitenleiste
    weak var window: NSWindow?
    var newlyCreated: UUID?

    init(store: Store, single: Bool = false) {
        self.store = store; self.single = single
        sel = [store.sortedLists.first!.id]
        compact = single
    }

    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var effectiveSel: Set<UUID> {
        let valid = sel.filter { store.list($0) != nil }
        return valid.isEmpty ? [store.sortedLists.first!.id] : Set(valid)
    }
    /// Seiten für den Kompaktmodus (Punkte): Erledigt + Listen
    var pages: [Page] { [.completed] + store.sortedLists.map { .list($0.id) } }
    enum Page: Equatable { case completed, list(UUID) }
    var currentPage: Page? {
        switch mode { case .completed: return .completed
        case .day: return nil
        case .lists: return effectiveSel.count == 1 ? .list(effectiveSel.first!) : nil }
    }
    @Published var pageEdge: Edge = .trailing
    var pageKey: String { "\(mode)-\(sel.map(\.uuidString).sorted())-\(searching)" }
    /// Seitenwechsel (Punkte / Wischen): schiebt die Seite von der Seite herein; mit „Bewegung reduzieren“ ohne Animation.
    func go(_ p: Page) {
        let ps = pages
        if let c = currentPage, let a = ps.firstIndex(of: c), let b = ps.firstIndex(of: p) { pageEdge = b > a ? .trailing : .leading }
        let change = { self.selected = nil; self.editing = nil; self.query = ""; self.showDone = false
            switch p { case .completed: self.mode = .completed
            case .list(let id): self.mode = .lists; self.sel = [id] } }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.22)) { change() } }
    }
    @Published var zone: Zone?                 // aktuell fokussierte Zone (von den Zonen-Views gemeldet)
    @Published var zoneRequest: Zone?
    @Published var zoneTick = 0
    @Published var calCursor = shownToday      // Tastaturcursor im Kalender
    @Published var focusSearchTick = 0
    @Published var focusPaperTick = 0     // Fokus per Tastatur (⌘F, Return im Suchfeld, nach Bearbeiten)
    @Published var dragX: CGFloat = 0
    var pageWidth: CGFloat = 320
    /// Nachbarseite in Richtung d (+1 = nächste); aus Tages-/Mehrfachansicht zählt die erste Liste als Nachbar.
    func neighbor(_ d: Int) -> Page? {
        let ps = pages
        guard let c = currentPage, let i = ps.firstIndex(of: c) else { return ps.dropFirst().first }
        return ps.indices.contains(i + d) ? ps[i + d] : nil
    }
    private func goInstant(_ p: Page) {
        selected = nil; editing = nil; query = ""; showDone = false
        switch p { case .completed: mode = .completed
        case .list(let id): mode = .lists; sel = [id] }
    }
    /// Seite folgt dem Finger; an den Enden mit Gummiband-Widerstand.
    func swipeChanged(_ acc: CGFloat) {
        dragX = neighbor(acc < 0 ? 1 : -1) == nil ? max(-40, min(40, acc * 0.3)) : acc
    }
    /// Loslassen: ab 60 pt (und vorhandener Zielseite) Seitenwechsel, sonst Abbruch mit Rückfedern. Der Zielzustand ist immer eine ganze Seite.
    func swipeEnded(_ acc: CGFloat) {
        let d = acc < 0 ? 1 : -1
        guard abs(acc) > 60, let target = neighbor(d) else {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { dragX = 0 } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 } }
            return
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { goInstant(target); dragX = 0 }; return }
        let out = acc < 0 ? -pageWidth : pageWidth
        withAnimation(.easeOut(duration: 0.12)) { dragX = out }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { goInstant(target); dragX = -out }      // neue Seite steht draußen auf der Gegenseite bereit
            withAnimation(.easeOut(duration: 0.16)) { dragX = 0 }
        }
    }
    func step(_ d: Int) {
        let ps = pages
        guard let c = currentPage, let i = ps.firstIndex(of: c) else { if let f = ps.dropFirst().first { go(f) }; return }   // aus Tages-/Mehrfachansicht: erste Liste
        let n = i + d; if ps.indices.contains(n) { go(ps[n]) }
    }

    var content: Content {
        let all = store.sortedLists
        if searching {
            let r = store.search(query)
            return Content(header: L("Search", "Suche"), secs: group(r, byList: true), doneCount: nil, showDoneRow: false)
        }
        switch mode {
        case .completed:
            let c = store.completed()
            let g = Dictionary(grouping: c) { Calendar.current.startOfDay(for: $0.completedAt ?? .distantPast) }
            let secs = g.keys.sorted(by: >).map { Sec(id: "d\($0.timeIntervalSince1970)", title: Fmt.header($0), tasks: g[$0]!) }
            return Content(header: L("Completed", "Erledigt"), secs: secs, doneCount: nil, showDoneRow: false)
        case .day(let d):
            return Content(header: Fmt.dayLabel(d), secs: [Sec(id: "day", title: nil, tasks: store.tasks(on: d))], doneCount: nil, showDoneRow: false)
        case .lists:
            let ids = effectiveSel
            let header = ids.count == 1 ? (store.list(ids.first!)?.name ?? "") : (isDE ? "\(ids.count) Listen" : "\(ids.count) Lists")
            let open = store.open(in: ids)
            let secs: [Sec]
            if ids.count > 1 { secs = group(open, byList: true, order: all.map(\.id)) }
            else {
                var s = [Sec(id: "open", title: nil, tasks: open)]
                if showDone { s.append(Sec(id: "done", title: nil, tasks: store.completed(in: ids))) }
                secs = s
            }
            return Content(header: header, secs: secs, doneCount: ids.count == 1 ? store.completed(in: ids).count : nil, showDoneRow: ids.count == 1)
        }
    }
    private func group(_ t: [Task], byList: Bool, order: [UUID]? = nil) -> [Sec] {
        let g = Dictionary(grouping: t, by: \.listID)
        let ids = order ?? store.sortedLists.map(\.id)
        return ids.compactMap { id in g[id].map { Sec(id: id.uuidString, title: store.list(id)?.name, tasks: $0) } }
    }
    var flat: [Task] { content.secs.flatMap(\.tasks) }

    // MARK: Aktionen
    func newTask() {
        let list = (mode == .lists ? effectiveSel.first.flatMap { id in store.list(id)?.readOnly == true ? nil : id } : nil) ?? store.writableLists.first!.id
        query = ""
        var due: Date?
        if case .day(let d) = mode { due = d }
        if mode == .completed { mode = .lists; sel = [list] }
        let id = store.addTask(in: list, due: due)
        newlyCreated = id; selected = id; editing = id
        announce(L("New reminder", "Neue Erinnerung"))
    }
    func newList() {
        let id = store.addList(L("New List", "Neue Liste"))
        mode = .lists; sel = [id]; query = ""; renaming = id
    }
    func deleteSelectedTask() {
        guard let id = selected, let t = store.task(id) else { return }
        _ = t; moveSelection(1); store.delete(id)
    }
    func moveSelection(_ d: Int) {
        let f = flat; guard !f.isEmpty else { return }
        if let s = selected, let i = f.firstIndex(where: { $0.id == s }) { selected = f[max(0, min(f.count - 1, i + d))].id }
        else { selected = d > 0 ? f.first?.id : f.last?.id }
    }
    /// Liste der Seitenleiste, auf die sich Tastaturbefehle beziehen (nur bei genau einer gewählten Liste)
    var currentListID: UUID? { if case .list(let id)? = currentPage { return id }; return nil }
    /// Esc beim Bearbeiten: verwirft die Eingabe; eine eben angelegte leere Aufgabe verschwindet wieder (inkl. Undo-Eintrag).
    func cancelEditing() {
        guard let id = editing else { return }
        editing = nil
        if newlyCreated == id, store.task(id)?.title.isEmpty == true { store.undo() }
        newlyCreated = nil
    }
    func requestZone(_ z: Zone) { zoneRequest = z; zone = z; zoneTick += 1 }    // zone sofort setzen: schnelle Tab-Wiederholung rechnet vom Ziel, nicht vom veralteten Fokus
    func visibleZones() -> [Zone] {
        if single { return [.plus, .paper] }
        if compact { return [.btnSidebar, .plus, .paper] }
        return [.search, .lists] + (showCal ? [.calendar] : []) + [.btnSidebar, .btnCalendar, .btnNewList, .plus, .paper]
    }
    /// Tab / ⇧Tab: nächste sichtbare Zone (mit Umlauf). Beim Bearbeiten beendet Tab nur die Eingabe (Fokus zurück aufs Papier → Übernahme).
    func tab(back: Bool) {
        if editing != nil { requestZone(.paper); return }
        let zs = visibleZones(), cur = zone.flatMap { zs.firstIndex(of: $0) } ?? zs.count - 1
        requestZone(zs[(cur + (back ? zs.count - 1 : 1)) % zs.count])
    }
    /// Kalendercursor bewegen; zeigt den passenden Monat.
    func calMove(days: Int = 0, months: Int = 0) {
        let c = Calendar.current
        var d = c.date(byAdding: .day, value: days, to: calCursor) ?? calCursor
        if months != 0 { d = c.date(byAdding: .month, value: months, to: d) ?? d }
        calCursor = d
        if !c.isDate(d, equalTo: month, toGranularity: .month) { month = d }
    }
    /// Tag wählen (wie Klick): erneutes Wählen desselben Tags kehrt zur Liste zurück.
    func selectDay(_ d: Date) {
        if case .day(let s) = mode, Calendar.current.isDate(s, inSameDayAs: d) { mode = .lists } else { mode = .day(d); query = "" }
        selected = nil
    }
    func toggleSelected() { if let id = selected, let t = store.task(id) { store.setDone(id, !t.done); announce((t.done ? L("Reopened: ", "Wieder geöffnet: ") : L("Completed: ", "Erledigt: ")) + t.title) } }
    func deleteList(_ id: UUID) {
        guard store.lists.count > 1, let l = store.list(id) else { return }
        let n = store.tasks.filter { $0.listID == id }.count
        if n > 0 {
            let a = NSAlert()
            a.messageText = L("Delete the list “\(l.name)”?", "Liste „\(l.name)“ löschen?")
            a.informativeText = isDE ? "Die Liste enthält \(n == 1 ? "1 Erinnerung" : "\(n) Erinnerungen"), die ebenfalls gelöscht \(n == 1 ? "wird" : "werden")." : "This list contains \(n == 1 ? "1 reminder" : "\(n) reminders"), which will be deleted as well."
            a.addButton(withTitle: L("Delete", "Löschen")); a.addButton(withTitle: L("Cancel", "Abbrechen"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        store.deleteList(id)
        sel.remove(id)
        if sel.isEmpty { sel = [store.sortedLists.first!.id] }
    }
    func exportICS() {
        let tasks: [Task]
        switch mode { case .lists: tasks = store.tasks.filter { effectiveSel.contains($0.listID) }
        case .completed: tasks = store.completed(); case .day(let d): tasks = store.tasks(on: d) }
        let p = NSSavePanel(); p.nameFieldStringValue = L("Reminders.ics", "Erinnerungen.ics"); p.allowedContentTypes = [.init(filenameExtension: "ics")!]
        if p.runModal() == .OK, let u = p.url { try? store.icsExport(tasks).write(to: u, atomically: true, encoding: .utf8) }
    }
}
