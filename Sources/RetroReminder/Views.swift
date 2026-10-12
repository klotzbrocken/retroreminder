import SwiftUI
import AppKit

/// Tastaturfokus einer Zone: meldet Fokus an den ViewState, reagiert auf Zonenanforderung (Tab) und zeichnet einen Fokusring.
struct ZoneFocus: ViewModifier {
    @ObservedObject var vs: ViewState
    let zone: Zone
    var radius: CGFloat = 4
    @FocusState private var f: Bool
    func body(content: _ViewModifier_Content<ZoneFocus>) -> some View {   // (Content ist hier durch unser eigenes Modell belegt)
        content.focusable().focusEffectDisabled().focused($f)
            .onChange(of: vs.zoneTick) { _, _ in if vs.zoneRequest == zone { f = true } }
            .onChange(of: f) { _, now in if now { vs.zone = zone } else if vs.zone == zone { vs.zone = nil } }
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.55), lineWidth: 1.5).opacity(f ? 1 : 0).allowsHitTesting(false))
    }
}

// MARK: - Wurzel
struct RootView: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    var body: some View {
        let compact = vs.compact
        ZStack(alignment: .topLeading) {
            Tiled(image: Tex.leather)
            // Titelleiste: Lichtverlauf (gemessen: 86 → 55 über 22 px)
            LinearGradient(stops: [108, 85, 76, 73, 71.5, 68, 65, 62, 61.5, 60.5, 59.6, 59, 58, 57.6, 57.3, 56.5, 56.2, 56, 55, 54.7, 54.9, 54, 53.5, 48.3].enumerated().map { .init(color: Color.white.opacity(max(0, ($0.element - 48.3) / 206.7)), location: Double($0.offset) / 23) }, startPoint: .top, endPoint: .bottom).frame(height: 24)
            VStack(spacing: 0) {
                ZStack {
                    DragArea()
                    Text(vs.single ? (vs.content.header) : "RetroReminder")
                        .font(.lucida(12, bold: true)).foregroundColor(Color(vs.active ? 230 : 190))
                        .shadow(color: .black.opacity(0.8), radius: 0, y: 1).offset(y: 4).allowsHitTesting(false)     // möglichst nah an der Ampelhöhe, ohne das Papier zu berühren
                }.frame(height: 22)
                HStack(alignment: .top, spacing: 0) {
                    if !compact { SidebarView(vs: vs, store: store).frame(width: 209).accessibilityElement(children: .contain).accessibilityLabel(L("Sidebar", "Seitenleiste")).accessibilitySortPriority(2) }
                    VStack(spacing: 0) {
                        PaperView(vs: vs, store: store).accessibilityElement(children: .contain).accessibilityLabel(L("Reminders", "Erinnerungen")).accessibilitySortPriority(1)
                            .padding(.trailing, compact ? 8 : 10).padding(.leading, compact ? 8 : 0).padding(.top, 2)
                            .padding(.bottom, compact && !vs.single ? 3 : 7)
                        if compact && !vs.single { BottomBar(vs: vs, store: store).frame(height: 26) }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) { HStack(spacing: 0) { Color.white.opacity(0.045).frame(width: 1); Color.white.opacity(0.024).frame(width: 1); Color.white.opacity(0.01).frame(width: 1); Spacer() }.padding(.vertical, 5).allowsHitTesting(false) }
        .overlay(alignment: .bottom) { VStack(spacing: 0) { Spacer(); Color.white.opacity(0.045).frame(height: 1) }.padding(.horizontal, 5).allowsHitTesting(false) }
        .environment(\.colorScheme, .light)
        .background(KeyCatcher(vs: vs))
    }
}

struct KeyCatcher: View {
    @ObservedObject var vs: ViewState
    var body: some View { Color.clear.onAppear { NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in } } }
}

// MARK: - Fenster verschieben / Größe ändern
final class DragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { if e.clickCount == 2 { window?.miniaturize(nil) } else { window?.performDrag(with: e) } }
}
struct DragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragNSView() }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - Seitenleiste
struct SidebarView: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            SearchField(vs: vs).padding(.horizontal, 9).padding(.top, 5).padding(.bottom, 10).frame(height: 37)
            ListBox(vs: vs, store: store).padding(.horizontal, 9).padding(.top, 1)
                .frame(minHeight: 99, maxHeight: .infinity)
            if vs.showCal { CalendarView(vs: vs, store: store).padding(.horizontal, 9).padding(.top, 11).frame(height: 211) }
            Spacer(minLength: 0).frame(height: 0)
            HStack(spacing: 8) {
                LeatherButton(vs: vs, zone: .btnSidebar, kind: .sidebar, label: L("Compact View", "Kompaktansicht")) { withAnimation(.easeInOut(duration: 0.15)) { vs.compact = true } }
                LeatherButton(vs: vs, zone: .btnCalendar, kind: .calendar, label: L("Show or Hide Calendar", "Kalender ein- oder ausblenden")) { withAnimation(.easeInOut(duration: 0.15)) { vs.showCal.toggle() } }
                LeatherButton(vs: vs, zone: .btnNewList, kind: .plus, label: L("New List", "Neue Liste")) { vs.newList() }
                Spacer()
            }.padding(.horizontal, 9).frame(height: 21).padding(.top, 9).padding(.bottom, 8)
        }
    }
}

