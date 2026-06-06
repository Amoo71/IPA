import SwiftUI

/// Terminal-inspired palette and typography. Everything is monospaced to get
/// that "modern CLI" feel without shipping a custom font file.
enum Theme {
    static let bg          = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let surface     = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let surfaceHi   = Color(red: 0.13, green: 0.15, blue: 0.17)
    static let line        = Color(red: 0.18, green: 0.20, blue: 0.23)
    static let accent      = Color(red: 0.18, green: 0.92, blue: 0.55)   // terminal green
    static let accentDim   = Color(red: 0.18, green: 0.92, blue: 0.55).opacity(0.55)
    static let text        = Color(red: 0.90, green: 0.92, blue: 0.94)
    static let textDim     = Color(red: 0.55, green: 0.59, blue: 0.64)
    static let textFaint   = Color(red: 0.38, green: 0.42, blue: 0.47)
    static let warn        = Color(red: 1.00, green: 0.75, blue: 0.25)
    static let badge       = Color(red: 0.18, green: 0.92, blue: 0.55)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    func monoBody() -> some View { font(Theme.mono(14)) }
}
