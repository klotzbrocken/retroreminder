import SwiftUI
import AppKit

struct PaperView: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    @FocusState private var paperFocus: Bool

    var body: some View {
        let c = vs.content
        ZStack(alignment: .topLeading) {
            Tiled(image: Tex.paper)
            ZStack(alignment: .topLeading) { VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(c.header).font(.hn(27)).foregroundColor(.mlRed).lineLimit(1).accessibilityAddTraits(.isHeader).padding(.leading, 11).padding(.top, 9)
                    Spacer()
                    PlusButton(vs: vs) { vs.newTask() }.padding(.trailing, 8)
                }.frame(height: 46)
                ListArea(vs: vs, store: store, c: c).padding(.horizontal, 6).padding(.bottom, 10)
            }
            .id(vs.pageKey).transition(.push(from: vs.pageEdge)) }
            .offset(x: vs.dragX)      // folgt dem Finger beim Wischen
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(36), lineWidth: 1))
        .overlay(alignment: .top) { Color(217).frame(height: 1).padding(.horizontal, 3).offset(y: 1) }
        .focusable().focusEffectDisabled().focused($paperFocus)
        .onAppear { paperFocus = true }
        .onChange(of: vs.focusPaperTick) { _, _ in paperFocus = true }
        .onChange(of: vs.zoneTick) { _, _ in if vs.zoneRequest == .paper { paperFocus = true } }
        .onChange(of: paperFocus) { _, f in if f { vs.zone = .paper } else if vs.zone == .paper { vs.zone = nil } }
        .onChange(of: vs.editing) { _, e in if e == nil { paperFocus = true } }     // nach Return/Esc zurück in die Listensteuerung
        .onKeyPress(.leftArrow) { guard vs.compact, !vs.single, vs.editing == nil else { return .ignored }; vs.step(-1); return .handled }
        .onKeyPress(.rightArrow) { guard vs.compact, !vs.single, vs.editing == nil else { return .ignored }; vs.step(1); return .handled }
        .onKeyPress(.space) { guard vs.editing == nil else { return .ignored }; vs.toggleSelected(); return .handled }
        .onKeyPress(.downArrow) { vs.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { vs.moveSelection(-1); return .handled }
        .onKeyPress(.return) { if let s = vs.selected, vs.editing == nil { vs.editing = s; return .handled }; return .ignored }
        .onKeyPress(.delete) { guard vs.editing == nil else { return .ignored }; vs.deleteSelectedTask(); return .handled }
        .onKeyPress(.escape) { if vs.editing != nil { vs.cancelEditing() } else { vs.selected = nil }; return .handled }
        .background(GeometryReader { g in Color.clear.onAppear { vs.pageWidth = g.size.width }.onChange(of: g.size.width) { _, w in vs.pageWidth = w } })
        .background(SwipeCatcher(onChange: { if vs.compact && !vs.single { vs.swipeChanged($0) } },
                                 onEnd: { if vs.compact && !vs.single { vs.swipeEnded($0) } }))
    }
}

/// Horizontales Trackpad-Wischen mit Mitziehen: onChange liefert die laufende Verschiebung, onEnd die Endverschiebung.
/// Die Achse wird mit der ersten Bewegung festgelegt; vertikales Scrollen der Liste bleibt unberührt.
struct SwipeCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void
    final class V: NSView {
        var onChange: ((CGFloat) -> Void)?, onEnd: ((CGFloat) -> Void)?
        var acc: CGFloat = 0, horizontal: Bool?
        var mon: Any?
        override func viewDidMoveToWindow() {
            if let m = mon { NSEvent.removeMonitor(m); mon = nil }
            guard window != nil else { return }
            mon = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let s = self, e.window === s.window, e.hasPreciseScrollingDeltas, e.momentumPhase.isEmpty else { return e }
                if e.phase.contains(.began) || e.phase.contains(.mayBegin) { s.acc = 0; s.horizontal = nil }
                if s.horizontal == nil, e.scrollingDeltaX != 0 || e.scrollingDeltaY != 0 { s.horizontal = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) }
                if s.horizontal == true {
                    s.acc += e.scrollingDeltaX; s.onChange?(s.acc)
                    if e.phase.contains(.ended) || e.phase.contains(.cancelled) { s.onEnd?(s.acc); s.acc = 0; s.horizontal = nil }
                } else if e.phase.contains(.ended) || e.phase.contains(.cancelled) { s.horizontal = nil }
                return e
            }
        }
        deinit { if let m = mon { NSEvent.removeMonitor(m) } }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onChange = onChange; v.onEnd = onEnd; return v }
    func updateNSView(_ v: V, context: Context) { v.onChange = onChange; v.onEnd = onEnd }
}