struct SearchField: View {
    @ObservedObject var vs: ViewState
    @FocusState private var focus: Bool
    var body: some View {
        HStack(spacing: 4) {
            Canvas { g, _ in
                g.stroke(Path(ellipseIn: CGRect(x: 1, y: 1, width: 8.5, height: 8.5)), with: .color(Color(160)), lineWidth: 1.8)
                var h = Path(); h.move(to: .init(x: 8.2, y: 8.2)); h.addLine(to: .init(x: 12, y: 12))
                g.stroke(h, with: .color(Color(160)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }.frame(width: 13, height: 13).shadow(color: .black.opacity(0.6), radius: 0, y: 1)
            TextField("", text: $vs.query).textFieldStyle(.plain).font(.hn(12)).foregroundColor(Color(235)).focused($focus)
                .onChange(of: vs.focusSearchTick) { _, _ in focus = true }
                .onChange(of: vs.zoneTick) { _, _ in if vs.zoneRequest == .search { focus = true } }
                .onChange(of: focus) { _, f in if f { vs.zone = .search } else if vs.zone == .search { vs.zone = nil } }
                .onSubmit { vs.selected = vs.flat.first?.id; vs.focusPaperTick += 1 }        // Return: erster Treffer, Fokus in die Liste
                .onExitCommand { vs.query = ""; vs.focusPaperTick += 1 }                      // Esc: Suche beenden
                .accessibilityLabel(L("Search", "Suche"))
            if !vs.query.isEmpty { Button { vs.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Color(150)) }.buttonStyle(.plain) }
        }
        .padding(.leading, 5).padding(.trailing, 7).frame(height: 22)
        .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1.5).opacity(focus ? 1 : 0).allowsHitTesting(false))
        .background(
            ZStack {
                Capsule().fill(Color(57)).offset(y: 3)
                Capsule().fill(Color(62)).offset(y: 2)
                Capsule().fill(Color(84)).offset(y: 1)                        // untere Lichtkante (gemessen 84/62/57)
                Capsule().fill(vprofile([31, 38, 44, 46, 47, 48, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 48, 44, 37]))
            }
        )
        .padding(.bottom, 1)
    }
}

struct ListBox: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    var body: some View {
        ZStack(alignment: .top) {
            Tiled(image: Tex.pit)
            Canvas { g, size in    // Leerzeilen: dunkle Trennlinie + feine Lichtkante
                var y: CGFloat = 33
                while y <= size.height { g.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 1)), with: .color(Color(40))); y += 33 }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    SideRow(vs: vs, title: L("Completed", "Erledigt"), selected: vs.mode == .completed && !vs.searching) { vs.go(.completed) }
                    if case .day(let d) = vs.mode, !vs.searching {
                        SideRow(vs: vs, title: Fmt.dayLabel(d), selected: true) {}
                    }
                    let ls = store.sortedLists, grouped = ls.contains(where: \.isSystem)
                    ForEach(Array(ls.enumerated()), id: \.element.id) { i, l in
                        if grouped, i == 0 || ls[i - 1].sourceName != l.sourceName || ls[i - 1].isSystem != l.isSystem {
                            SourceHeader(title: l.isSystem ? (l.sourceName ?? L("System", "System")) : L("On My Mac", "Auf meinem Mac"))
                        }
                        ListRow(vs: vs, store: store, list: l)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(30), lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1).padding(.horizontal, 1) }
        .modifier(ZoneFocus(vs: vs, zone: .lists))
        .onKeyPress(.upArrow) { vs.step(-1); return .handled }
        .onKeyPress(.downArrow) { vs.step(1); return .handled }
        .onKeyPress(.home) { if let f = vs.pages.first { vs.go(f) }; return .handled }
        .onKeyPress(.end) { if let l = vs.pages.last { vs.go(l) }; return .handled }
        .onKeyPress(.return) { if let id = vs.currentListID { vs.renaming = id }; return .handled }   // Return: Liste umbenennen
        .onKeyPress(.rightArrow) { vs.requestZone(.paper); return .handled }                           // → : in die Liste
        .accessibilityElement(children: .contain).accessibilityLabel(L("Lists", "Listen"))
    }
}

