import SwiftUI

/// Shows the phone pairing code that the user types into WhatsApp on their
/// primary phone (Linked Devices → Link a Device → "Link with phone number").
struct PairCodeView: View {
    let code: String
    @EnvironmentObject var wa: WhatsAppBridge
    @State private var blink = false
    @State private var requestingNew = false

    /// WhatsApp shows the 8-char code as "XXXX-XXXX".
    private var formatted: String {
        let c = code.uppercased()
        guard c.count == 8 else { return c }
        let i = c.index(c.startIndex, offsetBy: 4)
        return "\(c[..<i])-\(c[i...])"
    }

    private var logText: String {
        wa.logs.isEmpty ? "// no logs yet" : wa.logs.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 4) {
                Text("$ enter code in whatsapp")
                    .font(Theme.mono(16, .bold))
                    .foregroundColor(Theme.accent)
                Text("on your primary phone")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textDim)
            }

            // Code box
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

            // Instructions
            VStack(alignment: .leading, spacing: 6) {
                step("1", "Open WhatsApp on your phone")
                step("2", "Settings → Linked Devices")
                step("3", "Link a Device")
                step("4", "Tap \"Link with phone number instead\"")
                step("5", "Enter the code above")
            }
            .frame(maxWidth: 320, alignment: .leading)

            // Waiting indicator
            HStack(spacing: 6) {
                Text("waiting for confirmation")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textFaint)
                Text("_")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.accent)
                    .opacity(blink ? 1 : 0)
            }

            // Action buttons
            VStack(spacing: 10) {
                // Request a new code (same number, fresh code)
                Button {
                    requestingNew = true
                    wa.requestNewCode()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { requestingNew = false }
                } label: {
                    Text(requestingNew ? "[ requesting… ]" : "[ new code ]")
                        .font(Theme.mono(13, .bold))
                        .foregroundColor(requestingNew ? Theme.textFaint : Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(requestingNew ? Theme.surfaceHi : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(requestingNew)

                HStack(spacing: 10) {
                    // Fix number — restart bridge so user can enter a different number
                    Button { wa.resetToChoosing() } label: {
                        Text("[ fix number ]")
                            .font(Theme.mono(13))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    }

                    // Share / copy the full connection log for debugging
                    ShareLink(item: logText) {
                        Text("[ share logs ]")
                            .font(Theme.mono(13))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 24)

            // Live connection log — shows real reason if linking fails
            if !wa.logs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(wa.logs.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            } else {
                Text("// connecting — logs will appear here")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textFaint)
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
