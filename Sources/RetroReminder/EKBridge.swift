import Foundation
import EventKit
import CryptoKit

/// Systemerinnerungen (macOS „Erinnerungen“) über EventKit: lesen, anlegen, ändern, erledigen, löschen.
/// Datenhoheit liegt beim System; die Daten landen nie in store.json (DAT-06). Alarme übernimmt das System (kein Doppelalarm).
final class EKBridge {
    weak var store: Store?
    private let es = EKEventStore()
    private var loading = false, reloadAgain = false
    private(set) var status = L("System reminders: not connected", "Systemerinnerungen: nicht verbunden")
    static let enabledKey = "systemReminders"
    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func start() {
        guard enabled else { removeSystem(); return }
        es.requestFullAccessToReminders { ok, _ in
            DispatchQueue.main.async {
                guard ok else { self.status = L("System reminders: access denied (System Settings › Privacy › Reminders)", "Systemerinnerungen: Zugriff verweigert (Systemeinstellungen › Datenschutz › Erinnerungen)"); return }
                self.status = L("System reminders: connected", "Systemerinnerungen: verbunden")
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: self.es, queue: .main) { [weak self] _ in self?.reload() }
                self.reload()
            }
        }
    }
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { start() } else { removeSystem() }
    }
    private func removeSystem() {
        guard let s = store else { return }
        s.lists.removeAll(where: \.isSystem); s.tasks.removeAll { $0.ekID != nil }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Stabile IDs (damit Auswahl/Bearbeitung ein Neuladen überstehen)
    static func uuid(_ s: String) -> UUID {
        let h = Array(SHA256.hash(data: Data(s.utf8)).prefix(16))
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }

    // MARK: Laden
    func reload() {
        guard enabled, let store else { return }
        if loading { reloadAgain = true; return }
        loading = true
        let cals = es.calendars(for: .reminder)
        es.fetchReminders(matching: es.predicateForReminders(in: cals)) { [weak self] rems in
            DispatchQueue.main.async {
                guard let self, let store = self.store else { return }
                self.loading = false
                var lists: [RList] = [], tasks: [Task] = []
                for (i, c) in cals.enumerated() {
                    lists.append(RList(id: Self.uuid(c.calendarIdentifier), name: c.title, order: Double(i), ekCalendarID: c.calendarIdentifier,
                                       sourceName: c.source?.title, readOnly: !c.allowsContentModifications))
                }
                let sorted = (rems ?? []).sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                for (i, r) in sorted.enumerated() where r.calendar != nil { tasks.append(Self.task(from: r, order: Double(i))) }
                // Offener Editor: lokalen Titel nicht überschreiben, wenn gerade bearbeitet wird, übernimmt das nächste Neuladen
                store.lists = store.lists.filter { !$0.isSystem } + lists
                store.tasks = store.tasks.filter { $0.ekID == nil } + tasks
                if self.reloadAgain { self.reloadAgain = false; self.reload() }
            }
        }
    }

    static func task(from r: EKReminder, order: Double) -> Task {
        var t = Task(id: uuid(r.calendarItemIdentifier), listID: uuid(r.calendar.calendarIdentifier))
        t.ekID = r.calendarItemIdentifier
        t.title = r.title ?? ""; t.note = r.notes ?? ""; t.order = order
        t.priority = r.priority == 0 ? .none : r.priority <= 4 ? .high : r.priority == 5 ? .medium : .low
        t.done = r.isCompleted; t.completedAt = r.completionDate
        if let c = r.dueDateComponents, let d = Calendar.current.date(from: c) { t.due = d; t.hasTime = c.hour != nil }
        if let rule = r.recurrenceRules?.first {
            switch (rule.frequency, rule.interval) {
            case (.daily, 1): t.repeatRule = .daily
            case (.weekly, 1): t.repeatRule = .weekly
            case (.weekly, 2): t.repeatRule = .biweekly
            case (.monthly, 1): t.repeatRule = .monthly
            case (.yearly, 1): t.repeatRule = .yearly
            default: break          // komplexere Serien bleiben unverändert im System (DAT-10)
            }
            t.repeatEnd = rule.recurrenceEnd?.endDate
        }
        if let a = r.alarms?.first(where: { $0.structuredLocation != nil }), let loc = a.structuredLocation {
            t.locationOn = true; t.address = loc.title ?? ""; t.arriving = a.proximity == .enter
            t.lat = loc.geoLocation?.coordinate.latitude; t.lon = loc.geoLocation?.coordinate.longitude
        }
        return t
    }

    // MARK: Schreiben (nach jeder Store-Mutation)
    func push(beforeTasks: [Task], beforeLists: [RList]) {
        guard enabled, let s = store else { return }
        var dirty = false
        // Listen: umbenannt / gelöscht
        for old in beforeLists where old.isSystem {
            guard let cid = old.ekCalendarID, let cal = es.calendar(withIdentifier: cid) else { continue }
            if let now = s.lists.first(where: { $0.id == old.id }) {
                if now.name != old.name, cal.allowsContentModifications { cal.title = now.name; try? es.saveCalendar(cal, commit: false); dirty = true }
            } else if cal.allowsContentModifications { try? es.removeCalendar(cal, commit: false); dirty = true }
        }
        // Aufgaben, die verschwunden sind
        for old in beforeTasks where old.ekID != nil && !s.tasks.contains(where: { $0.id == old.id }) {
            if let r = es.calendarItem(withIdentifier: old.ekID!) as? EKReminder, r.calendar.allowsContentModifications { try? es.remove(r, commit: false); dirty = true }
        }
        for i in s.tasks.indices {
            let t = s.tasks[i]
            let list = s.list(t.listID)
            if let cid = list?.ekCalendarID, list?.readOnly != true, let cal = es.calendar(withIdentifier: cid) {
                if t.ekID == nil {                                 // neu im System oder aus lokaler Liste verschoben
                    let r = EKReminder(eventStore: es); r.calendar = cal; fill(r, from: t)
                    if (try? es.save(r, commit: false)) != nil { s.tasks[i].ekID = r.calendarItemIdentifier; dirty = true }
                } else if beforeTasks.first(where: { $0.id == t.id }) != t, let r = es.calendarItem(withIdentifier: t.ekID!) as? EKReminder {
                    if r.calendar.calendarIdentifier != cid { r.calendar = cal }
                    fill(r, from: t); try? es.save(r, commit: false); dirty = true
                }
            } else if t.ekID != nil, list?.isSystem != true {      // in eine lokale Liste verschoben: aus dem System entfernen
                if let r = es.calendarItem(withIdentifier: t.ekID!) as? EKReminder { try? es.remove(r, commit: false); dirty = true }
                s.tasks[i].ekID = nil
            }
        }
        if dirty { do { try es.commit() } catch { NSLog("RetroReminder: EventKit commit failed"); es.reset(); reload() } }
    }

    private func fill(_ r: EKReminder, from t: Task) {
        r.title = t.title; r.notes = t.note.isEmpty ? nil : t.note
        r.priority = [0, 9, 5, 1][t.priority.rawValue]
        if r.isCompleted != t.done { r.isCompleted = t.done }
        if let d = t.due {
            var c = Calendar.current.dateComponents(t.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: d)
            c.calendar = Calendar.current; r.dueDateComponents = c
        } else { r.dueDateComponents = nil }
        r.recurrenceRules?.forEach { r.removeRecurrenceRule($0) }
        if t.repeatRule != .none {
            let (f, n): (EKRecurrenceFrequency, Int) = { switch t.repeatRule { case .daily: return (.daily, 1); case .weekly: return (.weekly, 1)
                case .biweekly: return (.weekly, 2); case .monthly: return (.monthly, 1); default: return (.yearly, 1) } }()
            r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: f, interval: n, end: t.repeatEnd.map { EKRecurrenceEnd(end: $0) }))
        }
        // Alarme: Zeitalarm zur Fälligkeit (nur mit Uhrzeit, kein Mitternachtsalarm), Ortsalarm nur mit aufgelöster Koordinate
        r.alarms?.forEach { r.removeAlarm($0) }
        if t.hasTime, let d = t.due { r.addAlarm(EKAlarm(absoluteDate: d)) }
        if t.locationOn, let la = t.lat, let lo = t.lon {
            let a = EKAlarm(); let loc = EKStructuredLocation(title: t.address.isEmpty ? t.title : t.address)
            loc.geoLocation = CLLocation(latitude: la, longitude: lo); loc.radius = 150
            a.structuredLocation = loc; a.proximity = t.arriving ? .enter : .leave; r.addAlarm(a)
        }
    }
}
