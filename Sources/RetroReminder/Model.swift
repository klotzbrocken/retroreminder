import Foundation
import SwiftUI
import UserNotifications
import CoreLocation

// MARK: - Lokalisierung (DE/EN, Systemsprache)
let isDE = Locale.preferredLanguages.first?.hasPrefix("de") ?? false
/// Angezeigtes "heute" (nur für reproduzierbare Referenzaufnahmen: -date=yyyy-MM-dd)
let shownToday: Date = {
    guard let a = CommandLine.arguments.first(where: { $0.hasPrefix("-date=") }) else { return Date() }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
    return f.date(from: String(a.dropFirst(6))) ?? Date()
}()
func L(_ en: String, _ de: String) -> String { isDE ? de : en }

// MARK: - Modell
enum Repeat: String, Codable, CaseIterable {
    case none, daily, weekly, biweekly, monthly, yearly
    var label: String {
        switch self {
        case .none: return L("Never", "Nie")
        case .daily: return L("Every Day", "Täglich")
        case .weekly: return L("Every Week", "Wöchentlich")
        case .biweekly: return L("Every 2 Weeks", "Alle 2 Wochen")
        case .monthly: return L("Every Month", "Monatlich")
        case .yearly: return L("Every Year", "Jährlich")
        }
    }
    /// k-tes Vorkommen ab dem Ankerdatum (nicht iterativ: Monatsende 31. bleibt 31., wo der Monat es hergibt – Calendar klemmt sonst auf den letzten gültigen Tag).
    func occurrence(_ k: Int, from d: Date, cal: Calendar = .current) -> Date? {
        switch self {
        case .none: return nil
        case .daily: return cal.date(byAdding: .day, value: k, to: d)
        case .weekly: return cal.date(byAdding: .day, value: 7 * k, to: d)
        case .biweekly: return cal.date(byAdding: .day, value: 14 * k, to: d)
        case .monthly: return cal.date(byAdding: .month, value: k, to: d)
        case .yearly: return cal.date(byAdding: .year, value: k, to: d)
        }
    }
}

enum Priority: Int, Codable, CaseIterable {
    case none, low, medium, high
    var label: String {
        switch self {
        case .none: return L("None", "Keine")
        case .low: return L("Low", "Niedrig")
        case .medium: return L("Medium", "Mittel")
        case .high: return L("High", "Hoch")
        }
    }
    var marks: String { String(repeating: "!", count: rawValue) }
}

struct RList: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var order: Double
    // Systemliste (EventKit): nicht persistiert, wird bei jedem Start/Änderung neu geladen
    var ekCalendarID: String?
    var sourceName: String?
    var readOnly: Bool?
    var isSystem: Bool { ekCalendarID != nil }
}

struct Task: Codable, Identifiable, Equatable {
    var id = UUID()
    var listID: UUID
    var title = ""
    var note = ""
    var order: Double = 0
    var priority: Priority = .none
    var done = false
    var completedAt: Date?
    var due: Date?              // Fälligkeit (Tag); mit hasTime auch Uhrzeit
    var hasTime = true
    var repeatRule: Repeat = .none
    var repeatEnd: Date?
    var seriesID: UUID?
    var anchor: Date?           // ursprüngliche Fälligkeit der Serie (Ankertag für Monatsende / 29. Februar)
    var alarmFired = false
    var snoozedUntil: Date?
    var locationOn = false
    var address = ""
    var arriving = false
    var lat: Double?
    var lon: Double?
    var ekID: String?           // gesetzt = lebt im System (EventKit), nicht in store.json

    var isOverdue: Bool {
        guard !done, let d = due else { return false }
        return hasTime ? d < Date() : Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: Date())
    }
    /// Zeitpunkt des Alarms; Datum ohne Uhrzeit → 09:00 (kein versehentlicher Mitternachtsalarm, ALM-01)
    var alarmDate: Date? {
        guard let d = due, !done else { return nil }
        if hasTime { return d }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d)
    }
}

struct Snapshot: Codable { var lists: [RList]; var tasks: [Task] }   // nur lokale Daten; Systemänderungen sind nicht rückgängig zu machen
struct DiskFile: Codable { var schema = 1; var lists: [RList]; var tasks: [Task] }

