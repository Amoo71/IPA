import SwiftUI

/// Terminal-inspired palette and typography. Everything is monospaced to get
/// that "modern CLI" feel without shipping a custom font file.
///
/// Colors are `static var` so the user can recolor the UI at runtime (see
/// `ThemeManager`). `accentDim`/`badge` derive from `accent` so a single
/// accent change repaints the whole app.
enum Theme {
    static var bg          = Color(red: 0.04, green: 0.05, blue: 0.06)
    static var surface     = Color(red: 0.09, green: 0.10, blue: 0.12)
    static var surfaceHi   = Color(red: 0.13, green: 0.15, blue: 0.17)
    static var line        = Color(red: 0.18, green: 0.20, blue: 0.23)
    static var accent      = Color(red: 0.18, green: 0.92, blue: 0.55)   // terminal green
    static var text        = Color(red: 0.90, green: 0.92, blue: 0.94)
    static var textDim     = Color(red: 0.55, green: 0.59, blue: 0.64)
    static var textFaint   = Color(red: 0.38, green: 0.42, blue: 0.47)
    static var warn        = Color(red: 1.00, green: 0.75, blue: 0.25)

    static var accentDim: Color { accent.opacity(0.55) }
    static var badge: Color { accent }

    // Factory defaults, used by "reset theme".
    static let defaultAccent = Color(red: 0.18, green: 0.92, blue: 0.55)
    static let defaultBg     = Color(red: 0.04, green: 0.05, blue: 0.06)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    func monoBody() -> some View { font(Theme.mono(14)) }
}

/// Persists the user's chosen colors and forces a full UI repaint when they
/// change (RootView keys its content on `version`).
final class ThemeManager: ObservableObject {
    @Published var version = 0

    private let kAccent = "theme.accent.hex"
    private let kBg     = "theme.bg.hex"

    /// A few ready-made accent colors for one-tap theming.
    let presets: [(name: String, color: Color)] = [
        ("green",  Color(red: 0.18, green: 0.92, blue: 0.55)),
        ("amber",  Color(red: 1.00, green: 0.75, blue: 0.25)),
        ("cyan",   Color(red: 0.20, green: 0.85, blue: 0.95)),
        ("magenta",Color(red: 0.95, green: 0.40, blue: 0.85)),
        ("red",    Color(red: 0.95, green: 0.35, blue: 0.40)),
        ("blue",   Color(red: 0.40, green: 0.62, blue: 1.00)),
        ("white",  Color(red: 0.90, green: 0.92, blue: 0.94)),
    ]

    init() {
        if let h = UserDefaults.standard.string(forKey: kAccent), let c = Color(hex: h) {
            Theme.accent = c
        }
        if let h = UserDefaults.standard.string(forKey: kBg), let c = Color(hex: h) {
            Theme.bg = c
        }
    }

    var accent: Color {
        get { Theme.accent }
        set {
            Theme.accent = newValue
            UserDefaults.standard.set(newValue.hexString, forKey: kAccent)
            version += 1
        }
    }

    var background: Color {
        get { Theme.bg }
        set {
            Theme.bg = newValue
            UserDefaults.standard.set(newValue.hexString, forKey: kBg)
            version += 1
        }
    }

    func reset() {
        Theme.accent = Theme.defaultAccent
        Theme.bg = Theme.defaultBg
        UserDefaults.standard.removeObject(forKey: kAccent)
        UserDefaults.standard.removeObject(forKey: kBg)
        version += 1
    }
}

extension Color {
    /// "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue:  Double(v & 0xFF) / 255
        )
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}
