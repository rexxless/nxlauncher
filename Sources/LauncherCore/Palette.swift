import CoreGraphics
import Foundation
import ImageIO

/// An RGB color, components 0...1.
public struct RGB: Equatable, Hashable, Sendable, Codable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public var hsb: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6; if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    public init(h: Double, s: Double, v: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
    }

    func distance(_ o: RGB) -> Double { (r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b) }
}

/// The colors the window takes from a game's icon: `base` fills the window, `deep` the sidebar and lower half, `accent` the charts and highlights.
public struct Palette: Equatable, Hashable, Sendable, Codable {
    public var base: RGB
    public var deep: RGB
    public var accent: RGB
    public var swatches: [RGB]   // the clusters, most vivid first: the mesh gradient's points

    public static let fallback = Palette(base: RGB(0.80, 0.12, 0.16), deep: RGB(0.45, 0.05, 0.09), accent: RGB(1.0, 0.75, 0.25),
                                         swatches: [RGB(0.80, 0.12, 0.16), RGB(0.45, 0.05, 0.09), RGB(1.0, 0.75, 0.25), RGB(0.30, 0.04, 0.12)])

    /// Text and the Play button go dark on a light base.
    public var isLight: Bool { base.luminance > 0.6 }

    public static func from(imageAt url: URL) -> Palette? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                       kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary)
        else { return nil }
        return from(pixels: pixels(of: image, side: 32))
    }

    static func pixels(of image: CGImage, side: Int) -> [RGB] {
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let ok = buf.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return [] }
        return stride(from: 0, to: buf.count, by: 4).compactMap { i in
            buf[i + 3] < 128 ? nil : RGB(Double(buf[i]) / 255, Double(buf[i + 1]) / 255, Double(buf[i + 2]) / 255)
        }
    }

    /// k-means (k = 4, seeded deterministically) over the pixels; the base is the most vivid large cluster, kept dark enough for white text.
    public static func from(pixels: [RGB]) -> Palette {
        guard pixels.count >= 4 else { return .fallback }
        var centers = (0..<4).map { pixels[$0 * pixels.count / 4] }
        var counts = [Int](repeating: 0, count: 4)
        for _ in 0..<10 {
            var sums = [RGB](repeating: RGB(0, 0, 0), count: 4); counts = [0, 0, 0, 0]
            for p in pixels {
                let j = centers.indices.min { centers[$0].distance(p) < centers[$1].distance(p) }!
                sums[j].r += p.r; sums[j].g += p.g; sums[j].b += p.b; counts[j] += 1
            }
            for j in 0..<4 where counts[j] > 0 {
                let n = Double(counts[j]); centers[j] = RGB(sums[j].r / n, sums[j].g / n, sums[j].b / n)
            }
        }
        // Score: saturation and brightness, weighted by the cluster's share; a grey icon still yields its own (muted) tone.
        let total = Double(pixels.count)
        let ranked = centers.indices.filter { counts[$0] > 0 }.sorted { a, b in
            func score(_ j: Int) -> Double { let c = centers[j].hsb; return (c.s * 0.7 + c.v * 0.3) * sqrt(Double(counts[j]) / total) }
            return score(a) > score(b)
        }.map { centers[$0] }
        guard let top = ranked.first else { return .fallback }

        let h = top.hsb
        let base = RGB(h: h.h, s: min(1, max(h.s, 0.35) * 1.05), v: min(max(h.v, 0.45), 0.78))
        let deep = RGB(h: h.h, s: min(1, max(h.s, 0.35) * 1.1), v: min(max(h.v, 0.45), 0.78) * 0.55)
        let other = ranked.dropFirst().max { $0.hsb.s < $1.hsb.s } ?? top
        let o = other.hsb
        let accent = abs(o.h - h.h) > 0.08 && o.s > 0.25 ? RGB(h: o.h, s: max(o.s, 0.55), v: max(o.v, 0.85)) : RGB(h: (h.h + 0.08).truncatingRemainder(dividingBy: 1), s: 0.6, v: 1)
        return Palette(base: base, deep: deep, accent: accent, swatches: Array(ranked.prefix(4)))
    }
}
