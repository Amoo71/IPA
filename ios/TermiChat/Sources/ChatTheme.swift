import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

/// How a chat's background is rendered.
enum ChatBgKind: String, Codable { case none, color, image, video }

/// Per-chat appearance override (accent + background). Persisted as JSON.
struct ChatStyle: Codable, Equatable {
    var accentHex: String? = nil
    var bgKind: ChatBgKind = .none
    var bgValue: String = ""   // hex for color · file path for image/video
}

/// Stores per-conversation themes so you can give specific people (or all
/// chats, via the global key) a custom accent color and a color/image/video
/// background.
final class ChatThemeManager: ObservableObject {
    @Published private(set) var styles: [String: ChatStyle] = [:]

    static let globalKey = "__global__"
    private let key = "chat.styles.v1"

    init() { load() }

    /// Effective style for a chat (chat override → global → empty).
    func style(for jid: String) -> ChatStyle {
        if let s = styles[jid] { return s }
        if let g = styles[Self.globalKey] { return g }
        return ChatStyle()
    }

    /// The exact override stored for this chat (no global fallback) — for editing.
    func rawStyle(for jid: String) -> ChatStyle { styles[jid] ?? ChatStyle() }

    /// Accent color for a chat (chat override → global → app accent).
    func accent(for jid: String) -> Color {
        if let h = styles[jid]?.accentHex, let c = Color(hex: h) { return c }
        if let h = styles[Self.globalKey]?.accentHex, let c = Color(hex: h) { return c }
        return Theme.accent
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

/// Renders the chosen background for a chat behind the message list.
struct ChatBackgroundView: View {
    let jid: String
    @EnvironmentObject var chatTheme: ChatThemeManager

    var body: some View {
        let style = chatTheme.style(for: jid)
        switch style.bgKind {
        case .none:
            Theme.bg
        case .color:
            (Color(hex: style.bgValue) ?? Theme.bg)
        case .image:
            ZStack {
                Theme.bg
                if let ui = UIImage(contentsOfFile: style.bgValue) {
                    Image(uiImage: ui).resizable().scaledToFill()
                }
                Color.black.opacity(0.45)   // keep text legible
            }
        case .video:
            ZStack {
                Theme.bg
                LoopingVideoView(path: style.bgValue)
                Color.black.opacity(0.45)
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
