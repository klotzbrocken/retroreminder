import SwiftUI
import AppKit

// Prozedurale Texturen: nahtlos kachelbar, 512 px = 256 pt (scharf bei 1× und 2×).
enum Tex {
    private struct RNG {
        var s: UInt64
        mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 40) & 0xFFFF) / 65535 }
    }

    /// Weichgezeichnetes Rauschen mit Wraparound (Box-Blur, 2 Durchgänge ≈ Gauß), normiert auf -1…1.
    private static func noise(_ n: Int, blur r: Int, seed: UInt64) -> [Float] {
        var g = RNG(s: seed)
        var a = (0..<n * n).map { _ in g.next() - 0.5 }
        if r > 0 {
            for _ in 0..<2 {
                var b = a
                for y in 0..<n { for x in 0..<n { var t: Float = 0; for k in -r...r { t += a[y * n + (x + k + n) % n] }; b[y * n + x] = t / Float(2 * r + 1) } }
                for y in 0..<n { for x in 0..<n { var t: Float = 0; for k in -r...r { t += b[((y + k + n) % n) * n + x] }; a[y * n + x] = t / Float(2 * r + 1) } }
            }
        }
        let m = max(a.map { abs($0) }.max() ?? 1, 0.0001)
        return a.map { $0 / m }
    }

    private static func make(_ n: Int, scale: CGFloat, pixel: (Int) -> (Float, Float, Float)) -> Image {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<n * n {
            let (r, g, b) = pixel(i)
            px[i * 4] = UInt8(max(0, min(255, r))); px[i * 4 + 1] = UInt8(max(0, min(255, g))); px[i * 4 + 2] = UInt8(max(0, min(255, b)))
        }
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return Image(decorative: ctx.makeImage()!, scale: scale)
    }

    /// Gemessene Kacheln (Reference/make_textures.py); 512 px = 256 pt.
    private static func res(_ name: String) -> Image? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "png"), let ns = NSImage(contentsOf: u) else { return nil }
        ns.size = NSSize(width: 256, height: 256)
        return Image(nsImage: ns)
    }
    /// Genarbtes, dunkles Leder (Messung: Grundton ≈ 50, Streuung ±4).
    static let leather: Image = res("leather") ?? {
        let n = 512
        let fine = noise(n, blur: 1, seed: 7), mid = noise(n, blur: 3, seed: 11), pit = noise(n, blur: 2, seed: 23)
        return make(n, scale: 2) { i in
            var v: Float = 52 + fine[i] * 10 + mid[i] * 6
            if pit[i] < -0.5 { v -= 9 }
            if pit[i] > 0.6 { v += 3 }
            return (v, v, v)
        }
    }()

    /// Aquarellpapier (Messung: Grundton ≈ 241/241/236, Streuung ±4).
    static let paper: Image = res("paper") ?? {
        let n = 512
        let fine = noise(n, blur: 1, seed: 31), mid = noise(n, blur: 4, seed: 37)
        return make(n, scale: 2) { i in
            let v = fine[i] * 3 + mid[i] * 3
            return (241 + v, 241 + v, 236 + v * 0.9)
        }
    }()

    /// Dunklere Versenkung (Seitenleistenliste / Kalender).
    static let pit: Image = res("pit") ?? {
        let n = 256
        let fine = noise(n, blur: 1, seed: 41)
        return make(n, scale: 2) { i in let v = 47 + fine[i] * 2.5; return (v, v, v) }
    }()
}

extension Color {
    init(_ w: Double) { self.init(white: w / 255) }
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
    static let mlRed = Color(209, 16, 48)          // Überschrift, gemessen
    static let paperLine = Color(191)               // Tabellenlinien, gemessen
    static let rulePink = Color(255, 187, 200)      // Randlinie, gemessen
}

extension Font {
    static func hn(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "HelveticaNeue-Bold" : weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size)
    }
    static func hv(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom(weight == .bold ? "Helvetica-Bold" : "Helvetica", size: size) }
    static func lucida(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "LucidaGrande-Bold" : "LucidaGrande", size: size) }
}

/// Vertikaler Verlauf aus gemessenen Pixelzeilen (1 Wert je Pixelzeile, Grauwert 0–255).
func vprofile(_ v: [Double]) -> LinearGradient {
    LinearGradient(stops: v.enumerated().map { .init(color: Color($0.element), location: Double($0.offset) / Double(max(1, v.count - 1))) }, startPoint: .top, endPoint: .bottom)
}

struct Tiled: View {
    let image: Image
    var body: some View { image.resizable(resizingMode: .tile) }
}
