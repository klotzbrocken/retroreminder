import SwiftUI
import AppKit
import CoreLocation

final class PopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Eigenes Popover (kein NSPopover): helle Karte mit linkem Pfeil, ragt wie im Original über den Fensterrand.
final class PopoverController: NSObject, NSWindowDelegate {
    static let shared = PopoverController()
    private var panel: PopPanel?
    private var model: DetailModel?
    private var host: NSHostingView<AnyView>?
    var snapshotView: NSView? { host }
    private var tipY: CGFloat = 0, topY: CGFloat = 0

    func show(taskID: UUID, store: Store, vs: ViewState, rowFrame: CGRect) {
        close()
        guard let win = vs.window, let t = store.task(taskID) else { return }
        let m = DetailModel(task: t, store: store)
        model = m
        let tipX = win.frame.minX + rowFrame.maxX - 8
        tipY = win.frame.maxY - rowFrame.midY
        let v = DetailView(m: m, arrowY: Binding(get: { [unowned self] in self.topY - self.tipY }, set: { _ in }),
                           resize: { [weak self] in self?.fit() }, done: { [weak self] in self?.close() })
        let h = NSHostingView(rootView: AnyView(v)); host = h
        let p = PopPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating
        p.contentView = h; p.delegate = self; p.isReleasedWhenClosed = false
        panel = p
        defer { p.makeFirstResponder(nil) }
        let size = h.fittingSize
        let scr = (win.screen ?? NSScreen.main)!.visibleFrame
        topY = min(max(tipY + size.height / 2, scr.minY + size.height), scr.maxY)
        var x = tipX
        if x + size.width > scr.maxX { x = scr.maxX - size.width }
        p.setFrame(NSRect(x: x, y: topY - size.height, width: size.width, height: size.height), display: false)
        p.makeKeyAndOrderFront(nil)
        win.addChildWindow(p, ordered: .above)
    }
    func fit() {
        guard let p = panel, let h = host else { return }
        let s = h.fittingSize
        p.setFrame(NSRect(x: p.frame.minX, y: topY - s.height, width: s.width, height: s.height), display: true)
        p.invalidateShadow()
    }
    func close() {
        guard let p = panel else { return }
        panel = nil
        model?.commit(); model = nil
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }
    func windowDidResignKey(_ n: Notification) { close() }
}

final class DetailModel: ObservableObject {
    @Published var t: Task
    @Published var geoFailed = false
    let store: Store
    private let original: Task
    init(task: Task, store: Store) { t = task; original = task; self.store = store }

    func commit() {
        var x = t
        x.title = x.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if x.title.isEmpty { x.title = original.title }
        if !x.locationOn { x.lat = nil; x.lon = nil }
        if x.due != original.due || x.hasTime != original.hasTime { x.alarmFired = false; x.snoozedUntil = nil }
        guard x != original, store.task(x.id) != nil else { return }
        store.update(x)
        // Adresse auflösen; ohne Auflösung gibt es keinen Ortsalarm (ORT-01)
        if x.locationOn, !x.address.isEmpty, (x.address != original.address || x.lat == nil) {
            let id = x.id, store = store
            CLGeocoder().geocodeAddressString(x.address) { places, _ in
                DispatchQueue.main.async {
                    guard var y = store.task(id) else { return }
                    y.lat = places?.first?.location?.coordinate.latitude; y.lon = places?.first?.location?.coordinate.longitude
                    if y.ekID != nil { store.update(y) } else { store.updateSilently(y); store.alarms.reschedule(y) }
                }
            }
        }
    }
}

struct PopoverShape: Shape {
    var arrowY: CGFloat
    func path(in r: CGRect) -> Path {
        let ax: CGFloat = 9, rad: CGFloat = 5
        let body = CGRect(x: r.minX + ax, y: r.minY, width: r.width - ax, height: r.height)
        var p = Path(roundedRect: body, cornerRadius: rad)
        let y = min(max(arrowY, rad + 10), r.height - rad - 10)
        p.move(to: .init(x: body.minX + 0.5, y: y - 8)); p.addLine(to: .init(x: r.minX, y: y)); p.addLine(to: .init(x: body.minX + 0.5, y: y + 8)); p.closeSubpath()
        return p
    }
}

struct MiniCheck: View {
    @Binding var on: Bool
    let title: String
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2.5).fill(LinearGradient(colors: [Color(252), Color(226)], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 2.5).stroke(Color(150), lineWidth: 1)
                    if on { Path { p in p.move(to: .init(x: 2.5, y: 6)); p.addLine(to: .init(x: 5, y: 8.5)); p.addLine(to: .init(x: 9, y: 2.5)) }.stroke(Color(30), style: StrokeStyle(lineWidth: 1.6, lineCap: .round)) }
                }.frame(width: 12, height: 12)
                Text(title).font(.hv(11)).foregroundColor(Color(40))
            }
        }.buttonStyle(.plain).accessibilityValue(on ? L("on", "ein") : L("off", "aus")).accessibilityAddTraits(.isToggle)
    }
}

