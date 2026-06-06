import SwiftUI

struct RootView: View {
    @StateObject private var wa = WhatsAppBridge()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch wa.state {
            case .offline, .connecting:
                BootView(state: wa.state)
            case .linking(let qr):
                QRLinkView(code: qr)
            case .online(let name, let jid):
                ChatListView(name: name, jid: jid)
            }
        }
        .environmentObject(wa)
        .preferredColorScheme(.dark)
        .onAppear { wa.start() }
    }
}

/// Boot / dialing splash with a terminal banner.
private struct BootView: View {
    let state: ConnState
    @State private var blink = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("""
            ┌────────────────────────┐
            │      T E R M I C H A T  │
            └────────────────────────┘
            """)
            .font(Theme.mono(13))
            .foregroundColor(Theme.accent)

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
