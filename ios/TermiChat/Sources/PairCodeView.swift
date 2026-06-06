import SwiftUI

/// Shows the phone pairing code that the user types into WhatsApp on their
/// primary phone (Linked Devices → Link a Device → "Link with phone number").
struct PairCodeView: View {
    let code: String
    @EnvironmentObject var wa: WhatsAppBridge
    @State private var blink = false

    /// WhatsApp shows the 8-char code as "XXXX-XXXX".
    private var formatted: String {
        let c = code.uppercased()
        guard c.count == 8 else { return c }
        let i = c.index(c.startIndex, offsetBy: 4)
        return "\(c[..<i])-\(c[i...])"
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 4) {
                Text("$ enter code in whatsapp")
                    .font(Theme.mono(16, .bold))
                    .foregroundColor(Theme.accent)
                Text("on your primary phone")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textDim)
            }

            Text(formatted)
                .font(Theme.mono(34, .bold))
                .foregroundColor(Theme.text)
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
                .textSelection(.enabled)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                step("1", "Open WhatsApp on your phone")
                step("2", "Settings → Linked Devices")
                step("3", "Link a Device")
                step("4", "Tap “Link with phone number instead”")
                step("5", "Enter the code above")
            }
            .frame(maxWidth: 320, alignment: .leading)

            HStack(spacing: 6) {
                Text("waiting for confirmation")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textFaint)
                Text("_")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.accent)
                    .opacity(blink ? 1 : 0)
            }

            // Live connection log — shows the real reason if linking fails.
            if !wa.logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(wa.logs.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { blink = true }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(n)]").foregroundColor(Theme.accent)
            Text(text).foregroundColor(Theme.textDim)
        }
        .font(Theme.mono(12))
    }
}
