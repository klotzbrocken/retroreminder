import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Eigenes App-Symbol: Der Nutzer wählt ein PNG mit genau 256 × 256 Pixeln; es wird nach Application Support kopiert
/// und beim Start (und sofort bei Änderung) als Dock-Symbol gesetzt. Das Symbol der App-Datei im Finder bleibt unverändert
/// (es ist Teil der Signatur).
enum AppIcon {
    static let size = 256
    static var override: URL?                       // nur für Tests
    static var customURL: URL {
        if let o = override { return o }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroReminder/AppIcon.png")
    }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    struct Failure: LocalizedError { let errorDescription: String? }

    /// Prüft Datei: echtes PNG, exakt 256 × 256 Pixel.
    static func validate(_ url: URL) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src), (type as String) == UTType.png.identifier else {
            throw Failure(errorDescription: L("This file is not a PNG image.", "Diese Datei ist kein PNG-Bild."))
        }
        guard let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else {
            throw Failure(errorDescription: L("The image could not be read.", "Das Bild konnte nicht gelesen werden."))
        }
        guard w == size, h == size else {
            throw Failure(errorDescription: L("The PNG must be exactly \(size) × \(size) pixels (this one is \(w) × \(h)).", "Das PNG muss genau \(size) × \(size) Pixel groß sein (dieses hat \(w) × \(h))."))
        }
    }
    static func set(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try validate(url)
        let data = try Data(contentsOf: url)
        try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: customURL, options: .atomic)
        apply()
    }
    static func reset() { try? FileManager.default.removeItem(at: customURL); apply() }
    /// Dock-Symbol setzen; nil stellt das Symbol aus dem App-Paket wieder her.
    static func apply() {
        if hasCustom, (try? validate(customURL)) != nil, let img = NSImage(contentsOf: customURL) { NSApp.applicationIconImage = img }
        else { NSApp.applicationIconImage = nil }
    }
}

final class IconPrefs: ObservableObject {
    @Published var image: NSImage = NSApp.applicationIconImage
    @Published var custom = AppIcon.hasCustom
    @Published var error: String?
    func refresh() { image = NSApp.applicationIconImage; custom = AppIcon.hasCustom }
    func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png]; p.allowsMultipleSelection = false; p.canChooseDirectories = false
        p.message = L("Choose a PNG with exactly 256 × 256 pixels.", "Wähle ein PNG mit genau 256 × 256 Pixeln.")
        if p.runModal() == .OK, let u = p.url { use(u) }
    }
    func use(_ u: URL) {
        do { try AppIcon.set(from: u); error = nil } catch { self.error = error.localizedDescription }
        refresh()
    }
    func reset() { AppIcon.reset(); error = nil; refresh() }
}

struct PreferencesView: View {
    @StateObject private var m = IconPrefs()
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("App Icon", "App-Symbol")).font(.headline)
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: m.image).resizable().interpolation(.high).frame(width: 128, height: 128)
                    .padding(6).background(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .onDrop(of: [.fileURL], isTargeted: $targeted) { items in
                        guard let it = items.first else { return false }
                        _ = it.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { m.use(url) } } }
                        return true
                    }
                    .accessibilityLabel(L("Current app icon. Drop a PNG here to replace it.", "Aktuelles App-Symbol. PNG hierher ziehen, um es zu ersetzen."))
                VStack(alignment: .leading, spacing: 10) {
                    Button(L("Choose PNG …", "PNG wählen …")) { m.choose() }
                    Button(L("Reset to Default", "Standard wiederherstellen")) { m.reset() }.disabled(!m.custom)
                    Text(m.custom ? L("Custom icon in use.", "Eigenes Symbol aktiv.") : L("Default icon in use.", "Standardsymbol aktiv.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L("PNG, exactly 256 × 256 pixels, ideally with a transparent background. You can also drag a file onto the preview. The icon applies to the Dock while the app runs; the app file's icon in Finder stays as is.",
                   "PNG, genau 256 × 256 Pixel, am besten mit transparentem Hintergrund. Du kannst die Datei auch auf die Vorschau ziehen. Das Symbol gilt für das Dock, solange die App läuft; das Symbol der App-Datei im Finder bleibt unverändert."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let e = m.error { Text(e).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityLabel(L("Error: ", "Fehler: ") + e) }
        }
        .padding(20).frame(width: 440, alignment: .leading)
    }
}
