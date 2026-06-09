import SwiftUI
import DiskKit

extension Color {
    /// Builds an sRGB `Color` from an oklch value (L 0–1, C chroma, H degrees).
    /// The design specifies its palette in oklch; this converts it exactly
    /// (oklch → oklab → linear sRGB → gamma).
    init(oklch L: Double, _ c: Double, _ hDeg: Double) {
        let h = hDeg * .pi / 180
        let a = c * cos(h), b = c * sin(h)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func gamma(_ v: Double) -> Double {
            let cc = max(0, min(1, v))
            return cc <= 0.0031308 ? 12.92 * cc : 1.055 * pow(cc, 1 / 2.4) - 0.055
        }
        self.init(.sRGB, red: gamma(r), green: gamma(g), blue: gamma(bl))
    }
}

/// The Dial color system, ported verbatim from the design's CSS custom properties.
enum Palette {
    static func color(_ cat: FileCategory) -> Color {
        switch cat {
        case .deps:      return Color(oklch: 0.80, 0.115, 85)
        case .cache:     return Color(oklch: 0.79, 0.085, 205)
        case .build:     return Color(oklch: 0.66, 0.105, 252)
        case .container: return Color(oklch: 0.62, 0.10, 300)
        case .media:     return Color(oklch: 0.70, 0.115, 25)
        case .code:      return Color(oklch: 0.74, 0.095, 152)
        case .docs:      return Color(oklch: 0.74, 0.07, 262)
        case .app:       return Color(oklch: 0.70, 0.035, 250)
        case .trash:     return Color(oklch: 0.74, 0.045, 40)
        case .other:     return Color(oklch: 0.83, 0.012, 75)
        }
    }

    static let ink    = Color(oklch: 0.24, 0.006, 60)
    static let ink2   = Color(oklch: 0.46, 0.006, 60)
    static let ink3   = Color(oklch: 0.60, 0.005, 60)
    static let ink4   = Color(oklch: 0.73, 0.004, 60)
    static let line   = Color(oklch: 0.91, 0.004, 70)
    static let line2  = Color(oklch: 0.95, 0.004, 70)
    static let bg     = Color.white
    static let bg2    = Color(oklch: 0.985, 0.003, 75)
    static let bg3    = Color(oklch: 0.970, 0.004, 75)
    static let reclaim = Color(oklch: 0.66, 0.15, 58)
}