/// Konto-Überschrift in der Liste (Referenz Screenshot „iCloud“): kleine graue Versalien auf dunklem Band.
struct SourceHeader: View {
    let title: String
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(58), Color(44)], startPoint: .top, endPoint: .bottom)
            VStack { Spacer(); Color(30).frame(height: 1) }
            Text(title).font(.hn(9, .bold)).foregroundColor(Color(135)).shadow(color: .black, radius: 0, y: 1).padding(.leading, 8).accessibilityAddTraits(.isHeader)
        }.frame(height: 16)
    }
}

struct SideRow: View {
    @ObservedObject var vs: ViewState
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        ZStack(alignment: .leading) {
            if selected {
                LinearGradient(colors: [Color(89, 29, 41), Color(84, 22, 36), Color(78, 16, 29), Color(72, 14, 20)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) { Color(110, 59, 66).frame(height: 1); Spacer() }
            }
            VStack { Spacer(); Color(selected ? 29 : 40).frame(height: 1) }
            Text(title).font(.hn(12.5, selected ? .medium : .regular)).foregroundColor(selected ? Color(214) : Color(190))
                .shadow(color: .black.opacity(0.85), radius: 0, y: 1).padding(.leading, 10).lineLimit(1)
        }
        .frame(height: 33).contentShape(Rectangle()).onTapGesture(perform: action)
        .accessibilityElement().accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }
}

struct ListRow: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    let list: RList
    @State private var name = ""
    @FocusState private var focus: Bool
    var selected: Bool { vs.mode == .lists && !vs.searching && vs.effectiveSel.contains(list.id) }
    var body: some View {
        Group {
            if vs.renaming == list.id {
                TextField("", text: $name).textFieldStyle(.plain).font(.hn(13, .bold)).foregroundColor(.white).focused($focus)
                    .padding(.leading, 10).frame(height: 33).background(Color(72, 14, 20))
                    .onAppear { name = list.name; focus = true }
                    .onSubmit { commit() }
                    .onExitCommand { vs.renaming = nil }
                    .onChange(of: focus) { _, f in if !f { commit() } }
            } else {
                SideRow(vs: vs, title: list.name, selected: selected) {
                    vs.selected = nil; vs.query = ""
                    if NSEvent.modifierFlags.contains(.command) && vs.mode == .lists {
                        if vs.sel.contains(list.id) && vs.sel.count > 1 { vs.sel.remove(list.id) } else { vs.sel.insert(list.id) }
                    } else { vs.mode = .lists; vs.sel = [list.id]; vs.showDone = false }
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded { vs.renaming = list.id })
                .contextMenu {
                    Button(L("Rename", "Umbenennen")) { vs.renaming = list.id }
                    Button(L("Delete List", "Liste löschen")) { vs.deleteList(list.id) }.disabled(store.lists.count < 2)
                }
            }
        }
    }
    func commit() { if vs.renaming == list.id { store.rename(list.id, name); vs.renaming = nil } }
}

