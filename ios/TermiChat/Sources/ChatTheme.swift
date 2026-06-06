import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

/// How a chat's background is rendered.
enum ChatBgKind: String, Codable { case none, color, image, video }

/// Per-chat appearance override (accent + background + colors). Persisted as JSON.
/// All color fields are optional hex strings; `nil` means "use the default".
struct ChatStyle: Codable, Equatable {
    var accentHex: String? = nil
    var bgKind: ChatBgKind = .none
    var bgValue: String = ""        // hex for color · file path for image/video
    var bgDim: Double? = nil        // 0…1 overlay darkness over image/video (default 0.35)
    var textHex: String? = nil      // message text color
    var inBubbleHex: String? = nil  // incoming bubble fill
    var outBubbleHex: String? = nil // outgoing (mine) bubble fill
    var bubbleOpacity: Double? = nil // bubble fill opacity (nil = auto)
}

/// Fully-resolved colors for rendering one chat (overrides → global → defaults).
struct ResolvedChatStyle {
    var accent: Color
    var text: Color
    var inBubble: Color
    var outBubble: Color
    var inOpacity: Double
    var outOpacity: Double
}

/// Stores per-conversation themes so you can give specific people (or all
/// chats, via the global key) a custom accent color, text/bubble colors and a
/// color/image/video background.
final class ChatThemeManager: ObservableObject {
    @Published private(set) var styles: [String: ChatStyle] = [:]

    static let globalKey = "__global__"
    private let key = "chat.styles.v2"

    init() { load() }

    /// Effective style for a chat, merging field-by-field: a chat-level override
    /// wins, otherwise the global value, otherwise the field default.
    func style(for jid: String) -> ChatStyle {
        let chat = styles[jid]
        let global = styles[Self.globalKey]
        guard chat != nil || global != nil else { return ChatStyle() }
        var s = ChatStyle()
        s.accentHex     = chat?.accentHex     ?? global?.accentHex
        s.textHex       = chat?.textHex       ?? global?.textHex
        s.inBubbleHex   = chat?.inBubbleHex   ?? global?.inBubbleHex
        s.outBubbleHex  = chat?.outBubbleHex  ?? global?.outBubbleHex
        s.bubbleOpacity = chat?.bubbleOpacity ?? global?.bubbleOpacity
        s.bgDim         = chat?.bgDim         ?? global?.bgDim
        // Background: a chat-level background overrides the global one entirely.
        if let c = chat, c.bgKind != .none {
            s.bgKind = c.bgKind; s.bgValue = c.bgValue
        } else if let g = global, g.bgKind != .none {
            s.bgKind = g.bgKind; s.bgValue = g.bgValue
        }
        return s
    }

    /// The exact override stored for this chat (no fallback) — for editing.
    func rawStyle(for jid: String) -> ChatStyle { styles[jid] ?? ChatStyle() }

    /// Accent color for a chat (chat override → global → app accent).
    func accent(for jid: String) -> Color {
        if let h = style(for: jid).accentHex, let c = Color(hex: h) { return c }
        return Theme.accent
    }

    /// Fully resolved colors for the message bubbles in a chat.
    func resolved(for jid: String) -> ResolvedChatStyle {
        let s = style(for: jid)
        let accent = s.accentHex.flatMap { Color(hex: $0) } ?? Theme.accent
        let text = s.textHex.flatMap { Color(hex: $0) } ?? Theme.text
        let inBubble = s.inBubbleHex.flatMap { Color(hex: $0) } ?? Theme.surfaceHi
        let outBubble = s.outBubbleHex.flatMap { Color(hex: $0) } ?? accent
        // Auto opacities preserve the original look (solid incoming, tinted mine)
        // when the user hasn't picked a custom bubble color/opacity.
        let inOp = s.bubbleOpacity ?? 1.0
        let outOp = s.bubbleOpacity ?? (s.outBubbleHex == nil ? 0.16 : 1.0)
        return ResolvedChatStyle(accent: accent, text: text, inBubble: inBubble,
                                 outBubble: outBubble, inOpacity: inOp, outOpacity: outOp)
    }

    func set(_ style: ChatStyle, for jid: String) {
        styles[jid] = style
        persist()
    }

    func clear(_ jid: String) {
        styles[jid] = nil
        persist()
    }

    /// Copies a picked background file into app storage; returns its local path.
    func saveBackgroundFile(_ data: Data, ext: String) -> String? {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + ext)
        do { try data.write(to: url); return url.path } catch { return nil }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode([String: ChatStyle].self, from: data) {
            styles = s
        }
    }
}

// MARK: - Background renderer

/// Renders the chosen background for a chat behind the message list. When the
/// chat has no background of its own it is fully transparent so the terminal
/// base shows through (no heavy panel behind the bubbles).
struct ChatBackgroundView: View {
    let jid: String
    @EnvironmentObject var chatTheme: ChatThemeManager

    var body: some View {
        let style = chatTheme.style(for: jid)
        let dim = style.bgDim ?? 0.35
        switch style.bgKind {
        case .none:
            Color.clear
        case .color:
            (Color(hex: style.bgValue) ?? Theme.bg)
        case .image:
            ZStack {
                Theme.bg
                // AnimatedImage so animated GIF/WebP backgrounds actually move;
                // still PNG/JPEG render the same way.
                AnimatedImage(path: style.bgValue, contentMode: .scaleAspectFill)
                Color.black.opacity(dim)   // keep text legible
            }
        case .video:
            ZStack {
                Theme.bg
                LoopingVideoView(path: style.bgValue)
                Color.black.opacity(dim)
            }
        }
    }
}

/// A silently-looping, muted video used as a chat background.
struct LoopingVideoView: UIViewRepresentable {
    let path: String

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(path: path)
    }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

final class LoopingPlayerUIView: UIView {
    private var looper: AVPlayerLooper?
    private let queuePlayer = AVQueuePlayer()
    private let layerView = AVPlayerLayer()

    init(path: String) {
        super.init(frame: .zero)
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        layerView.player = queuePlayer
        layerView.videoGravity = .resizeAspectFill
        layer.addSublayer(layerView)
        queuePlayer.play()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layerView.frame = bounds
    }
}
