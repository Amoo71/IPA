import SwiftUI

/// Full profile for a contact or group: large picture, name, about/description,
/// phone number, and (for groups) member count. Opened by tapping the chat
/// header in `ChatDetailView`.
struct ProfileView: View {
    let chat: Chat
    @EnvironmentObject var wa: WhatsAppBridge
    @Environment(\.dismiss) private var dismiss

    private var p: Profile? { wa.openProfile }
    private var isGroup: Bool { chat.isGroup || (p?.isGroup ?? false) }
    private var title: String { p?.name ?? chat.display }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Theme.line)
                ScrollView {
                    VStack(spacing: 18) {
                        Avatar(url: p?.pictureURL ?? wa.avatars[chat.jid],
                               name: title, isGroup: isGroup, size: 120)
                            .padding(.top, 24)

                        VStack(spacing: 4) {
                            Text(title)
                                .font(Theme.mono(20, .bold))
                                .foregroundColor(Theme.text)
                                .multilineTextAlignment(.center)
                            Text(isGroup ? "# group" : "contact")
                                .font(Theme.mono(11))
                                .foregroundColor(Theme.accent)
                        }

                        VStack(spacing: 0) {
                            if isGroup {
                                if let about = p?.about, !about.isEmpty {
                                    field("description", about)
                                }
                                if let n = p?.participants, n > 0 {
                                    field("members", "\(n)")
                                }
                            } else {
                                if let about = p?.about, !about.isEmpty {
                                    field("about", about)
                                }
                                if let phone = p?.phone, !phone.isEmpty {
                                    field("phone", phone)
                                } else {
                                    field("phone", "+" + (chat.jid.split(separator: "@").first.map(String.init) ?? ""))
                                }
                            }
                            field("jid", chat.jid)
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 30)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Text("$ profile")
                .font(Theme.mono(16, .bold))
                .foregroundColor(Theme.accent)
            Spacer()
            Button { dismiss() } label: {
                Text("[ done ]").font(Theme.mono(12)).foregroundColor(Theme.text)
            }
        }
        .padding(16)
    }

    private func field(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            Text(value).font(Theme.mono(13)).foregroundColor(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        .padding(.bottom, 8)
    }
}