// MARK: - Untere Knöpfe
struct LeatherButton: View {
    enum Kind { case sidebar, calendar, plus }
    @ObservedObject var vs: ViewState
    let zone: Zone
    let kind: Kind
    var label = ""
    let action: () -> Void
    @State private var down = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color(72)).offset(y: 1)   // Lichtkante unten (gemessen ≈ 78)
            RoundedRectangle(cornerRadius: 7).fill(down ? vprofile([26, 40, 44, 45, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 28, 24]) : vprofile([26, 58, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 50, 48, 46, 44, 42, 40, 37, 34, 30, 24]))
            RoundedRectangle(cornerRadius: 7).stroke(Color(20), lineWidth: 1.5)
            icon
        }
        .frame(width: 31, height: 22)
        .modifier(ZoneFocus(vs: vs, zone: zone, radius: 7))
        .onKeyPress(.space) { action(); return .handled }
        .onKeyPress(.return) { action(); return .handled }
        .accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in down = true }.onEnded { v in down = false; if abs(v.translation.width) < 31 && abs(v.translation.height) < 22 { action() } })
    }
    @ViewBuilder var icon: some View {
        switch kind {
        case .plus:
            Canvas { g, _ in
                g.fill(Path(CGRect(x: 0, y: 4.5, width: 11, height: 2)), with: .color(Color(172)))
                g.fill(Path(CGRect(x: 4.5, y: 0, width: 2, height: 11)), with: .color(Color(172)))
            }.frame(width: 11, height: 11).shadow(color: .black.opacity(0.7), radius: 0, y: 1)
        case .calendar:
            Canvas { g, _ in
                g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 13, height: 12), cornerRadius: 1), with: .linearGradient(.init(colors: [Color(185), Color(140)]), startPoint: .zero, endPoint: .init(x: 0, y: 12)))
                for row in 0..<3 { for col in 0..<4 { g.fill(Path(CGRect(x: 1.5 + CGFloat(col) * 2.9, y: 3.5 + CGFloat(row) * 2.9, width: 2, height: 2)), with: .color(Color(48))) } }
            }.frame(width: 13, height: 12).shadow(color: .black.opacity(0.7), radius: 0, y: 1)
        case .sidebar:
            Canvas { g, _ in
                g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 13, height: 12), cornerRadius: 1.5), with: .color(Color(170)))
                g.fill(Path(CGRect(x: 2, y: 2, width: 9, height: 8)), with: .color(Color(40)))
                var p = Path(); p.move(to: .init(x: 4, y: 8.5)); p.addLine(to: .init(x: 9, y: 8.5)); p.addLine(to: .init(x: 6.5, y: 4.5)); p.closeSubpath()
                g.fill(p, with: .color(Color(170)))
            }.frame(width: 13, height: 12).shadow(color: .black.opacity(0.7), radius: 0, y: 1)
        }
    }
}

// MARK: - Kompakt: Leiste unten mit Seitenleisten-Knopf und Seitenpunkten
struct BottomBar: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    var body: some View {
        ZStack {
            HStack {
                if !vs.single { LeatherButton(vs: vs, zone: .btnSidebar, kind: .sidebar, label: L("Show Lists", "Listen einblenden")) { withAnimation(.easeInOut(duration: 0.15)) { vs.compact = false } }.padding(.leading, 9) }
                Spacer()
            }
            if !vs.single {
                HStack(spacing: 7) {
                    ForEach(Array(vs.pages.enumerated()), id: \.offset) { _, p in
                        Circle().fill(vs.currentPage == p ? Color(235) : Color(110)).frame(width: 5, height: 5)
                            .contentShape(Circle().inset(by: -4)).onTapGesture { vs.go(p) }
                    }
                }
            }
        }
    }
}

