import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A single conversation: profile header, message history, and a CLI-style
/// input line. Reads live state from `WhatsAppBridge.openMessages/openProfile`.
struct ChatDetailView: View {
    let chat: Chat
    @EnvironmentObject var wa: WhatsAppBridge
    @EnvironmentObject var chatTheme: ChatThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var showProfile = false
    @State private var showThemeEditor = false
    @State private var notice: String?

    // Attachment pickers.
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showDocImporter = false

    private var accent: Color { chatTheme.accent(for: chat.jid) }
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
        ZStack {
            ChatBackgroundView(jid: chat.jid).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.line)
                messageList
                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { wa.openChat(chat.jid) }
        .onDisappear { wa.closeChat() }
        .sheet(isPresented: $showProfile) {
            ProfileView(chat: chat).environmentObject(wa)
        }
        .sheet(isPresented: $showThemeEditor) {
            ChatThemeEditor(jid: chat.jid, title: title, initial: chatTheme.rawStyle(for: chat.jid))
                .environmentObject(chatTheme)
        }
        .photosPicker(isPresented: $showImagePicker, selection: $photoItem, matching: .images)
        .photosPicker(isPresented: $showVideoPicker, selection: $videoItem, matching: .videos)
        .onChange(of: photoItem) { item in send(item, kind: "image") }
        .onChange(of: videoItem) { item in send(item, kind: "video") }
        .fileImporter(isPresented: $showDocImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handleDocument(result)
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
            }
            // Tap the avatar/name to open the full profile.
            Button { showProfile = true } label: {
                HStack(spacing: 12) {
                    Avatar(url: wa.openProfile?.pictureURL ?? wa.avatars[chat.jid],
                           name: title, isGroup: chat.isGroup, size: 38)
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
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { showProfile = true } label: { Label("Profile", systemImage: "person.crop.circle") }
                Button { showThemeEditor = true } label: { Label("Customize theme", systemImage: "paintbrush") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundColor(accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.92))
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
                        Bubble(msg: msg, isGroup: chat.isGroup, accent: accent)
                            .id(msg.rowKey)
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

            if let notice {
                Text(notice)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            HStack(spacing: 8) {
                // Attachments: photo / video / document.
                Menu {
                    Button { showImagePicker = true } label: { Label("Photo", systemImage: "photo") }
                    Button { showVideoPicker = true } label: { Label("Video", systemImage: "video") }
                    Button { showDocImporter = true } label: { Label("Document", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accent)
                }

                HStack(spacing: 8) {
                    Text(">")
                        .font(Theme.mono(14, .bold))
                        .foregroundColor(accent)
                    TextField("", text: $draft,
                              prompt: Text("message").foregroundColor(Theme.textFaint))
                        .font(Theme.mono(14))
                        .foregroundColor(Theme.text)
                        .submitLabel(.send)
                        .onSubmit(sendDraft)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.bg.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? accent : Theme.textFaint)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Theme.surface.opacity(0.92))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        wa.send(to: chat.jid, text: draft)
        draft = ""
    }

    // MARK: media sending

    private func send(_ item: PhotosPickerItem?, kind: String) {
        guard let item else { return }
        note("sending \(kind)…")
        item.loadTransferable(type: Data.self) { result in
            guard case .success(let data?) = result else { return }
            let ext = kind == "video" ? ".mp4" : ".jpg"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ext)
            do {
                try data.write(to: url)
                DispatchQueue.main.async {
                    wa.sendMedia(to: chat.jid, path: url.path, kind: kind)
                }
            } catch {}
        }
    }

    private func handleDocument(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let u = urls.first else { return }
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u) else { return }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(u.lastPathComponent)
        do {
            try data.write(to: dst)
            wa.sendMedia(to: chat.jid, path: dst.path, kind: "document")
            note("sending document…")
        } catch {}
    }

    /// Show a transient one-line notice above the input bar.
    private func note(_ text: String) {
        withAnimation { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

// MARK: - Bubble

private struct Bubble: View {
    let msg: Message
    let isGroup: Bool
    let accent: Color
    @EnvironmentObject var wa: WhatsAppBridge

    private var path: String? { wa.mediaPaths[msg.id].flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        HStack {
            if msg.fromMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if isGroup && !msg.fromMe && !msg.senderName.isEmpty {
                    Text(msg.senderName)
                        .font(Theme.mono(10, .bold))
                        .foregroundColor(accent)
                }

                if msg.isMedia {
                    MediaContent(msg: msg, path: path, accent: accent)
                    if !msg.caption.isEmpty {
                        Text(msg.caption)
                            .font(Theme.mono(13))
                            .foregroundColor(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(msg.text.isEmpty ? "—" : msg.text)
                        .font(Theme.mono(13))
                        .foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(msg.timeLabel)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(msg.fromMe ? accent.opacity(0.16) : Theme.surfaceHi)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(msg.fromMe ? accent.opacity(0.35) : Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if !msg.fromMe { Spacer(minLength: 40) }
        }
        .onAppear {
            if msg.hasMedia && path == nil { wa.downloadMedia(msg.id) }
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
