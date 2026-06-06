import SwiftUI

/// Device-linking screen. Mirrors WhatsApp's "Link a device" flow but in the
/// terminal aesthetic.
struct QRLinkView: View {
    let code: String

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 4) {
                Text("$ link device")
                    .font(Theme.mono(16, .bold))
                    .foregroundColor(Theme.accent)
                Text("scan from WhatsApp › Linked Devices")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textDim)
            }

            QR.image(from: code)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                step("1", "Open WhatsApp on your phone")
                step("2", "Settings → Linked Devices")
                step("3", "Link a Device → scan this code")
            }
            .frame(maxWidth: 300, alignment: .leading)

            Spacer()
            Text("waiting for scan…")
                .font(Theme.mono(11))
                .foregroundColor(Theme.textFaint)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(n)]").foregroundColor(Theme.accent)
            Text(text).foregroundColor(Theme.textDim)
        }
        .font(Theme.mono(12))
    }
}
