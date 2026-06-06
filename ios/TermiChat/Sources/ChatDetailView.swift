import SwiftUI
import UIKit
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
    @State private var replyTo: Message?

    // Attachment pickers.
    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showDocImporter = false
    @State private var showAudioImporter = false
    @State private var showStickerPicker = false
    @StateObject private var recorder = VoiceRecorder()

    private var accent: Color { chatTheme.accent(for: chat.jid) }
    private var resolved: ResolvedChatStyle { chatTheme.resolved(for: chat.jid) }
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
            Theme.bg.ignoresSafeArea()
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
            handleDocument(result, kind: "document")
        }
        .fileImporter(isPresented: $showAudioImporter,
                      allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            handleDocument(result, kind: "audio")
        }
        .sheet(isPresented: $showStickerPicker) {
            StickerPickerView { path in
                wa.sendSticker(to: chat.jid, path: path)
                note("sending sticker…")
            }
            .environmentObject(wa)
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
                        Bubble(msg: msg, isGroup: chat.isGroup, style: resolved,
                               onReply: { replyTo = $0 })
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

            if let r = replyTo { replyPreview(r) }

            if let notice {
                Text(notice)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if recorder.isRecording {
                recordingBar
            } else {
                HStack(spacing: 8) {
                    // Attachments: photo / video / sticker / audio / document.
                    Menu {
                        Button { showImagePicker = true } label: { Label("Photo", systemImage: "photo") }
                        Button { showVideoPicker = true } label: { Label("Video", systemImage: "video") }
                        Button { showStickerPicker = true } label: { Label("Sticker", systemImage: "face.smiling") }
                        Button { showAudioImporter = true } label: { Label("Audio", systemImage: "music.note") }
                        Button { showDocImporter = true } label: { Label("Document", systemImage: "doc") }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(accent)
                    }

                    // Quick sticker shortcut.
                    Button { showStickerPicker = true } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22))
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

                    if canSend {
                        Button(action: sendDraft) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(accent)
                        }
                    } else {
                        // Empty draft → microphone for a voice note.
                        Button { startRecording() } label: {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(accent)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(Theme.surface.opacity(0.92))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: voice recording

    private var recordingBar: some View {
        HStack(spacing: 14) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 30)).foregroundColor(Theme.warn)
            }
            Circle().fill(Color.red).frame(width: 10, height: 10)
            Text("recording \(recorder.label)")
                .font(Theme.mono(13)).foregroundColor(Theme.text)
            Spacer()
            Button { stopAndSendRecording() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30)).foregroundColor(accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func startRecording() {
        recorder.start(onDenied: { note("microphone access denied") })
    }

    private func stopAndSendRecording() {
        guard let url = recorder.stop() else { note("recording too short"); return }
        wa.sendMedia(to: chat.jid, path: url.path, kind: "voice")
        note("sending voice…")
    }

    /// Quoted-message banner shown above the input while composing a reply.
    private func replyPreview(_ r: Message) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.fromMe ? "you" : (r.senderName.isEmpty ? "reply" : r.senderName))
                    .font(Theme.mono(10, .bold)).foregroundColor(accent)
                Text(replySnippet(r))
                    .font(Theme.mono(11)).foregroundColor(Theme.textDim).lineLimit(1)
            }
            Spacer()
            Button { replyTo = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func replySnippet(_ r: Message) -> String {
        if !r.text.isEmpty { return r.text }
        if !r.caption.isEmpty { return r.caption }
        switch r.kind {
        case "image": return "📷 photo"
        case "sticker": return "🌟 sticker"
        case "video": return "🎥 video"
        case "gif": return "🎞 gif"
        case "audio", "voice": return "🎤 audio"
        case "document": return "📎 document"
        default: return r.kind
        }
    }

    private func sendDraft() {
        guard canSend else { return }
        if let r = replyTo {
            wa.sendReply(to: chat.jid, text: draft, reply: r)
            replyTo = nil
        } else {
            wa.send(to: chat.jid, text: draft)
        }
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

    private func handleDocument(_ result: Result<[URL], Error>, kind: String) {
        guard case .success(let urls) = result, let u = urls.first else { return }
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u) else { return }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(u.lastPathComponent)
        do {
            try data.write(to: dst)
            wa.sendMedia(to: chat.jid, path: dst.path, kind: kind)
            note("sending \(kind)…")
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
    let style: ResolvedChatStyle
    let onReply: (Message) -> Void
    @EnvironmentObject var wa: WhatsAppBridge

    @State private var shareURL: ShareItem?

    private var accent: Color { style.accent }
    private var path: String? { wa.mediaPaths[msg.id].flatMap { $0.isEmpty ? nil : $0 } }
    private var isStarred: Bool { wa.starred.contains(msg.id) }
    // Stickers render as the bare (transparent) image with just a timestamp —
    // no bubble background or border.
    private var isSticker: Bool { msg.kind == "sticker" }
    private var bubbleFill: Color {
        if isSticker { return .clear }
        return msg.fromMe ? style.outBubble.opacity(style.outOpacity)
                          : style.inBubble.opacity(style.inOpacity)
    }

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
                            .foregroundColor(style.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(msg.text.isEmpty ? "—" : msg.text)
                        .font(Theme.mono(13))
                        .foregroundColor(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    if isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8)).foregroundColor(Theme.warn)
                    }
                    Text(msg.timeLabel)
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .padding(.horizontal, isSticker ? 0 : 10)
            .padding(.vertical, isSticker ? 0 : 7)
            .background(bubbleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSticker ? Color.clear : (msg.fromMe ? accent.opacity(0.35) : Theme.line),
                            lineWidth: isSticker ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: isSticker ? 0 : 10))
            .contextMenu { contextMenu }
            if !msg.fromMe { Spacer(minLength: 40) }
        }
        .onAppear {
            if msg.hasMedia && path == nil { wa.downloadMedia(msg.id) }
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(url: item.url)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button { onReply(msg) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }

        Button { wa.toggleStar(msg.id) } label: {
            Label(isStarred ? "Unstar" : "Star",
                  systemImage: isStarred ? "star.slash" : "star")
        }

        if !msg.text.isEmpty {
            Button { UIPasteboard.general.string = msg.text } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }

        if msg.isMedia, let p = path {
            let isVideo = msg.kind == "video"
            if msg.kind != "document" && msg.kind != "audio" && msg.kind != "voice" {
                Button {
                    MediaSaver.save(path: p, isVideo: isVideo) { _ in }
                } label: {
                    Label(msg.kind == "sticker" ? "Save sticker" : "Save to Photos",
                          systemImage: "square.and.arrow.down")
                }
            }
            Button { shareURL = ShareItem(url: URL(fileURLWithPath: p)) } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// Identifiable wrapper so a file URL can drive a `.sheet(item:)`.
private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

/// UIKit share sheet for exporting a media file (preserves original format).
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
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
