import SwiftUI

struct SettingsView: View {
    let name: String
    let jid: String

    @EnvironmentObject var wa: WhatsAppBridge
    @Environment(\.dismiss) private var dismiss
    @State private var showLogs = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("$ settings")
                        .font(Theme.mono(16, .bold))
                        .foregroundColor(Theme.accent)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("[ done ]").font(Theme.mono(12)).foregroundColor(Theme.text)
                    }
                }
                .padding(16)
                Divider().overlay(Theme.line)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        field("user", name)
                        field("jid", jid)
                        field("session", "stored locally · e2e")

                        rowButton("view connection log") { showLogs.toggle() }
                        if showLogs {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(wa.logs.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(Theme.mono(10))
                                        .foregroundColor(Theme.textFaint)
                                        .textSelection(.enabled)
                                }
                                if wa.logs.isEmpty {
                                    Text("// no log output").font(Theme.mono(10)).foregroundColor(Theme.textFaint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.surface)
                        }

                        Divider().overlay(Theme.line).padding(.vertical, 8)

                        Button { wa.logout() } label: {
                            HStack {
                                Text("⏻ unlink device / logout")
                                    .font(Theme.mono(13, .semibold))
                                    .foregroundColor(Theme.warn)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
                Text("TermiChat · CLI client for whatsapp web")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            Text(value).font(Theme.mono(13)).foregroundColor(Theme.text).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func rowButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("› \(title)").font(Theme.mono(13)).foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