struct MiniRadio: View {
    let selected: Bool, title: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(252), Color(226)], startPoint: .top, endPoint: .bottom))
                    Circle().stroke(Color(150), lineWidth: 1)
                    if selected { Circle().fill(Color(30)).frame(width: 5, height: 5) }
                }.frame(width: 12, height: 12)
                Text(title).font(.hv(11)).foregroundColor(Color(40))
            }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct Popup<T: Hashable>: View {
    @Binding var value: T
    let options: [T]
    let label: (T) -> String
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in Button(label(o)) { value = o } }
        } label: {
            HStack(spacing: 4) {
                Text(label(value)).font(.hv(11)).foregroundColor(Color(40))
                Canvas { g, _ in
                    var u = Path(); u.move(to: .init(x: 3, y: 0)); u.addLine(to: .init(x: 6, y: 3.6)); u.addLine(to: .init(x: 0, y: 3.6)); u.closeSubpath()
                    var d = Path(); d.move(to: .init(x: 3, y: 9)); d.addLine(to: .init(x: 6, y: 5.4)); d.addLine(to: .init(x: 0, y: 5.4)); d.closeSubpath()
                    g.fill(u, with: .color(Color(30))); g.fill(d, with: .color(Color(30)))
                }.frame(width: 6, height: 9)
            }
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityValue(label(value))
    }
}

struct DetailView: View {
    @ObservedObject var m: DetailModel
    @Binding var arrowY: CGFloat
    let resize: () -> Void
    let done: () -> Void
    @State private var editingNote = false
    @FocusState private var noteFocus: Bool