// MARK: - Kalender
struct CalendarView: View {
    @ObservedObject var vs: ViewState
    @ObservedObject var store: Store
    var cal: Calendar { .current }
    var body: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: vs.month))!
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first)!
        let days = (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let f = DateFormatter(); let _ = (f.dateFormat = "LLLL")
        let syms = cal.veryShortStandaloneWeekdaySymbols, short = cal.shortWeekdaySymbols
        ZStack(alignment: .topLeading) {
            Tiled(image: Tex.pit)
            VStack(spacing: 0) {
                ZStack {
                    Text(f.string(from: first)).font(.hn(15, .bold)).foregroundColor(Color(150)).shadow(color: .black, radius: 0, y: 1).offset(x: -2, y: 2)
                    HStack {
                        Tri(left: true).onTapGesture { vs.month = cal.date(byAdding: .month, value: -1, to: first)! }.accessibilityAction { vs.month = cal.date(byAdding: .month, value: -1, to: first)! }
                        Spacer()
                        Tri(left: false).onTapGesture { vs.month = cal.date(byAdding: .month, value: 1, to: first)! }.accessibilityAction { vs.month = cal.date(byAdding: .month, value: 1, to: first)! }
                    }.padding(.horizontal, 12)
                }.frame(height: 26)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        let wd = (i + cal.firstWeekday - 1) % 7
                        Text(String(short[wd].prefix(2))).font(.hn(9, .bold)).foregroundColor(Color(150)).shadow(color: .black, radius: 0, y: 1)
                            .frame(width: 27)
                    }
                }.frame(height: 17).padding(.top, -2).opacity(syms.isEmpty ? 0 : 1)
                ZStack(alignment: .topLeading) {
                    Canvas { g, size in
                        for r in 0...6 { g.fill(Path(CGRect(x: 0, y: CGFloat(r) * 26.5, width: size.width, height: 1)), with: .color(Color(42))) }
                        for c in 1..<7 { g.fill(Path(CGRect(x: CGFloat(c) * 27, y: 0, width: 1, height: size.height)), with: .color(Color(42))) }
                    }
                    ForEach(0..<42, id: \.self) { i in
                        let d = days[i]
                        DayCell(d: d, inMonth: cal.isDate(d, equalTo: first, toGranularity: .month), isToday: cal.isDate(d, inSameDayAs: shownToday),
                                isSel: { if case .day(let s) = vs.mode { return cal.isDate(s, inSameDayAs: d) && !vs.searching }; return false }(),
                                dot: store.hasTasks(on: d), cursor: vs.zone == .calendar && cal.isDate(d, inSameDayAs: vs.calCursor))
                            .frame(width: 27, height: 26.5).offset(x: CGFloat(i % 7) * 27, y: CGFloat(i / 7) * 26.5)
                            .onTapGesture { vs.calCursor = d; vs.selectDay(d); vs.requestZone(.calendar) }
                            .accessibilityElement().accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                            .accessibilityValue([cal.isDate(d, inSameDayAs: shownToday) ? L("today", "heute") : nil,
                                                 { if case .day(let s) = vs.mode, cal.isDate(s, inSameDayAs: d) { return L("selected", "ausgewählt") }; return nil }(),
                                                 store.hasTasks(on: d) ? L("has reminders", "hat Erinnerungen") : nil].compactMap { $0 }.joined(separator: ", "))
                            .accessibilityAddTraits(.isButton).accessibilityAction { vs.selectDay(d) }
                    }
                }.frame(width: 189, height: 159).offset(x: -1, y: -1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(30), lineWidth: 1))
        .modifier(ZoneFocus(vs: vs, zone: .calendar))
        .onKeyPress(.leftArrow) { vs.calMove(days: -1); return .handled }
        .onKeyPress(.rightArrow) { vs.calMove(days: 1); return .handled }
        .onKeyPress(.upArrow) { vs.calMove(days: -7); return .handled }
        .onKeyPress(.downArrow) { vs.calMove(days: 7); return .handled }
        .onKeyPress(.pageUp) { vs.calMove(months: -1); return .handled }
        .onKeyPress(.pageDown) { vs.calMove(months: 1); return .handled }
        .onKeyPress(.home) { vs.calCursor = shownToday; vs.month = shownToday; return .handled }
        .onKeyPress(.return) { vs.selectDay(vs.calCursor); return .handled }
        .onKeyPress(.space) { vs.selectDay(vs.calCursor); return .handled }
        .accessibilityElement(children: .contain).accessibilityLabel(L("Calendar", "Kalender"))
        .frame(width: 191, height: 200)
    }
}
struct Tri: View {
    let left: Bool
    var label: String { left ? L("Previous Month", "Vorheriger Monat") : L("Next Month", "Nächster Monat") }
    var body: some View {
        Canvas { g, _ in
            var p = Path()
            if left { p.move(to: .init(x: 0, y: 5)); p.addLine(to: .init(x: 9, y: 0)); p.addLine(to: .init(x: 9, y: 10)) }
            else { p.move(to: .init(x: 9, y: 5)); p.addLine(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 0, y: 10)) }
            p.closeSubpath(); g.fill(p, with: .color(Color(150)))
        }.frame(width: 9, height: 10).padding(6).contentShape(Rectangle())
            .accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isButton)
    }
}
struct DayCell: View {
    let d: Date, inMonth: Bool, isToday: Bool, isSel: Bool, dot: Bool
    var cursor = false
    var body: some View {
        ZStack {
            if isToday || isSel { Rectangle().fill(Color(28)).overlay(Rectangle().stroke(Color(18), lineWidth: 1)) }
            Text("\(Calendar.current.component(.day, from: d))")
                .font(.hn(13.5, isToday ? .bold : .medium)).foregroundColor(isToday ? Color(225) : inMonth ? Color(182) : Color(72))
                .shadow(color: .black.opacity(0.9), radius: 0, y: 1)
            if dot { Circle().fill(Color(170)).frame(width: 2.5, height: 2.5).offset(y: 10) }
            if cursor { Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 1.5).padding(1) }       // Tastaturcursor
        }.contentShape(Rectangle())
    }
}
