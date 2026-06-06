import SwiftUI

/// A single conversation: profile header, message history, and a CLI-style
/// input line. Reads live state from `WhatsAppBridge.openMessages/openProfile`.
struct ChatDetailView: View {
    let chat: Chat
    @EnvironmentObject var wa: WhatsAppBridge
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private var title: String { wa.openProfile?.name ?? chat.display }

    private var subtitle: String {
        let p = wa.openProfile
        if chat.isGroup || (p?.isGroup ?? false) {
            if let n = p?.participants, n > 0 { return "\(n) members" }
            return "group"
        }
        if let about = p?.about, !about.isEmpty { return about }
        if let phone = p?.phone, !phone.isEmpty { return phone }
        return chat.jid.split(separator: "@").first.map(String.init) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            messageList
            inputBar
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { wa.openChat(chat.jid) }
        .onDisappear { wa.closeChat() }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            Avatar(url: wa.openProfile?.pictureURL, name: title, isGroup: chat.isGroup, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.mono(15, .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if wa.openMessages.isEmpty {
                        Text("// no messages yet")
                            .font(Theme.mono(12))
                            .foregroundColor(Theme.textFaint)
                            .padding(.top, 40)
                    }
                    ForEach(wa.openMessages, id: \.rowKey) { msg in
                        Bubble(msg: msg, isGroup: chat.isGroup).id(msg.rowKey)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: wa.openMessages.count) { _ in
                if let last = wa.openMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.rowKey, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: input

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.line)
            HStack(spacing: 8) {
                Text(">")
                    .font(Theme.mono(15, .bold))
                    .foregroundColor(Theme.accent)
                TextField("", text: $draft,
                          prompt: Text("message").foregroundColor(Theme.textFaint))
                    .font(Theme.mono(14))
                    .foregroundColor(Theme.text)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(canSend ? Theme.accent : Theme.textFaint)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.surface)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        wa.send(to: chat.jid, text: draft)
        draft = ""
    }
}

// MARK: - Bubble

private struct Bubble: View {
    let msg: Message
    let isGroup: Bool

    var body: some View {
        HStack {
            if msg.fromMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                if isGroup && !msg.fromMe && !msg.senderName.isEmpty {
                    Text(msg.senderName)
                        .font(Theme.mono(10, .bold))
                        .foregroundColor(Theme.accent)
                }
                Text(msg.text.isEmpty ? "—" : msg.text)
                    .font(Theme.mono(13))
                    .foregroundColor(Theme.text)
                Text(msg.timeLabel)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(msg.fromMe ? Theme.accent.opacity(0.16) : Theme.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(msg.fromMe ? Theme.accent.opacity(0.35) : Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if !msg.fromMe { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Avatar

struct Avatar: View {
    let url: String?
    let name: String
    let isGroup: Bool
    var size: CGFloat = 38

    private var initials: String {
        if isGroup { return "#" }
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4)
                .fill(Theme.surfaceHi)
            if let s = url, let u = URL(string: s), !s.isEmpty {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4))
    }

    private var placeholder: some View {
        Text(initials)
            .font(Theme.mono(size * 0.4, .bold))
            .foregroundColor(Theme.accent)
    }
}