// MARK: - Datumsformat
enum Fmt {
    static func dayLabel(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return L("Today", "Heute") }
        if c.isDateInYesterday(d) { return L("Yesterday", "Gestern") }
        if c.isDateInTomorrow(d) { return L("Tomorrow", "Morgen") }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }
    static func due(_ t: Task, timeOnly: Bool = false) -> String {
        guard let d = t.due else { return "" }
        var s = timeOnly && t.hasTime ? "" : dayLabel(d)
        if t.hasTime { let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; s += (s.isEmpty ? "" : " ") + f.string(from: d) }
        return s
    }
    static func header(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = isDE ? "EEE, d. MMM yyyy" : "EEE, MMM d, yyyy"
        return f.string(from: d)
    }
}

// MARK: - Store
final class Store: ObservableObject {
    @Published var lists: [RList] = []
    @Published var tasks: [Task] = []
    private var undoStack: [Snapshot] = [], redoStack: [Snapshot] = []
    private let url: URL
    private(set) var loadError: String?
    let alarms = Alarms()
    let ek = EKBridge()

    init(demo: Bool = false) {
        let dir = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("RetroReminder-demo")
                       : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroReminder")
        // Umbenennung: Bestand aus dem alten Ordner „MountainLionReminders“ übernehmen (einmalig, nichts wird überschrieben)
        if !demo {
            let old = dir.deletingLastPathComponent().appendingPathComponent("MountainLionReminders")
            if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.moveItem(at: old, to: dir) }
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("store.json")
        if demo { try? FileManager.default.removeItem(at: url) }
        if let data = try? Data(contentsOf: url) {
            do { let f = try JSONDecoder.iso.decode(DiskFile.self, from: data); lists = f.lists; tasks = f.tasks }
            catch { // beschädigte Datei sichern statt überschreiben (QUA-08)
                loadError = "\(error)"
                try? FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("store-broken-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
        if lists.isEmpty { lists = [RList(name: L("Reminders", "Erinnerungen"), order: 0)] }
        if demo { CommandLine.arguments.contains("-ref") ? seedRef() : seedDemo() }
        alarms.store = self
        ek.store = self
        if CommandLine.arguments.contains("-demo") == false { ek.start() }
        alarms.requestAuth()
        alarms.rescheduleAll(tasks)
    }

    /// Datenbestand der Referenzaufnahme (Ars Technica, 18. Juni 2012): Liste "Tasks", 15 erledigte, 1 offene Aufgabe.
    private func seedRef() {
        lists[0].name = "Tasks"
        var t = Task(listID: lists[0].id, title: "Review Mountain Lion", note: "10.8 is due out in July, according to Apple's website and WWDC keynote.", order: 1)
        t.hasTime = false
        tasks = [t]
        for i in 0..<15 { var d = Task(listID: lists[0].id, title: "Done \(i)", order: Double(10 + i)); d.done = true; d.completedAt = Date(); tasks.append(d) }
    }

    private func seedDemo() {
        let a = lists[0].id
        let b = RList(name: L("Work", "Arbeit"), order: 1), c = RList(name: L("Shopping", "Einkauf"), order: 2)
        lists[0].name = L("Tasks", "Aufgaben"); lists += [b, c]
        func t(_ l: UUID, _ s: String, _ n: String = "", _ o: Double, due: Date? = nil, p: Priority = .none) -> Task {
            Task(listID: l, title: s, note: n, order: o, priority: p, due: due)
        }
        let cal = Calendar.current
        let y = cal.date(byAdding: .hour, value: -20, to: Date())
        tasks = [
            t(a, "Review the roadmap", "Check the open items before Friday and update the plan.", 1),
            t(a, "Write the release notes", "", 2, due: y, p: .high),
            t(a, L("Buy milk", "Milch kaufen"), "", 3, due: cal.date(byAdding: .hour, value: 5, to: Date())),
            t(b.id, L("Call highland kitchen", "Küche anrufen"), "", 4),
            t(c.id, L("Eggs", "Eier"), "", 5),
        ]
        for i in 0..<3 {
            var d = t(a, ["Get a haircut", "Call mac repair place", "Check the macaroni and cheese"][i], "", Double(10 + i))
            d.done = true; d.completedAt = cal.date(byAdding: .day, value: -i * 40 - 1, to: Date()); tasks.append(d)
        }
    }

    // MARK: Persistenz + Undo
    fileprivate func save() {
        let f = DiskFile(lists: lists.filter { !$0.isSystem }, tasks: tasks.filter { $0.ekID == nil })
        guard let data = try? JSONEncoder.iso.encode(f) else { return }
        do { try data.write(to: url, options: .atomic) } catch { NSLog("RetroReminder: save failed") }
    }
    /// Jede Änderung läuft hier durch: ein Undo-Schritt, atomare Speicherung, Alarmabgleich.
    func mutate(_ body: () -> Void) {
        undoStack.append(localSnapshot()); if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        let before = tasks, beforeLists = lists
        body()
        ek.push(beforeTasks: before, beforeLists: beforeLists)
        save()
        for t in tasks where before.first(where: { $0.id == t.id }) != t { alarms.reschedule(t) }
        for t in before where !tasks.contains(where: { $0.id == t.id }) { alarms.cancel(t.id) }
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private func localSnapshot() -> Snapshot { Snapshot(lists: lists.filter { !$0.isSystem }, tasks: tasks.filter { $0.ekID == nil }) }
    func undo() { swap(&undoStack, &redoStack) }
    func redo() { swap(&redoStack, &undoStack) }
    private func swap(_ from: inout [Snapshot], _ to: inout [Snapshot]) {
        guard let s = from.popLast() else { return }
        to.append(localSnapshot())
        lists = s.lists + lists.filter(\.isSystem); tasks = s.tasks + tasks.filter { $0.ekID != nil }
        save(); alarms.rescheduleAll(tasks)
    }

    // MARK: Abfragen
    func list(_ id: UUID) -> RList? { lists.first { $0.id == id } }
    func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }
    /// Lokale Listen zuerst, danach Systemlisten gruppiert nach Konto.
    var sortedLists: [RList] { lists.sorted { ($0.isSystem ? 1 : 0, $0.sourceName ?? "", $0.order) < ($1.isSystem ? 1 : 0, $1.sourceName ?? "", $1.order) } }
    var writableLists: [RList] { sortedLists.filter { $0.readOnly != true } }
    func open(in ids: Set<UUID>) -> [Task] { tasks.filter { ids.contains($0.listID) && !$0.done }.sorted { $0.order < $1.order } }
    func completed(in ids: Set<UUID>? = nil) -> [Task] {
        tasks.filter { $0.done && (ids?.contains($0.listID) ?? true) }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    func tasks(on day: Date) -> [Task] {
        tasks.filter { !$0.done && $0.due.map { Calendar.current.isDate($0, inSameDayAs: day) } == true }.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }
    func hasTasks(on day: Date) -> Bool { tasks.contains { !$0.done && $0.due.map { Calendar.current.isDate($0, inSameDayAs: day) } == true } }
    func search(_ q: String) -> [Task] {
        let q = q.trimmingCharacters(in: .whitespaces); guard !q.isEmpty else { return [] }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.note.localizedCaseInsensitiveContains(q) }
            .sorted { ($0.done ? 1 : 0, $0.order) < ($1.done ? 1 : 0, $1.order) }
    }

    // MARK: Aktionen
    @discardableResult func addList(_ name: String) -> UUID {
        let l = RList(name: name, order: (lists.map(\.order).max() ?? 0) + 1)
        mutate { lists.append(l) }; return l.id
    }
    func rename(_ id: UUID, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        mutate { if let i = lists.firstIndex(where: { $0.id == id }) { lists[i].name = n } }
    }
    func deleteList(_ id: UUID) {
        guard lists.count > 1 else { return }
        mutate { lists.removeAll { $0.id == id }; tasks.removeAll { $0.listID == id } }
    }
    @discardableResult func addTask(in list: UUID, title: String = "", due: Date? = nil) -> UUID {
        var t = Task(listID: list, title: title, order: (tasks.map(\.order).max() ?? 0) + 1)
        if let due { t.due = due; t.hasTime = false }
        mutate { tasks.append(t) }; return t.id
    }
    func update(_ t: Task) { mutate { if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t } } }
    func delete(_ id: UUID) { mutate { tasks.removeAll { $0.id == id } } }
    func move(_ id: UUID, to list: UUID) { mutate { if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].listID = list } } }