    var dayOn: Binding<Bool> {
        Binding(get: { m.t.due != nil }, set: { on in
            if on { m.t.due = m.t.due ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()); m.t.hasTime = false } else { m.t.due = nil; m.t.repeatRule = .none }
            DispatchQueue.main.async(execute: resize)
        })
    }
    var locOn: Binding<Bool> { Binding(get: { m.t.locationOn }, set: { m.t.locationOn = $0; DispatchQueue.main.async(execute: resize) }) }
    func label(_ s: String) -> some View {
        Text(s).font(.hv(11, .bold)).foregroundColor(Color(150)).shadow(color: .white, radius: 0, y: 1).frame(width: 91, alignment: .trailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $m.t.title).accessibilityLabel(L("Title", "Titel")).textFieldStyle(.plain).font(.hv(16, .bold)).foregroundColor(Color(35))
                .padding(.horizontal, 16).padding(.top, 8).frame(height: 44)
            Rectangle().fill(Color(194)).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 9) {
                    label(L("remind me", "erinnern"))
                    VStack(alignment: .leading, spacing: 11) {
                        MiniCheck(on: dayOn, title: L("On a Day", "An einem Tag"))
                        if m.t.due != nil { dayFields }
                    }
                }
                if m.t.due != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        label(L("repeat", "wiederholen"))
                        Popup(value: $m.t.repeatRule, options: Repeat.allCases, label: { $0.label }).accessibilityLabel(L("Repeat", "Wiederholen"))
                    }
                    if m.t.repeatRule != .none {
                        HStack(alignment: .top, spacing: 9) {
                            label(L("end repeat", "Ende"))
                            VStack(alignment: .leading, spacing: 6) {
                                Popup(value: Binding(get: { m.t.repeatEnd != nil }, set: { m.t.repeatEnd = $0 ? (m.t.due ?? Date()).addingTimeInterval(86400 * 30) : nil; DispatchQueue.main.async(execute: resize) }),
                                      options: [false, true], label: { $0 ? L("On Date", "Am Datum") : L("Never", "Nie") })
                                if m.t.repeatEnd != nil {
                                    DatePicker("", selection: Binding(get: { m.t.repeatEnd ?? Date() }, set: { m.t.repeatEnd = $0 }), displayedComponents: [.date])
                                        .datePickerStyle(.field).labelsHidden().fixedSize()
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 9) {
                    Color.clear.frame(width: 91, height: 1)
                    VStack(alignment: .leading, spacing: 11) {
                        MiniCheck(on: locOn, title: L("At a Location", "An einem Ort"))
                        if m.t.locationOn { locationFields }
                    }
                }
            }.padding(.top, 8).padding(.bottom, 5)
            Rectangle().fill(Color(194)).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                label(L("priority", "Priorität"))
                Popup(value: $m.t.priority, options: Priority.allCases, label: { $0.label }).accessibilityLabel(L("Priority", "Priorität"))
            }.padding(.top, 11)
            HStack(alignment: .top, spacing: 9) {
                label(L("note", "Notiz"))
                // Anzeige als Text (nur dort greift lineSpacing: Referenz 13 px Zeilenabstand); Klick wechselt in den Editor
                ZStack(alignment: .topLeading) {
                    if editingNote {
                        TextEditor(text: $m.t.note).font(.hv(11)).foregroundColor(Color(40)).focused($noteFocus)
                            .scrollContentBackground(.hidden).scrollDisabled(true).padding(.horizontal, -5).padding(.vertical, -8).accessibilityLabel(L("Note", "Notiz"))
                            .onAppear { noteFocus = true }
                            .onChange(of: noteFocus) { _, f in if !f { editingNote = false; DispatchQueue.main.async(execute: resize) } }
                    } else {
                        Text(m.t.note.isEmpty ? L("None", "Keine") : m.t.note).font(.hv(11)).lineSpacing(2.4)
                            .foregroundColor(m.t.note.isEmpty ? Color(150) : Color(40)).accessibilityLabel(L("Note", "Notiz")).accessibilityValue(m.t.note).accessibilityAddTraits(.isButton).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 13, alignment: .topLeading).contentShape(Rectangle())
                            .onTapGesture { editingNote = true; DispatchQueue.main.async(execute: resize) }
                    }
                }.frame(width: 138, alignment: .leading)
            }.padding(.top, 19)
            HStack {
                Spacer()
                Button(action: done) {
                    Text(L("Done", "Fertig")).font(.hv(11)).foregroundColor(Color(40)).frame(width: 42, height: 19)
                        .background(RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(255), Color(236)], startPoint: .top, endPoint: .bottom)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(140), lineWidth: 1))
                }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }.padding(.top, 17).padding(.trailing, 12).padding(.bottom, 8)
        }
        .frame(width: 255).padding(.leading, 9)
        .background(
            ZStack {
                PopoverShape(arrowY: arrowY).fill(LinearGradient(stops: [.init(color: Color(254), location: 0), .init(color: Color(247.5), location: 0.4), .init(color: Color(243), location: 0.58), .init(color: Color(239), location: 0.82), .init(color: Color(236), location: 1)], startPoint: .top, endPoint: .bottom))
                PopoverShape(arrowY: arrowY).stroke(Color.black.opacity(0.22), lineWidth: 0.5)
            }
        )
        .environment(\.colorScheme, .light)
        .onExitCommand { done() }                                  // Esc schließt wie „Fertig“ (speichert)
        .onChange(of: m.t.locationOn) { _, _ in resize() }
    }

    var dayFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker("", selection: Binding(get: { m.t.due ?? Date() }, set: { m.t.due = $0 }), displayedComponents: [.date])
                .datePickerStyle(.field).labelsHidden().fixedSize()
            MiniCheck(on: Binding(get: { m.t.hasTime }, set: { m.t.hasTime = $0; DispatchQueue.main.async(execute: resize) }), title: L("Time", "Uhrzeit"))
            if m.t.hasTime {
                DatePicker("", selection: Binding(get: { m.t.due ?? Date() }, set: { m.t.due = $0 }), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.field).labelsHidden().fixedSize()
            }
        }.padding(.bottom, 2)
    }

    var locationFields: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                TextField("", text: $m.t.address).textFieldStyle(.plain).font(.hv(11)).padding(.horizontal, 4).frame(width: 118, height: 18)
                    .background(Color.white).overlay(Rectangle().stroke(Color(170), lineWidth: 1))
                ZStack { Rectangle().fill(LinearGradient(colors: [Color(252), Color(230)], startPoint: .top, endPoint: .bottom)); Rectangle().stroke(Color(170), lineWidth: 1)
                    Image(systemName: "chevron.down").font(.system(size: 6, weight: .black)).foregroundColor(Color(60)) }.frame(width: 14, height: 18)
            }
            Text(L("Enter a contact or an address", "Kontakt oder Adresse eingeben")).font(.hv(9)).foregroundColor(Color(150))
            HStack(spacing: 8) {
                MiniRadio(selected: !m.t.arriving, title: L("Leaving", "Verlassen")) { m.t.arriving = false }
                MiniRadio(selected: m.t.arriving, title: L("Arriving", "Ankommen")) { m.t.arriving = true }
            }.padding(.top, 3)
        }
    }
}
