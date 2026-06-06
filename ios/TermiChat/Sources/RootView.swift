import SwiftUI

struct RootView: View {
    @StateObject private var wa = WhatsAppBridge()
    @StateObject private var theme = ThemeManager()
    @StateObject private var chatTheme = ChatThemeManager()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch wa.state {
            case .offline, .connecting:
                BootView(state: wa.state)
            case .choosing:
                LinkMethodView()
            case .linking(let qr):
                QRLinkView(code: qr)
            case .pairingCode(let code):
                PairCodeView(code: code)
            case .online(let name, let jid):
                ChatListView(name: name, jid: jid)
            }
        }
        .environmentObject(wa)
        .environmentObject(theme)
        .environmentObject(chatTheme)
        .preferredColorScheme(.dark)
        .onAppear { wa.start() }
        // Recoloring bumps `version`, giving this subtree a new identity so
        // every view re-reads Theme.* with the new palette.
        .id(theme.version)
    }
}

/// Boot / dialing splash with a terminal banner.
private struct BootView: View {
    let state: ConnState
    @State private var blink = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            // Inner width is exactly 24 chars on every line so the right
            // border stays aligned in the monospaced font.
            Text("""
            ┌────────────────────────┐
            │   T E R M I C H A T    │
            └────────────────────────┘
            """)
            .font(Theme.mono(13))
            .foregroundColor(Theme.accent)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 6) {
                Text(statusText)
                    .font(Theme.mono(13))
                    .foregroundColor(Theme.textDim)
                Text("_")
                    .font(Theme.mono(13))
                    .foregroundColor(Theme.accent)
                    .opacity(blink ? 1 : 0)
            }
            Spacer()
            Text("end-to-end via whatsapp multi-device")
                .font(Theme.mono(10))
                .foregroundColor(Theme.textFaint)
                .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { blink = true }
        }
    }

    private var statusText: String {
        switch state {
        case .connecting: return "$ connecting to whatsapp"
        default:          return "$ booting"
        }
    }
}
