import SwiftUI

/// First-run screen: pick how to link. Phone-number pairing is the default
/// because TermiChat usually runs on the *same* phone as WhatsApp, where you
/// can't scan your own QR code.
struct LinkMethodView: View {
    @EnvironmentObject var wa: WhatsAppBridge
    @State private var phone: String = ""
    @FocusState private var focused: Bool

    private var digits: String { phone.filter { $0.isNumber } }
    private var canPair: Bool { digits.count >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("$ link device")
                    .font(Theme.mono(18, .bold))
                    .foregroundColor(Theme.accent)
                Text("connect your whatsapp account")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textDim)
            }

            // --- phone number (recommended) ---
            VStack(alignment: .leading, spacing: 8) {
                Text("// link with phone number")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textFaint)

                HStack(spacing: 8) {
                    Text("+")
                        .font(Theme.mono(15, .bold))
                        .foregroundColor(Theme.accent)
                    TextField("", text: $phone,
                              prompt: Text("country code + number").foregroundColor(Theme.textFaint))
                        .font(Theme.mono(15))
                        .foregroundColor(Theme.text)
                        .keyboardType(.numberPad)
                        .focused($focused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))

                Text("e.g. 49 170 1234567  (no spaces, no +)")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textFaint)

                Button {
                    focused = false
                    wa.pair(method: "phone", phone: digits)
                } label: {
                    Text("[ get pairing code ]")
                        .font(Theme.mono(14, .bold))
                        .foregroundColor(canPair ? Theme.bg : Theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canPair ? Theme.accent : Theme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canPair)
            }

            // --- divider ---
            HStack(spacing: 8) {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text("or").font(Theme.mono(11)).foregroundColor(Theme.textFaint)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.vertical, 4)

            // --- QR (for linking from another device) ---
            Button {
                focused = false
                wa.pair(method: "qr")
            } label: {
                HStack {
                    Text("[ scan QR code instead ]")
                        .font(Theme.mono(13))
                        .foregroundColor(Theme.text)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            }
            Text("scan only works from a *different* device")
                .font(Theme.mono(10))
                .foregroundColor(Theme.textFaint)

            Spacer()
        }
        .padding(20)
    }
}
