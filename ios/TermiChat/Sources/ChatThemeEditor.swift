import SwiftUI
import PhotosUI

/// Editor for a single chat's appearance: accent color + background
/// (none / color / image / video). Reachable from the chat header menu.
struct ChatThemeEditor: View {
    let jid: String
    let title: String

    @EnvironmentObject var chatTheme: ChatThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var style: ChatStyle
    @State private var customAccent: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var applyToAll = false
    @State private var loading = false

    init(jid: String, title: String, initial: ChatStyle) {
        self.jid = jid
        self.title = title
        _style = State(initialValue: initial)
        _customAccent = State(initialValue: initial.accentHex != nil)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Divider().overlay(Theme.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("// customizing: \(title)")
                            .font(Theme.mono(11)).foregroundColor(Theme.textFaint)

                        accentSection
                        backgroundSection

                        Toggle(isOn: $applyToAll) {
                            Text("apply to all chats")
                                .font(Theme.mono(12)).foregroundColor(Theme.text)
                        }
                        .tint(Theme.accent)

                        HStack(spacing: 10) {
                            Button { save() } label: {
                                Text("[ save ]")
                                    .font(Theme.mono(13, .bold)).foregroundColor(Theme.bg)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { reset() } label: {
                                Text("[ reset ]")
                                    .font(Theme.mono(13)).foregroundColor(Theme.text)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(Theme.surfaceHi)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _ in loadPicked() }
    }

    private var topBar: some View {
        HStack {
            Text("$ chat theme").font(Theme.mono(16, .bold)).foregroundColor(Theme.accent)
            Spacer()
            Button { dismiss() } label: {
                Text("[ close ]").font(Theme.mono(12)).foregroundColor(Theme.text)
            }
        }
        .padding(16)
    }

    // MARK: accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("accent").font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            Toggle(isOn: $customAccent) {
                Text("custom accent").font(Theme.mono(12)).foregroundColor(Theme.text)
            }
            .tint(Theme.accent)
            .onChange(of: customAccent) { on in
                if !on { style.accentHex = nil }
                else if style.accentHex == nil { style.accentHex = Theme.accent.hexString }
            }
            if customAccent {
                ColorPicker(selection: accentBinding, supportsOpacity: false) {
                    Text("color").font(Theme.mono(12)).foregroundColor(Theme.text)
                }
            }
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { style.accentHex.flatMap { Color(hex: $0) } ?? Theme.accent },
            set: { style.accentHex = $0.hexString }
        )
    }

    // MARK: background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("background").font(Theme.mono(10)).foregroundColor(Theme.textFaint)

            Picker("", selection: $style.bgKind) {
                Text("none").tag(ChatBgKind.none)
                Text("color").tag(ChatBgKind.color)
                Text("image").tag(ChatBgKind.image)
                Text("video").tag(ChatBgKind.video)
            }
            .pickerStyle(.segmented)

            switch style.bgKind {
            case .none:
                Text("default terminal background")
                    .font(Theme.mono(10)).foregroundColor(Theme.textFaint)
            case .color:
                ColorPicker(selection: bgColorBinding, supportsOpacity: false) {
                    Text("color").font(Theme.mono(12)).foregroundColor(Theme.text)
                }
            case .image, .video:
                PhotosPicker(selection: $pickerItem,
                             matching: style.bgKind == .video ? .videos : .images) {
                    Text(loading ? "[ loading… ]"
                         : (style.bgValue.isEmpty ? "[ pick \(style.bgKind == .video ? "video" : "image") ]"
                            : "[ change \(style.bgKind == .video ? "video" : "image") ]"))
                        .font(Theme.mono(13)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                }
                if !style.bgValue.isEmpty {
                    Text("selected ✓").font(Theme.mono(10)).foregroundColor(Theme.accent)
                }
            }
        }
    }

    private var bgColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: style.bgValue) ?? Theme.bg },
            set: { style.bgValue = $0.hexString }
        )
    }

    private func loadPicked() {
        guard let item = pickerItem else { return }
        loading = true
        let isVideo = style.bgKind == .video
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                loading = false
                guard case .success(let data?) = result else { return }
                let ext = isVideo ? ".mp4" : ".jpg"
                if let path = chatTheme.saveBackgroundFile(data, ext: ext) {
                    style.bgValue = path
                }
            }
        }
    }

    private func save() {
        let target = applyToAll ? ChatThemeManager.globalKey : jid
        chatTheme.set(style, for: target)
        dismiss()
    }

    private func reset() {
        chatTheme.clear(jid)
        if applyToAll { chatTheme.clear(ChatThemeManager.globalKey) }
        dismiss()
    }
}