struct PlusButton: View {
    @ObservedObject var vs: ViewState
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(250), Color(236)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 4).stroke(Color(205), lineWidth: 1)
                Text("+").font(.hn(21, .medium)).foregroundColor(Color(188)).offset(y: -1)
            }.frame(width: 26, height: 24)
        }.buttonStyle(.plain).help(L("New Reminder", "Neue Erinnerung"))
            .modifier(ZoneFocus(vs: vs, zone: .plus))
            .onKeyPress(.space) { action(); return .handled }
            .onKeyPress(.return) { action(); return .handled }
            .accessibilityLabel(L("New Reminder", "Neue Erinnerung"))
    }
}

struct ListArea: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    let c: Content
    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if c.showDoneRow { CompletedRow(vs: vs, count: c.doneCount ?? 0) }
                    ZStack(alignment: .topLeading) {
                        // Randlinie: grau + rosa (gemessen)
                        HStack(spacing: 0) { Color(224).frame(width: 1); Color.clear.frame(width: 1); Color.rulePink.frame(width: 1) }.padding(.leading, 28)
                        VStack(spacing: 0) {
                            ForEach(c.secs) { s in
                                if let t = s.title { Band(title: t) }
                                ForEach(s.tasks) { t in TaskRow(vs: vs, store: store, task: t, showList: vs.mode == .completed || vs.searching) }
                            }
                            Filler().frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                .contentShape(Rectangle()).onTapGesture { vs.newTask() }
                        }
                    }.frame(maxHeight: .infinity)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .overlay(Rectangle().stroke(Color.paperLine, lineWidth: 1).allowsHitTesting(false))
        }
    }
}

struct Filler: View {
    var body: some View {
        Canvas { g, size in
            var y: CGFloat = 32.5
            while y < size.height + 33 {
                var p = Path(); p.move(to: .init(x: 29, y: y)); p.addLine(to: .init(x: size.width, y: y))
                g.stroke(p, with: .color(Color(200)), style: StrokeStyle(lineWidth: 1, dash: [1, 1.5]))
                y += 33
            }
        }
    }
}

struct Band: View {
    let title: String
    var body: some View {
        ZStack(alignment: .leading) {
            Color(252, 222, 228)
            VStack(spacing: 0) { Color(240, 170, 185).frame(height: 1); Spacer(); Color(240, 170, 185).frame(height: 1) }
            Text(title).font(.hn(10, .bold)).foregroundColor(.mlRed).padding(.leading, 8).accessibilityAddTraits(.isHeader)
        }.frame(height: 17)
    }
}

struct CompletedRow: View {
    @ObservedObject var vs: ViewState
    let count: Int
    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) { Spacer(); Color.paperLine.frame(height: 1) }
            HStack(spacing: 0) {
                Text("\(count)").font(.hn(17, .bold)).foregroundColor(Color(190)).frame(width: 29, alignment: .center)
                Text(L("Completed", "Erledigt")).font(.hn(13)).foregroundColor(Color(68)).padding(.leading, 10).offset(y: 2)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(Color(165))
                    .rotationEffect(.degrees(vs.showDone ? 90 : 0)).padding(.trailing, 8)
            }
        }
        .frame(height: 33).contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { vs.showDone.toggle() } }
        .accessibilityElement(children: .ignore).accessibilityLabel(L("Completed, \(count)", "Erledigt, \(count)"))
        .accessibilityValue(vs.showDone ? L("expanded", "eingeblendet") : L("collapsed", "ausgeblendet"))
        .accessibilityAddTraits(.isButton).accessibilityAction(.default) { withAnimation { vs.showDone.toggle() } }
    }
}