    /// Titel auf Datum prüfen ("morgen um 18:30", "tomorrow at 10am"); erkannter Teil wandert in die Fälligkeit.
    func parseDate(in t: inout Task) {
        guard t.due == nil, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: t.title, range: NSRange(t.title.startIndex..., in: t.title)),
              let d = m.date, let r = Range(m.range, in: t.title), m.range.length >= 3 else { return }
        let rest = t.title.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return }       // nie den ganzen Titel verschlucken
        t.title = rest; t.due = d
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        t.hasTime = !(c.hour == 12 && c.minute == 0) // Detector setzt 12:00 für reine Datumsangaben
    }

    /// Erledigen/Wiederöffnen; Serie erzeugt genau einen Nachfolger, Wiederöffnen räumt ihn weg (WIE-03).
    func setDone(_ id: UUID, _ done: Bool) {
        mutate {
            guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[i].done = done
            tasks[i].completedAt = done ? Date() : nil
            tasks[i].alarmFired = false
            let t = tasks[i]
            guard t.repeatRule != .none, let due = t.due else { return }
            let series = t.seriesID ?? t.id
            tasks[i].seriesID = series; tasks[i].anchor = t.anchor ?? due
            if done {
                let base = t.anchor ?? due
                var k = 1, guardN = 0
                guard var n = t.repeatRule.occurrence(k, from: base) else { return }
                while n <= due || (n < Date() && Calendar.current.startOfDay(for: n) < Calendar.current.startOfDay(for: Date())) {
                    k += 1; guardN += 1
                    guard guardN < 5000, let x = t.repeatRule.occurrence(k, from: base) else { return }
                    n = x
                }
                if let end = t.repeatEnd, n > end { return }
                var next = t; next.id = UUID(); next.done = false; next.completedAt = nil; next.due = n; next.alarmFired = false; next.ekID = nil; next.seriesID = series; next.anchor = base
                next.order = (tasks.map(\.order).max() ?? 0) + 1
                tasks.append(next)
            } else {
                // offenen Nachfolger derselben Serie entfernen, falls unverändert nachgelaufen
                if let j = tasks.firstIndex(where: { $0.seriesID == series && !$0.done && $0.id != id && ($0.due ?? .distantPast) > due }) { tasks.remove(at: j) }
            }
        }
    }

    func reorder(_ id: UUID, before target: UUID) {
        guard id != target else { return }
        mutate {
            guard let ti = tasks.firstIndex(where: { $0.id == target }), let mi = tasks.firstIndex(where: { $0.id == id }) else { return }
            let sameList = tasks.filter { $0.listID == tasks[ti].listID && !$0.done && $0.id != id }.sorted { $0.order < $1.order }
            let prev = sameList.last { $0.order < tasks[ti].order }?.order ?? tasks[ti].order - 2
            tasks[mi].listID = tasks[ti].listID
            tasks[mi].order = (prev + tasks[ti].order) / 2
        }
    }

    // MARK: Export (.ics, VTODO)
    func icsExport(_ list: [Task]) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n") }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; f.timeZone = TimeZone(identifier: "UTC")
        let fd = DateFormatter(); fd.dateFormat = "yyyyMMdd"
        var s = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//RetroReminder//EN\r\n"
        for t in list {
            s += "BEGIN:VTODO\r\nUID:\(t.id.uuidString)\r\nDTSTAMP:\(f.string(from: Date()))\r\nSUMMARY:\(esc(t.title))\r\n"
            if !t.note.isEmpty { s += "DESCRIPTION:\(esc(t.note))\r\n" }
            if let d = t.due { s += t.hasTime ? "DUE:\(f.string(from: d))\r\n" : "DUE;VALUE=DATE:\(fd.string(from: d))\r\n" }
            if t.priority != .none { s += "PRIORITY:\([0, 9, 5, 1][t.priority.rawValue])\r\n" }
            switch t.repeatRule { case .daily: s += "RRULE:FREQ=DAILY\r\n"; case .weekly: s += "RRULE:FREQ=WEEKLY\r\n"; case .biweekly: s += "RRULE:FREQ=WEEKLY;INTERVAL=2\r\n"
                case .monthly: s += "RRULE:FREQ=MONTHLY\r\n"; case .yearly: s += "RRULE:FREQ=YEARLY\r\n"; case .none: break }
            if t.done { s += "STATUS:COMPLETED\r\n"; if let c = t.completedAt { s += "COMPLETED:\(f.string(from: c))\r\n" } } else { s += "STATUS:NEEDS-ACTION\r\n" }
            if let d = t.alarmDate { _ = d; s += "BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:\(esc(t.title))\r\nTRIGGER;RELATED=END:PT0S\r\nEND:VALARM\r\n" }
            s += "END:VTODO\r\n"
        }
        return s + "END:VCALENDAR\r\n"
    }
}

extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }
extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }

// MARK: - Alarme (UserNotifications) + Ortsüberwachung
final class Alarms: NSObject, UNUserNotificationCenterDelegate, CLLocationManagerDelegate {
    weak var store: Store?
    private let lm = CLLocationManager()
    private var center: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current() }
    var denied = false

    func requestAuth() {
        guard let c = center else { return }
        c.delegate = self
        let snooze = UNNotificationAction(identifier: "snooze", title: L("Snooze 15 Minutes", "15 Minuten später"))
        let close = UNNotificationAction(identifier: "close", title: L("Close", "Schließen"))
        c.setNotificationCategories([UNNotificationCategory(identifier: "task", actions: [close, snooze], intentIdentifiers: [])])
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in DispatchQueue.main.async { self.denied = !ok } }
        lm.delegate = self
    }
    func cancel(_ id: UUID) { center?.removePendingNotificationRequests(withIdentifiers: [id.uuidString]) }
    func rescheduleAll(_ tasks: [Task]) {
        center?.removeAllPendingNotificationRequests()
        tasks.forEach(reschedule)
    }
    func reschedule(_ t: Task) {
        cancel(t.id)
        if t.ekID != nil { return }
        updateRegion(t)
        guard let c = center, !t.done, var when = t.snoozedUntil ?? t.alarmDate else { return }
        if t.snoozedUntil == nil && t.alarmFired { return }
        if when <= Date() {
            // verpasst: einmalig nachholen, danach als zugestellt markieren (ALM-05)
            guard t.snoozedUntil != nil || !t.alarmFired else { return }
            when = Date().addingTimeInterval(2)
            DispatchQueue.main.async { if var x = self.store?.task(t.id) { x.alarmFired = true; x.snoozedUntil = nil; self.store?.updateSilently(x) } }
        }
        let content = UNMutableNotificationContent()
        content.title = t.title; content.body = t.note; content.sound = .default; content.categoryIdentifier = "task"
        content.userInfo = ["id": t.id.uuidString]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: when)
        c.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        defer { done() }
        guard let s = r.notification.request.content.userInfo["id"] as? String, let id = UUID(uuidString: s) else { return }
        DispatchQueue.main.async {
            guard var t = self.store?.task(id) else { return }
            if r.actionIdentifier == "snooze" { t.snoozedUntil = Date().addingTimeInterval(15 * 60); t.alarmFired = true; self.store?.update(t) }
            else { t.alarmFired = true; t.snoozedUntil = nil; self.store?.updateSilently(t) }   // Schließen erledigt NICHT (ALM-03)
        }
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner, .sound]) }

    // Orte: öffentliche CoreLocation-Regionenüberwachung, best effort (siehe README)
    private func updateRegion(_ t: Task) {
        for r in lm.monitoredRegions where r.identifier == t.id.uuidString { lm.stopMonitoring(for: r) }
        guard t.locationOn, !t.done, let la = t.lat, let lo = t.lon else { return }
        if lm.authorizationStatus == .notDetermined { lm.requestAlwaysAuthorization() }
        let r = CLCircularRegion(center: .init(latitude: la, longitude: lo), radius: 150, identifier: t.id.uuidString)
        r.notifyOnEntry = t.arriving; r.notifyOnExit = !t.arriving
        lm.startMonitoring(for: r)
    }
    func locationManager(_ m: CLLocationManager, didEnterRegion r: CLRegion) { fire(r) }
    func locationManager(_ m: CLLocationManager, didExitRegion r: CLRegion) { fire(r) }
    private func fire(_ r: CLRegion) {
        guard let id = UUID(uuidString: r.identifier), let t = store?.task(id), !t.done, let c = center else { return }
        let content = UNMutableNotificationContent(); content.title = t.title; content.body = t.address; content.sound = .default; content.userInfo = ["id": t.id.uuidString]
        c.add(UNNotificationRequest(identifier: "loc-" + t.id.uuidString, content: content, trigger: nil))
    }
}

extension Store {
    /// Zustandsänderung ohne Undo-Schritt (Alarm-Bookkeeping).
    func updateSilently(_ t: Task) { if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t; saveNow() } }
    func saveNow() { save() }
}