// MARK: - Zeile
struct TaskRow: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    let task: Task
    let showList: Bool
    @State private var hover = false
    @State private var pending: Bool?
    @State private var draft = ""
    @State private var frame: CGRect = .zero
    @FocusState private var focus: Bool

    var checked: Bool { pending ?? task.done }
    var editing: Bool { vs.editing == task.id }

    var subtitle: (String, Bool)? {
        var parts: [String] = []
        if task.due != nil {
            var sameDay = false
            if case .day(let d) = vs.mode, !vs.searching, let due = task.due { sameDay = Calendar.current.isDate(due, inSameDayAs: d) && !task.isOverdue }
            parts.append(Fmt.due(task, timeOnly: sameDay))   // in der Tagesansicht reicht die Uhrzeit
        }
        if task.locationOn && !task.address.isEmpty { parts.append("\(task.arriving ? L("Arriving", "Ankommen") : L("Leaving", "Verlassen")): \(task.address)") }
        if task.repeatRule != .none && task.due != nil { parts.append("↻") }
        if showList, let l = store.list(task.listID) { parts.append(l.name) }
        if let n = task.note.split(separator: "\n").first, !n.isEmpty { parts.append(String(n)) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), task.isOverdue)
    }

    var body: some View {
        let sub = subtitle
        ZStack(alignment: .leading) {
            VStack(spacing: 0) { Spacer(); Dotted() }
            if vs.selected == task.id { Color.black.opacity(0.045) }
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("", text: $draft).textFieldStyle(.plain).font(.hn(13)).foregroundColor(Color(68)).focused($focus)
                        .onSubmit { commit() }
                        .onExitCommand { cancel() }
                        .onKeyPress(.escape) { cancel(); return .handled }
                        .onChange(of: focus) { _, f in if !f { commit() } }
                        .onAppear { draft = task.title; DispatchQueue.main.async { focus = true } }
                } else {
                    Text((task.priority == .none ? "" : task.priority.marks + " ") + task.title).font(.hn(13)).foregroundColor(Color(68)).lineLimit(1)
                        .offset(y: sub == nil ? 0 : 3)
                }
                if let (s, over) = sub {
                    Text(s).font(.hn(11)).foregroundColor(over ? Color(205, 60, 70) : Color(170)).lineLimit(1).offset(y: 1)
                }
            }.padding(.leading, 39).padding(.trailing, 30).padding(.bottom, sub == nil ? 0 : 1)
            Checkbox(checked: checked, overdue: task.isOverdue).offset(x: 9, y: sub == nil ? 0 : 1)
                .contentShape(Rectangle().inset(by: -6))
                .onTapGesture { toggle() }
                .accessibilityLabel(task.title).accessibilityValue(checked ? L("completed", "erledigt") : L("open", "offen"))
                .accessibilityAddTraits(.isButton)
            HStack { Spacer()
                if hover || vs.selected == task.id {
                    InfoButton().onTapGesture { openInfo() }.padding(.trailing, 5)
                }
            }
        }
        // VoiceOver: eine Zeile = ein Element; Priorität/Überfällig sind Text, nicht nur Farbe; Standardaktion = Erledigen, weitere als Aktionen
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([task.priority == .none ? nil : L("Priority \(task.priority.label)", "Priorität \(task.priority.label)"), task.title.isEmpty ? L("New reminder", "Neue Erinnerung") : task.title].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue([checked ? L("completed", "erledigt") : L("open", "offen"), task.isOverdue ? L("overdue", "überfällig") : nil, sub?.0].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(vs.selected == task.id ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { toggle() }
        .accessibilityAction(named: L("Show Info", "Informationen")) { openInfo() }
        .accessibilityAction(named: L("Edit Title", "Titel bearbeiten")) { vs.selected = task.id; vs.editing = task.id }
        .accessibilityAction(named: L("Delete", "Löschen")) { store.delete(task.id) }
        .frame(height: 33).background(GeometryReader { p in Color.clear.onAppear { frame = p.frame(in: .global) }.onChange(of: p.frame(in: .global)) { _, f in frame = f } })
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { openInfo() }
        .onTapGesture { vs.selected = task.id; vs.editing = nil; vs.focusPaperTick += 1 }
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            store.reorder(id, before: task.id); return true
        }
        .contextMenu {
            Button(L("Show Info", "Informationen")) { openInfo() }
            Button(task.done ? L("Mark as Incomplete", "Als nicht erledigt markieren") : L("Mark as Completed", "Als erledigt markieren")) { store.setDone(task.id, !task.done) }
            Menu(L("Move to List", "In Liste verschieben")) {
                ForEach(store.sortedLists) { l in Button(l.name) { store.move(task.id, to: l.id) }.disabled(l.id == task.listID) }
            }
            Divider()
            Button(L("Delete", "Löschen")) { store.delete(task.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MLInfo"))) { n in if (n.object as? UUID) == task.id, (n.userInfo?["vs"] as? ViewState) === vs { openInfo() } }
        .transition(.opacity)
    }

    func toggle() {
        let new = !task.done
        withAnimation(.easeOut(duration: 0.1)) { pending = new }
        DispatchQueue.main.asyncAfter(deadline: .now() + (new ? 0.5 : 0.15)) { pending = nil; withAnimation(.easeOut(duration: 0.2)) { store.setDone(task.id, new) }; announce((new ? L("Completed: ", "Erledigt: ") : L("Reopened: ", "Wieder geöffnet: ")) + task.title) }
    }
    func commit() {
        guard vs.editing == task.id else { return }
        vs.editing = nil
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            if vs.newlyCreated == task.id { store.undo() } else { store.delete(task.id) }
        } else if title != task.title {
            var t = task; t.title = title; store.parseDate(in: &t); store.update(t)
        }
        vs.newlyCreated = nil
    }
    func cancel() { vs.cancelEditing() }
    func openInfo() {
        vs.selected = task.id
        PopoverController.shared.show(taskID: task.id, store: store, vs: vs, rowFrame: frame)
    }
}

struct Dotted: View {
    var body: some View {
        Canvas { g, size in
            var p = Path(); p.move(to: .init(x: 29, y: 0.5)); p.addLine(to: .init(x: size.width, y: 0.5))
            g.stroke(p, with: .color(Color(200)), style: StrokeStyle(lineWidth: 1, dash: [1, 1.5]))
        }.frame(height: 1)
    }
}

struct Checkbox: View {
    let checked: Bool, overdue: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: overdue ? [Color(255, 205, 210), Color(240, 150, 160)] : [Color(234), Color(220)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 2).stroke(overdue ? Color(200, 90, 100) : Color(165), lineWidth: 1)
            if checked {
                Path { p in p.move(to: .init(x: 2.2, y: 5.5)); p.addLine(to: .init(x: 4.6, y: 8)); p.addLine(to: .init(x: 9, y: 2)) }
                    .stroke(Color(30), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }.frame(width: 11, height: 11)
    }
}

struct InfoButton: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(250), Color(228)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(Color(170), lineWidth: 1)
            Text("i").font(.custom("Georgia-BoldItalic", size: 10)).foregroundColor(Color(130))
        }.frame(width: 15, height: 15).accessibilityLabel(L("Info", "Information"))
    }
}
